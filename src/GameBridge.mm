// GameBridge.mm — IL2CPP runtime calls. See GameBridge.h for the design
// and the banned-methods note. All calls go through il2cpp_runtime_invoke
// (no raw function-pointer calls, no MethodInfo* hacks). Every call is
// wrapped in try/catch and null-checked; a failure returns an error code
// and the menu shows "chua goi duoc" — results are never faked.
//
// il2cpp function pointers are resolved with dlsym(RTLD_DEFAULT) at first
// use; if the runtime symbols are not exported, the bridge reports
// UNAVAILABLE instead of crashing.
#import "GameBridge.h"

#include <dlfcn.h>
#include <string.h>
#include <pthread.h>
#include <stdint.h>

// ---- Minimal IL2CPP declarations (opaque; we never touch internals) ----
typedef struct Il2CppDomain Il2CppDomain;
typedef struct Il2CppAssembly Il2CppAssembly;
typedef struct Il2CppImage Il2CppImage;
typedef struct Il2CppClass Il2CppClass;
typedef struct Il2CppMethod Il2CppMethod;
typedef struct Il2CppField Il2CppField;
typedef struct Il2CppObject Il2CppObject;
typedef struct Il2CppType Il2CppType;
typedef struct Il2CppException Il2CppException;

typedef Il2CppDomain *(*FNDomainGet)(void);
typedef void (*FNThreadAttach)(Il2CppDomain *);
typedef Il2CppAssembly **(*FNDomainGetAssemblies)(Il2CppDomain *, size_t *);
typedef Il2CppImage *(*FNAssemblyGetImage)(Il2CppAssembly *);
typedef const char *(*FNImageGetName)(Il2CppImage *);
typedef Il2CppClass *(*FNClassFromName)(Il2CppImage *, const char *, const char *);
typedef Il2CppMethod *(*FNClassGetMethod)(Il2CppClass *, const char *, int);
typedef Il2CppField *(*FNClassGetField)(Il2CppClass *, const char *);
typedef void (*FNFieldGetValue)(Il2CppObject *, Il2CppField *, void *);
typedef const Il2CppType *(*FNClassGetType)(Il2CppClass *);
typedef Il2CppObject *(*FNTypeGetObject)(const Il2CppType *);
typedef Il2CppObject *(*FNRuntimeInvoke)(Il2CppMethod *, Il2CppObject *, void **, Il2CppObject **);
typedef void *(*FNObjectUnbox)(Il2CppObject *);
typedef Il2CppObject *(*FNObjectNew)(Il2CppClass *);

typedef struct {
    FNDomainGet domainGet;
    FNThreadAttach threadAttach;
    FNDomainGetAssemblies domainGetAssemblies;
    FNAssemblyGetImage assemblyGetImage;
    FNImageGetName imageGetName;
    FNClassFromName classFromName;
    FNClassGetMethod classGetMethod;
    FNClassGetField classGetField;
    FNFieldGetValue fieldGetValue;
    FNClassGetType classGetType;
    FNTypeGetObject typeGetObject;
    FNRuntimeInvoke runtimeInvoke;
    FNObjectUnbox objectUnbox;
    FNObjectNew objectNew;
    int loaded; // 1 = all required symbols resolved
} Il2CppApi;

static Il2CppApi s_api;
static pthread_once_t s_apiOnce = PTHREAD_ONCE_INIT;

