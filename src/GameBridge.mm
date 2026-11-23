// GameBridge.mm — IL2CPP runtime calls. See GameBridge.h for the design
// and the banned-methods note. All calls go through il2cpp_runtime_invoke
// (no raw function-pointer calls, no MethodInfo* hacks). Every call is
// wrapped in try/catch and null-checked; a failure returns an error code
// and the menu shows "chua goi duoc" — results are never faked.
//
// il2cpp function pointers are resolved with dlsym(RTLD_DEFAULT) lazily;
// because the thin iOS launcher loads UnityFramework dynamically, lookup
// retries until UnityFramework's exports are present instead of latching
// a permanent failure.
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
typedef struct Il2CppThread Il2CppThread;

typedef Il2CppDomain *(*FNDomainGet)(void);
typedef Il2CppThread *(*FNThreadCurrent)(void);
typedef Il2CppThread *(*FNThreadAttach)(Il2CppDomain *);
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
typedef Il2CppClass *(*FNObjectGetClass)(Il2CppObject *);

typedef struct {
    FNDomainGet domainGet;
    FNThreadCurrent threadCurrent;
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
    FNObjectGetClass objectGetClass;
    int loaded; // 1 = all required symbols resolved
} Il2CppApi;

static Il2CppApi s_api;
static pthread_mutex_t s_apiMutex = PTHREAD_MUTEX_INITIALIZER;

static void TryLoadApiLocked(void) {
    if (s_api.loaded) return;
    memset(&s_api, 0, sizeof(s_api));
    s_api.domainGet = (FNDomainGet)dlsym(RTLD_DEFAULT, "il2cpp_domain_get");
    s_api.threadCurrent = (FNThreadCurrent)dlsym(RTLD_DEFAULT, "il2cpp_thread_current");
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
    s_api.objectGetClass = (FNObjectGetClass)dlsym(RTLD_DEFAULT, "il2cpp_object_get_class");
    // object_unbox / object_new / object_get_class / thread_current are optional;
    // the rest are required.
    s_api.loaded = (s_api.domainGet && s_api.threadAttach && s_api.domainGetAssemblies &&
                    s_api.assemblyGetImage && s_api.imageGetName && s_api.classFromName &&
                    s_api.classGetMethod && s_api.classGetField && s_api.fieldGetValue &&
                    s_api.classGetType && s_api.typeGetObject && s_api.runtimeInvoke) ? 1 : 0;
}

static Il2CppApi *Api(void) {
    if (!s_api.loaded) {
        pthread_mutex_lock(&s_apiMutex);
        TryLoadApiLocked();
        pthread_mutex_unlock(&s_apiMutex);
    }
    if (s_api.loaded) {
        Il2CppDomain *domain = s_api.domainGet();
        if (domain && (!s_api.threadCurrent || s_api.threadCurrent() == NULL)) {
            @try { s_api.threadAttach(domain); } @catch (...) {}
        }
    }
    return &s_api;
}

const char *FTC_CallResultMessage(FTC_CallResult r) {
    switch (r) {
        case FTC_CALL_OK: return "OK";
        case FTC_CALL_ERR_UNAVAILABLE: return "Chua goi duoc: IL2CPP runtime chua san sang";
        case FTC_CALL_ERR_NO_INSTANCE: return "Chua goi duoc: chua tim thay dev tools trong game (thu vao man choi hoac mo menu tam dung roi bam lai)";
        case FTC_CALL_ERR_NO_METHOD: return "Chua goi duoc: khong tim thay ham trong game";
        case FTC_CALL_ERR_EXCEPTION: return "Game bao loi khi chay lenh";
        case FTC_CALL_ERR_RETURNED_FALSE: return "Game tu choi lenh (chua du dieu kien trong game)";
        default: return "Loi khong ro";
    }
}

// ---- Image / class lookup ----
// il2cpp_image_get_name returns names WITH the ".dll" extension in Unity 6
// (e.g. "Assembly-CSharp.dll", "UnityEngine.CoreModule.dll", "ForgeTax.Rules.dll").
// Match both with and without ".dll" so callers never miss on suffix mismatch.
static bool ImageNameMatches(const char *actual, const char *wanted) {
    if (!actual || !wanted) return false;
    if (strcmp(actual, wanted) == 0) return true;
    size_t alen = strlen(actual);
    size_t wlen = strlen(wanted);
    if (alen == wlen + 4 && strncmp(actual, wanted, wlen) == 0 && strcmp(actual + wlen, ".dll") == 0) {
        return true;
    }
    if (wlen == alen + 4 && strncmp(wanted, actual, alen) == 0 && strcmp(wanted + alen, ".dll") == 0) {
        return true;
    }
    return false;
}