static void LoadApi(void) {
    memset(&s_api, 0, sizeof(s_api));
    s_api.domainGet = (FNDomainGet)dlsym(RTLD_DEFAULT, "il2cpp_domain_get");
    s_api.threadAttach = (FNThreadAttach)dlsym(RTLD_DEFAULT, "il2cpp_thread_attach");
    s_api.domainGetAssemblies = (FNDomainGetAssemblies)dlsym(RTLD_DEFAULT, "il2cpp_domain_get_assemblies");
    s_api.assemblyGetImage = (FNAssemblyGetImage)dlsym(RTLD_DEFAULT, "il2cpp_assembly_get_image");
    s_api.imageGetName = (FNImageGetName)dlsym(RTLD_DEFAULT, "il2cpp_image_get_name");
    s_api.classFromName = (FNClassFromName)dlsym(RTLD_DEFAULT, "il2cpp_class_from_name");
    s_api.classGetMethod = (FNClassGetMethod)dlsym(RTLD_DEFAULT, "il2cpp_class_get_method_from_name");
    s_api.classGetField = (FNClassGetField)dlsym(RTLD_DEFAULT, "il2cpp_class_get_field_from_name");
    s_api.fieldGetValue = (FNFieldGetValue)dlsym(RTLD_DEFAULT, "il2cpp_field_get_value");
    s_api.classGetType = (FNClassGetType)dlsym(RTLD_DEFAULT, "il2cpp_class_get_type");
    s_api.typeGetObject = (FNTypeGetObject)dlsym(RTLD_DEFAULT, "il2cpp_type_get_object");
    s_api.runtimeInvoke = (FNRuntimeInvoke)dlsym(RTLD_DEFAULT, "il2cpp_runtime_invoke");
    s_api.objectUnbox = (FNObjectUnbox)dlsym(RTLD_DEFAULT, "il2cpp_object_unbox");
    s_api.objectNew = (FNObjectNew)dlsym(RTLD_DEFAULT, "il2cpp_object_new");
    // object_unbox / object_new are optional niceties; the rest are required.
    s_api.loaded = (s_api.domainGet && s_api.threadAttach && s_api.domainGetAssemblies &&
                    s_api.assemblyGetImage && s_api.imageGetName && s_api.classFromName &&
                    s_api.classGetMethod && s_api.classGetField && s_api.fieldGetValue &&
                    s_api.classGetType && s_api.typeGetObject && s_api.runtimeInvoke) ? 1 : 0;
    if (s_api.loaded) {
        Il2CppDomain *domain = s_api.domainGet();
        if (domain) {
            @try { s_api.threadAttach(domain); } @catch (...) {}
        }
    }
}

static Il2CppApi *Api(void) {
    pthread_once(&s_apiOnce, LoadApi);
    return &s_api;
}

const char *FTC_CallResultMessage(FTC_CallResult r) {
    switch (r) {
        case FTC_CALL_OK: return "OK";
        case FTC_CALL_ERR_UNAVAILABLE: return "Chua goi duoc: IL2CPP runtime chua san sang";
        case FTC_CALL_ERR_NO_INSTANCE: return "Chua goi duoc: chua tim thay dev tools trong game (thu mo menu tam dung trong game roi bam lai)";
        case FTC_CALL_ERR_NO_METHOD: return "Chua goi duoc: khong tim thay ham trong game";
        case FTC_CALL_ERR_EXCEPTION: return "Game bao loi khi chay lenh";
        case FTC_CALL_ERR_RETURNED_FALSE: return "Game tu choi lenh (chua du dieu kien trong game)";
        default: return "Loi khong ro";
    }
}

// ---- Image / class lookup ----
static Il2CppImage *FindImage(const char *imageName) {
    Il2CppApi *api = Api();
    if (!api->loaded) return NULL;
    Il2CppDomain *domain = api->domainGet();
    if (!domain) return NULL;
    size_t count = 0;
    Il2CppAssembly **assemblies = api->domainGetAssemblies(domain, &count);
    if (!assemblies) return NULL;
    for (size_t i = 0; i < count; i++) {
        Il2CppImage *image = api->assemblyGetImage(assemblies[i]);
        if (!image) continue;
        const char *name = api->imageGetName(image);
        if (name && strcmp(name, imageName) == 0) return image;
    }
    return NULL;
}

static Il2CppClass *FindClass(const char *imageName, const char *ns, const char *name) {
    Il2CppImage *image = FindImage(imageName);
    if (!image) return NULL;
    return Api()->classFromName(image, ns, name);
}

static Il2CppObject *ReadObjectField(Il2CppObject *obj, Il2CppClass *klass, const char *fieldName) {
    if (!obj || !klass) return NULL;
    Il2CppField *field = Api()->classGetField(klass, fieldName);
    if (!field) return NULL;
    Il2CppObject *value = NULL;
    Api()->fieldGetValue(obj, field, &value);
    return value;
}

// ---- Instance resolution ----
// Primary: ForgePauseMenu (MonoBehaviour) -> developerPage -> tools.
// Fallback: ForgeRoom (MonoBehaviour) -> new ForgeDeveloperTools(room).
//
// NO CACHING (AEGIS fix): earlier versions kept s_toolsCache /
// s_campaignCache forever after the first resolve. If the game destroys
// and recreates the pause menu / room / campaign (scene reload, run
// reset), a cached Il2CppObject* becomes a dangling pointer and the next
// runtime_invoke on it can crash instead of reporting NO_INSTANCE.
// So ResolveTools()/ResolveCampaign() re-resolve FRESH on every call and
// never store the result. These calls only happen when the user taps a
// menu button (never per-frame), so the extra FindObjectOfType cost is
// negligible. No code path may hold an Il2CppObject* across calls.
static Il2CppObject *FindUnityObject(Il2CppClass *klass) {
    // UnityEngine.Object.FindObjectOfType(Type, bool includeInactive)
    Il2CppApi *api = Api();
    Il2CppClass *objectClass = FindClass("UnityEngine.CoreModule", "UnityEngine", "Object");
    if (!objectClass) return NULL;
    Il2CppMethod *find = api->classGetMethod(objectClass, "FindObjectOfType", 2);
    if (!find) return NULL;
    Il2CppObject *typeObj = api->typeGetObject(api->classGetType(klass));
    if (!typeObj) return NULL;
    bool includeInactive = false;
    void *args[2] = { &typeObj, &includeInactive };
    Il2CppObject *exc = NULL;
    Il2CppObject *found = NULL;
    @try {
        found = api->runtimeInvoke(find, NULL, args, &exc);
    } @catch (...) {
        return NULL;
    }
    if (exc) return NULL;
    return found;
}

static Il2CppObject *ResolveTools(void) {
    Il2CppApi *api = Api();
    if (!api->loaded) return NULL;

    // Path 1: pause menu chain.
    Il2CppClass *pauseClass = FindClass("Assembly-CSharp", "ForgeTax.Menu", "ForgePauseMenu");
    Il2CppClass *pageClass = FindClass("Assembly-CSharp", "ForgeTax.Touch", "ForgeDeveloperPage");
    if (pauseClass && pageClass) {
        Il2CppObject *pause = FindUnityObject(pauseClass);
        if (pause) {
            Il2CppObject *page = ReadObjectField(pause, pauseClass, "developerPage");
            if (page) {
                Il2CppObject *tools = ReadObjectField(page, pageClass, "tools");
                if (tools) return tools;
            }
        }
    }
    // Path 2: build a tools instance from the live ForgeRoom.
    // (ForgeDeveloperTools.ctor(ForgeRoom) — dump.cs RVA 0x263C4E8.)
    // NOTE: unproven live — the dev page may be the only intended owner.
    // If construction fails, we report NO_INSTANCE; nothing is faked.
    Il2CppClass *toolsClass = FindClass("Assembly-CSharp", "ForgeTax.Touch", "ForgeDeveloperTools");
    Il2CppClass *roomClass = FindClass("Assembly-CSharp", "ForgeTax.Room", "ForgeRoom");
    if (toolsClass && roomClass && api->objectNew) {
        Il2CppObject *room = FindUnityObject(roomClass);
        if (room) {
            Il2CppMethod *ctor = api->classGetMethod(toolsClass, ".ctor", 1);
            if (ctor) {
                Il2CppObject *tools = api->objectNew(toolsClass);
                if (tools) {
                    void *args[1] = { &room };
                    Il2CppObject *exc = NULL;
                    @try { api->runtimeInvoke(ctor, tools, args, &exc); } @catch (...) { exc = (Il2CppObject *)1; }
                    if (!exc) return tools;
                }
            }
        }
    }
    return NULL;
}