static Il2CppImage *FindImage(const char *imageName) {
    Il2CppApi *api = Api();
    if (!api->loaded || !imageName) return NULL;
    Il2CppDomain *domain = api->domainGet();
    if (!domain) return NULL;
    size_t count = 0;
    Il2CppAssembly **assemblies = api->domainGetAssemblies(domain, &count);
    if (!assemblies) return NULL;
    for (size_t i = 0; i < count; i++) {
        Il2CppImage *image = api->assemblyGetImage(assemblies[i]);
        if (!image) continue;
        const char *name = api->imageGetName(image);
        if (ImageNameMatches(name, imageName)) return image;
    }
    return NULL;
}

static Il2CppClass *FindClass(const char *imageName, const char *ns, const char *name) {
    Il2CppApi *api = Api();
    if (!api->loaded || !name) return NULL;
    if (!ns) ns = "";
    if (imageName) {
        Il2CppImage *image = FindImage(imageName);
        if (image) {
            Il2CppClass *klass = api->classFromName(image, ns, name);
            if (klass) return klass;
        }
    }
    // Fallback: scan all loaded assemblies (handles split asmdefs like ForgeTax.Rules.dll).
    Il2CppDomain *domain = api->domainGet();
    if (!domain) return NULL;
    size_t count = 0;
    Il2CppAssembly **assemblies = api->domainGetAssemblies(domain, &count);
    if (!assemblies) return NULL;
    for (size_t i = 0; i < count; i++) {
        Il2CppImage *image = api->assemblyGetImage(assemblies[i]);
        if (!image) continue;
        Il2CppClass *klass = api->classFromName(image, ns, name);
        if (klass) return klass;
    }
    return NULL;
}