static Il2CppObject *ResolveCampaign(void) {
    // Fresh resolve every call (see the NO CACHING note above): the
    // campaign object is re-read from the live tools -> room chain, so a
    // destroyed/recreated campaign can never be invoked through a stale
    // cached pointer.
    Il2CppObject *tools = ResolveTools();
    if (!tools) return NULL;
    Il2CppClass *toolsClass = FindClass("Assembly-CSharp", "ForgeTax.Touch", "ForgeDeveloperTools");
    Il2CppClass *roomClass = FindClass("Assembly-CSharp", "ForgeTax.Room", "ForgeRoom");
    if (!toolsClass || !roomClass) return NULL;
    Il2CppObject *room = ReadObjectField(tools, toolsClass, "room");
    if (!room) return NULL;
    Il2CppObject *campaign = ReadObjectField(room, roomClass, "campaign");
    return campaign;
}

bool FTC_BridgeReady(void) {
    return Api()->loaded && FindImage("Assembly-CSharp") != NULL;
}

bool FTC_ToolsAvailable(void) {
    return ResolveTools() != NULL;
}

// ---- Generic invoke ----
// Calls a bool method on `obj` (or a static method when obj == NULL).
// Returns OK only when: no exception AND (no return value OR boxed bool true
// OR unbox unavailable, in which case no-exception counts as success).
static FTC_CallResult InvokeBool(Il2CppClass *klass, Il2CppObject *obj,
                                 const char *methodName, int argc, void **args) {
    Il2CppApi *api = Api();
    if (!api->loaded) return FTC_CALL_ERR_UNAVAILABLE;
    if (!klass) return FTC_CALL_ERR_NO_METHOD;
    Il2CppMethod *method = NULL;
    @try { method = api->classGetMethod(klass, methodName, argc); } @catch (...) { return FTC_CALL_ERR_NO_METHOD; }
    if (!method) return FTC_CALL_ERR_NO_METHOD;
    Il2CppObject *exc = NULL;
    Il2CppObject *ret = NULL;
    @try { ret = api->runtimeInvoke(method, obj, args, &exc); } @catch (...) { return FTC_CALL_ERR_EXCEPTION; }
    if (exc) return FTC_CALL_ERR_EXCEPTION;
    if (!ret) return FTC_CALL_OK; // void method
    if (api->objectUnbox) {
        bool *boxed = NULL;
        @try { boxed = (bool *)api->objectUnbox(ret); } @catch (...) { return FTC_CALL_OK; }
        if (boxed && !*boxed) return FTC_CALL_ERR_RETURNED_FALSE;
    }
    return FTC_CALL_OK;
}

static Il2CppClass *ToolsClass(void) {
    return FindClass("Assembly-CSharp", "ForgeTax.Touch", "ForgeDeveloperTools");
}

static FTC_CallResult InvokeTools0(const char *methodName) {
    Il2CppObject *tools = ResolveTools();
    if (!tools) return FTC_CALL_ERR_NO_INSTANCE;
    return InvokeBool(ToolsClass(), tools, methodName, 0, NULL);
}

static FTC_CallResult InvokeToolsDouble(const char *methodName, double value) {
    Il2CppObject *tools = ResolveTools();
    if (!tools) return FTC_CALL_ERR_NO_INSTANCE;
    void *args[1] = { &value };
    return InvokeBool(ToolsClass(), tools, methodName, 1, args);
}

static FTC_CallResult InvokeToolsInt(const char *methodName, int value) {
    Il2CppObject *tools = ResolveTools();
    if (!tools) return FTC_CALL_ERR_NO_INSTANCE;
    void *args[1] = { &value };
    return InvokeBool(ToolsClass(), tools, methodName, 1, args);
}

// ---- Public calls (one per feature) ----
FTC_CallResult FTC_AddGold(double amount) { return InvokeToolsDouble("AddGold", amount); }
FTC_CallResult FTC_GiveAllRelics(void) { return InvokeTools0("GiveAllRelics"); }
FTC_CallResult FTC_CycleForgeMode(void) { return InvokeTools0("CycleForgeMode"); }
FTC_CallResult FTC_SetAnvilGrade(int grade) { return InvokeToolsInt("SetAnvilGrade", grade); }
FTC_CallResult FTC_ToggleGodMode(void) { return InvokeTools0("ToggleGodMode"); }
FTC_CallResult FTC_KillDragon(void) { return InvokeTools0("KillDragon"); }
FTC_CallResult FTC_SummonMerchant(void) { return InvokeTools0("SummonMerchant"); }
FTC_CallResult FTC_JumpToDay(int day) { return InvokeToolsInt("JumpToDay", day); }
FTC_CallResult FTC_FillFever(void) { return InvokeTools0("FillFever"); }
FTC_CallResult FTC_AddSwordCredits(void) { return InvokeTools0("AddSwordCredits"); }
FTC_CallResult FTC_GiveSecretDoorKey(void) { return InvokeTools0("GiveSecretDoorKey"); }
FTC_CallResult FTC_EnterSkillArena(void) { return InvokeTools0("EnterSkillArena"); }
FTC_CallResult FTC_OpenSwordPicker(void) { return InvokeTools0("OpenSwordPicker"); }
FTC_CallResult FTC_RevealCodex(void) { return InvokeTools0("RevealCodex"); }
FTC_CallResult FTC_ResetRun(void) { return InvokeTools0("ResetRun"); }
FTC_CallResult FTC_SkipDay(void) { return InvokeTools0("SkipDay"); }
FTC_CallResult FTC_NextDay(void) { return InvokeTools0("NextDay"); }
FTC_CallResult FTC_StartDragonFight(void) { return InvokeTools0("StartDragonFight"); }
FTC_CallResult FTC_ForceDragonLoss(void) { return InvokeTools0("ForceDragonLoss"); }
FTC_CallResult FTC_OpenArmory(void) { return InvokeTools0("OpenArmory"); }
FTC_CallResult FTC_ToggleMerchantShelfSlot(void) { return InvokeTools0("ToggleMerchantShelfSlot"); }
FTC_CallResult FTC_ToggleFps(void) { return InvokeTools0("ToggleFps"); }

FTC_CallResult FTC_SetQualityTier(int tier) {
    // SetQualityTier(Nullable<QualityTier>) — QualityTier: Low=0, Mid=1,
    // High=2 (dump.cs, ForgeTax.Quality). Nullable<T> is passed as a
    // struct { int32 value; bool has_value } by pointer to runtime_invoke.
    // Layout is the standard IL2CPP Nullable layout; UNPROVEN live — if
    // the game rejects it, this returns EXCEPTION / RETURNED_FALSE.
    if (tier < 0) tier = 0;
    if (tier > 2) tier = 2;
    Il2CppObject *tools = ResolveTools();
    if (!tools) return FTC_CALL_ERR_NO_INSTANCE;
    struct { int32_t value; uint8_t hasValue; uint8_t pad[3]; } nullable;
    nullable.value = (int32_t)tier;
    nullable.hasValue = 1;
    nullable.pad[0] = nullable.pad[1] = nullable.pad[2] = 0;
    void *args[1] = { &nullable };
    return InvokeBool(ToolsClass(), tools, "SetQualityTier", 1, args);
}

FTC_CallResult FTC_AddRunTickets(int outcome, int count) {
    // ForgeCampaign.AddRunTickets(int outcome, int count).
    // ForgeOutcome: Destruction=0, Damage=1, Hold=2, Success=3, GreatSuccess=4.
    Il2CppObject *campaign = ResolveCampaign();
    if (!campaign) return FTC_CALL_ERR_NO_INSTANCE;
    Il2CppClass *campaignClass = FindClass("Assembly-CSharp", "ForgeTax.Rules", "ForgeCampaign");
    if (!campaignClass) return FTC_CALL_ERR_NO_METHOD;
    void *args[2] = { &outcome, &count };
    return InvokeBool(campaignClass, campaign, "AddRunTickets", 2, args);
}