static Il2CppObject *ReadObjectField(Il2CppObject *obj, Il2CppClass *klass, const char *fieldName) {
    if (!obj || !klass || !fieldName) return NULL;
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
// NO CACHING (AEGIS fix): ResolveTools()/ResolveCampaign() re-resolve FRESH
// on every call and never store an Il2CppObject* across calls, so a scene
// reload or run reset can never leave a dangling pointer.
static Il2CppObject *FindUnityObject(Il2CppClass *klass) {
    if (!klass) return NULL;
    // UnityEngine.Object.FindObjectOfType(Type type, bool includeInactive)
    Il2CppApi *api = Api();
    if (!api->loaded) return NULL;
    Il2CppClass *objectClass = FindClass("UnityEngine.CoreModule.dll", "UnityEngine", "Object");
    if (!objectClass) return NULL;
    Il2CppMethod *find = api->classGetMethod(objectClass, "FindObjectOfType", 2);
    if (!find) return NULL;
    const Il2CppType *rawType = api->classGetType(klass);
    if (!rawType) return NULL;
    Il2CppObject *typeObj = api->typeGetObject(rawType);
    if (!typeObj) return NULL;
    // includeInactive = true so inactive menus/components are still found.
    // IMPORTANT: in IL2CPP runtime_invoke, reference-type args (System.Type)
    // are passed directly as the Il2CppObject* pointer, while value-type args
    // (bool) are passed by address (&includeInactive).
    uint8_t includeInactive = 1;
    void *args[2] = { typeObj, &includeInactive };
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
    Il2CppClass *pauseClass = FindClass("Assembly-CSharp.dll", "ForgeTax.Menu", "ForgePauseMenu");
    Il2CppClass *pageClass = FindClass("Assembly-CSharp.dll", "ForgeTax.Touch", "ForgeDeveloperPage");
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
    // (ForgeDeveloperTools..ctor(ForgeRoom) — dump.cs RVA 0x263C4E8.)
    Il2CppClass *toolsClass = FindClass("Assembly-CSharp.dll", "ForgeTax.Touch", "ForgeDeveloperTools");
    Il2CppClass *roomClass = FindClass("Assembly-CSharp.dll", "ForgeTax.Room", "ForgeRoom");
    if (toolsClass && roomClass && api->objectNew) {
        Il2CppObject *room = FindUnityObject(roomClass);
        if (room) {
            Il2CppMethod *ctor = api->classGetMethod(toolsClass, ".ctor", 1);
            if (ctor) {
                Il2CppObject *tools = api->objectNew(toolsClass);
                if (tools) {
                    // Reference-type param: pass `room` directly (NOT &room).
                    void *args[1] = { room };
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
    // Fresh resolve every call (see NO CACHING note above).
    Il2CppClass *roomClass = FindClass("Assembly-CSharp.dll", "ForgeTax.Room", "ForgeRoom");
    if (roomClass) {
        Il2CppObject *room = FindUnityObject(roomClass);
        if (room) {
            Il2CppObject *campaign = ReadObjectField(room, roomClass, "campaign");
            if (campaign) return campaign;
        }
    }
    Il2CppObject *tools = ResolveTools();
    if (!tools) return NULL;
    Il2CppClass *toolsClass = FindClass("Assembly-CSharp.dll", "ForgeTax.Touch", "ForgeDeveloperTools");
    if (!toolsClass || !roomClass) return NULL;
    Il2CppObject *room = ReadObjectField(tools, toolsClass, "room");
    if (!room) return NULL;
    return ReadObjectField(room, roomClass, "campaign");
}

bool FTC_BridgeReady(void) {
    return Api()->loaded && FindImage("Assembly-CSharp.dll") != NULL;
}

bool FTC_ToolsAvailable(void) {
    return ResolveTools() != NULL;
}

// ---- Generic invoke ----
// Calls a bool (or void) method on `obj` (or a static method when obj == NULL).
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
        uint8_t *boxed = NULL;
        @try { boxed = (uint8_t *)api->objectUnbox(ret); } @catch (...) { return FTC_CALL_OK; }
        if (boxed && (*boxed == 0)) return FTC_CALL_ERR_RETURNED_FALSE;
    }
    return FTC_CALL_OK;
}

static Il2CppClass *ToolsClass(void) {
    return FindClass("Assembly-CSharp.dll", "ForgeTax.Touch", "ForgeDeveloperTools");
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
    int32_t v = (int32_t)value;
    void *args[1] = { &v };
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

FTC_CallResult FTC_SetAntiLag(bool enabled) {
    // Extreme Max-FPS / Anti-Lag boost via pure static IL2CPP calls (no __TEXT
    // patch, works natively on TrollStore without JIT):
    //   - Application.set_targetFrameRate(120) -> unlocks 120 FPS on ProMotion
    //     and prevents Unity from throttling down to 30 FPS on 60 Hz iPhone 7 Plus.
    //   - QualitySettings: vSyncCount=0, antiAliasing=0 (MSAA off),
    //     globalTextureMipmapLimit=1 (cuts 3D texture bandwidth ~75%),
    //     enableLODCrossFade=false.
    //   - ScalableBufferManager.ResizeBuffers(0.8, 0.8) -> lighter GPU fillrate.
    //   - ForgeQualityTier.Force(Low) -> lowers game's own FX/shader tier
    //     (restored to Auto/null when disabled).
    Il2CppApi *api = Api();
    if (!api->loaded) return FTC_CALL_ERR_UNAVAILABLE;

    bool anyOk = false;
    Il2CppClass *appClass = FindClass("UnityEngine.CoreModule.dll", "UnityEngine", "Application");
    if (appClass) {
        int32_t fps = enabled ? 120 : 60;
        void *args[1] = { &fps };
        if (InvokeBool(appClass, NULL, "set_targetFrameRate", 1, args) == FTC_CALL_OK) {
            anyOk = true;
        }
    }
    Il2CppClass *qsClass = FindClass("UnityEngine.CoreModule.dll", "UnityEngine", "QualitySettings");
    if (qsClass) {
        int32_t vsync = enabled ? 0 : 1;
        void *vsArgs[1] = { &vsync };
        if (InvokeBool(qsClass, NULL, "set_vSyncCount", 1, vsArgs) == FTC_CALL_OK) {
            anyOk = true;
        }
        int32_t aa = enabled ? 0 : 2;
        void *aaArgs[1] = { &aa };
        if (InvokeBool(qsClass, NULL, "set_antiAliasing", 1, aaArgs) == FTC_CALL_OK) {
            anyOk = true;
        }
        int32_t mip = enabled ? 1 : 0;
        void *mipArgs[1] = { &mip };
        InvokeBool(qsClass, NULL, "set_globalTextureMipmapLimit", 1, mipArgs);

        uint8_t lodFade = enabled ? 0 : 1;
        void *lodArgs[1] = { &lodFade };
        InvokeBool(qsClass, NULL, "set_enableLODCrossFade", 1, lodArgs);
    }
    Il2CppClass *sbmClass = FindClass("UnityEngine.CoreModule.dll", "UnityEngine", "ScalableBufferManager");
    if (sbmClass) {
        float scale = enabled ? 0.80f : 1.0f;
        void *sArgs[2] = { &scale, &scale };
        InvokeBool(sbmClass, NULL, "ResizeBuffers", 2, sArgs);
    }
    Il2CppClass *qtClass = FindClass("Assembly-CSharp.dll", "ForgeTax.Quality", "ForgeQualityTier");
    if (qtClass) {
        struct {
            uint8_t hasValue;
            uint8_t pad[3];
            int32_t value;
        } nullable;
        nullable.hasValue = enabled ? 1 : 0;
        nullable.pad[0] = nullable.pad[1] = nullable.pad[2] = 0;
        nullable.value = 0; // Low
        void *qArgs[1] = { &nullable };
        if (InvokeBool(qtClass, NULL, "Force", 1, qArgs) == FTC_CALL_OK) {
            anyOk = true;
        }
    }
    return anyOk ? FTC_CALL_OK : FTC_CALL_ERR_NO_METHOD;
}

FTC_CallResult FTC_SetTimeScale(float scale) {
    // Pure static UnityEngine.Time.set_timeScale(float) — works natively on
    // TrollStore without JIT. Clamped to [0.5, 4.0] for stability.
    if (scale < 0.5f) scale = 0.5f;
    if (scale > 4.0f) scale = 4.0f;
    Il2CppApi *api = Api();
    if (!api->loaded) return FTC_CALL_ERR_UNAVAILABLE;
    Il2CppClass *timeClass = FindClass("UnityEngine.CoreModule.dll", "UnityEngine", "Time");
    if (!timeClass) return FTC_CALL_ERR_NO_METHOD;
    void *args[1] = { &scale };
    return InvokeBool(timeClass, NULL, "set_timeScale", 1, args);
}

FTC_CallResult FTC_SetQualityTier(int tier) {
    // SetQualityTier(Nullable<QualityTier>) — QualityTier: Low=0, Mid=1, High=2.
    // Verified from global-metadata.dat (mscorlib.dll System.Nullable`1) AND
    // ARM64 disassembly at 0x24ef138 (tbz w19,#0) / 0x2edd5d4 (ldrb w8,[x0,#0]):
    // field 0 = hasValue (bool at +0), field 1 = value (int32 at +4).
    if (tier < 0) tier = 0;
    if (tier > 2) tier = 2;
    struct {
        uint8_t hasValue;
        uint8_t pad[3];
        int32_t value;
    } nullable;
    nullable.hasValue = 1;
    nullable.pad[0] = nullable.pad[1] = nullable.pad[2] = 0;
    nullable.value = (int32_t)tier;
    void *args[1] = { &nullable };
    Il2CppObject *tools = ResolveTools();
    if (tools) {
        FTC_CallResult cr = InvokeBool(ToolsClass(), tools, "SetQualityTier", 1, args);
        if (cr == FTC_CALL_OK) return cr;
    }
    // Static fallback so #32 works on any screen (even before ForgeRoom loads).
    Il2CppClass *qtClass = FindClass("Assembly-CSharp.dll", "ForgeTax.Quality", "ForgeQualityTier");
    if (!qtClass) return tools ? FTC_CALL_ERR_NO_METHOD : FTC_CALL_ERR_NO_INSTANCE;
    return InvokeBool(qtClass, NULL, "Force", 1, args);
}

FTC_CallResult FTC_AddRunTickets(int outcome, int count) {
    // ForgeCampaign.AddRunTickets(int outcome, int count) in ForgeTax.Rules.dll.
    // ForgeOutcome: Destruction=0, Damage=1, Hold=2, Success=3, GreatSuccess=4.
    Il2CppObject *campaign = ResolveCampaign();
    if (!campaign) return FTC_CALL_ERR_NO_INSTANCE;
    Il2CppApi *api = Api();
    Il2CppClass *campaignClass = (api->objectGetClass)
        ? api->objectGetClass(campaign)
        : FindClass("ForgeTax.Rules.dll", "ForgeTax.Rules", "ForgeCampaign");
    if (!campaignClass) {
        campaignClass = FindClass("ForgeTax.Rules.dll", "ForgeTax.Rules", "ForgeCampaign");
    }
    if (!campaignClass) return FTC_CALL_ERR_NO_METHOD;
    int32_t o = (int32_t)outcome;
    int32_t c = (int32_t)count;
    void *args[2] = { &o, &c };
    return InvokeBool(campaignClass, campaign, "AddRunTickets", 2, args);
}
