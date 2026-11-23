// GameBridge.mm — IL2CPP runtime calls. See GameBridge.h for the design.
// All calls go through il2cpp_runtime_invoke / il2cpp_field_{get,set}_value
// with full null checks and try/catch guards.
#import "GameBridge.h"

#include <dlfcn.h>
#include <string.h>
#include <pthread.h>
#include <stdint.h>

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
typedef void (*FNFieldSetValue)(Il2CppObject *, Il2CppField *, void *);
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
    FNFieldSetValue fieldSetValue;
    FNClassGetType classGetType;
    FNTypeGetObject typeGetObject;
    FNRuntimeInvoke runtimeInvoke;
    FNObjectUnbox objectUnbox;
    FNObjectNew objectNew;
    FNObjectGetClass objectGetClass;
    int loaded;
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
    s_api.fieldSetValue = (FNFieldSetValue)dlsym(RTLD_DEFAULT, "il2cpp_field_set_value");
    s_api.classGetType = (FNClassGetType)dlsym(RTLD_DEFAULT, "il2cpp_class_get_type");
    s_api.typeGetObject = (FNTypeGetObject)dlsym(RTLD_DEFAULT, "il2cpp_type_get_object");
    s_api.runtimeInvoke = (FNRuntimeInvoke)dlsym(RTLD_DEFAULT, "il2cpp_runtime_invoke");
    s_api.objectUnbox = (FNObjectUnbox)dlsym(RTLD_DEFAULT, "il2cpp_object_unbox");
    s_api.objectNew = (FNObjectNew)dlsym(RTLD_DEFAULT, "il2cpp_object_new");
    s_api.objectGetClass = (FNObjectGetClass)dlsym(RTLD_DEFAULT, "il2cpp_object_get_class");
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

const char *FTC_CallResultMessageLang(FTC_CallResult r, bool english) {
    if (english) {
        switch (r) {
            case FTC_CALL_OK: return "OK";
            case FTC_CALL_ERR_UNAVAILABLE: return "IL2CPP runtime not ready yet";
            case FTC_CALL_ERR_NO_INSTANCE: return "Enter gameplay first, then tap again";
            case FTC_CALL_ERR_NO_METHOD: return "Game method not found";
            case FTC_CALL_ERR_EXCEPTION: return "Game threw an error";
            case FTC_CALL_ERR_RETURNED_FALSE: return "Precondition not met in game";
            default: return "Unknown error";
        }
    }
    switch (r) {
        case FTC_CALL_OK: return "OK";
        case FTC_CALL_ERR_UNAVAILABLE: return "IL2CPP chưa sẵn sàng";
        case FTC_CALL_ERR_NO_INSTANCE: return "Hãy vào màn chơi trước rồi bấm lại";
        case FTC_CALL_ERR_NO_METHOD: return "Không tìm thấy hàm trong game";
        case FTC_CALL_ERR_EXCEPTION: return "Game báo lỗi khi thực thi";
        case FTC_CALL_ERR_RETURNED_FALSE: return "Chưa đủ điều kiện trong game";
        default: return "Lỗi không rõ";
    }
}

const char *FTC_CallResultMessage(FTC_CallResult r) {
    return FTC_CallResultMessageLang(r, false);
}

// ---- Image / class lookup ----
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

// ---- Instance resolution (fresh every call — never caches stale pointers) ----
static Il2CppObject *FindUnityObject(Il2CppClass *klass) {
    if (!klass) return NULL;
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

static Il2CppObject *ResolveRoom(void) {
    Il2CppClass *roomClass = FindClass("Assembly-CSharp.dll", "ForgeTax.Room", "ForgeRoom");
    if (!roomClass) return NULL;
    return FindUnityObject(roomClass);
}

static Il2CppObject *ResolveTools(void) {
    Il2CppApi *api = Api();
    if (!api->loaded) return NULL;

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
    Il2CppClass *toolsClass = FindClass("Assembly-CSharp.dll", "ForgeTax.Touch", "ForgeDeveloperTools");
    if (toolsClass && api->objectNew) {
        Il2CppObject *room = ResolveRoom();
        if (room) {
            Il2CppMethod *ctor = api->classGetMethod(toolsClass, ".ctor", 1);
            if (ctor) {
                Il2CppObject *tools = api->objectNew(toolsClass);
                if (tools) {
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
    if (!ret) return FTC_CALL_OK;
    if (api->objectUnbox) {
        uint8_t *boxed = NULL;
        @try { boxed = (uint8_t *)api->objectUnbox(ret); } @catch (...) { return FTC_CALL_OK; }
        if (boxed && (*boxed == 0)) return FTC_CALL_ERR_RETURNED_FALSE;
    }
    return FTC_CALL_OK;
}

static void RefreshRoomDisplaysBestEffort(void) {
    Il2CppObject *room = ResolveRoom();
    if (!room) return;
    Il2CppClass *roomClass = FindClass("Assembly-CSharp.dll", "ForgeTax.Room", "ForgeRoom");
    if (!roomClass) return;
    InvokeBool(roomClass, room, "RefreshDisplays", 0, NULL);
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

// ---- #4: 3-Mode Forge Mode (100% IL2CPP — NO JIT needed!) ----
// mode = 0 (OFF / Normal), 1 (Hold 100% / Giữ nguyên), 2 (Success 100% / Thành công),
//        3 (Great 100% / Đại thành công).
// Uses DeveloperOverrides.set_ForgeMode + ForgeCampaign.altarForced (3=Hold, 4=Success,
// 5=Great in NewRelicRules.ApplyAltar -> updates BOTH outside display and strike roll!)
// + ForgeRoom.RefreshDisplays().
static bool WriteCampaignAltarForced(int32_t forcedValue, bool onlyIfChanged) {
    Il2CppApi *api = Api();
    if (!api->loaded || !api->fieldSetValue) return false;
    Il2CppObject *campaign = ResolveCampaign();
    if (!campaign) return false;
    Il2CppClass *campClass = (api->objectGetClass)
        ? api->objectGetClass(campaign)
        : FindClass("ForgeTax.Rules.dll", "ForgeTax.Rules", "ForgeCampaign");
    if (!campClass) campClass = FindClass("ForgeTax.Rules.dll", "ForgeTax.Rules", "ForgeCampaign");
    if (!campClass) return false;
    Il2CppField *field = api->classGetField(campClass, "altarForced");
    if (!field) return false;
    if (onlyIfChanged) {
        int32_t cur = 0;
        api->fieldGetValue(campaign, field, &cur);
        if (cur == forcedValue) return false;
    }
    api->fieldSetValue(campaign, field, &forcedValue);
    return true;
}

FTC_CallResult FTC_SetForgeWinMode(int mode) {
    Il2CppApi *api = Api();
    if (!api->loaded) return FTC_CALL_ERR_UNAVAILABLE;
    Il2CppClass *ovClass = FindClass("ForgeTax.Rules.dll", "ForgeTax.Rules", "DeveloperOverrides");
    if (!ovClass) return FTC_CALL_ERR_NO_METHOD;

    // DeveloperForgeMode: Normal=0, NoBreak=1, AlwaysSuccess=2.
    // Mode 1 (Hold) keeps Normal so AlwaysSuccess doesn't override Hold->Success.
    // Modes 2 (Success) and 3 (Great) set AlwaysSuccess as extra protection.
    int32_t forgeMode = (mode == 2 || mode == 3) ? 2 : 0;
    void *args[1] = { &forgeMode };
    FTC_CallResult cr = InvokeBool(ovClass, NULL, "set_ForgeMode", 1, args);
    if (cr != FTC_CALL_OK) return cr;

    int32_t altarVal = (mode >= 1 && mode <= 3) ? (int32_t)(mode + 2) : 0; // 1->3(Hold), 2->4(Succ), 3->5(Great)
    WriteCampaignAltarForced(altarVal, false);
    RefreshRoomDisplaysBestEffort();
    return FTC_CALL_OK;
}

void FTC_KeepForgeModeAlive(int mode) {
    @try {
        if (mode < 1 || mode > 3) return;
        int32_t target = (int32_t)(mode + 2);
        if (WriteCampaignAltarForced(target, true)) {
            RefreshRoomDisplaysBestEffort();
        }
    } @catch (...) {}
}

// #10: Auto-Refill Fever immediately when Fever finishes (0 writes while running or full).
void FTC_TickAutoFever(void) {
    @try {
        Il2CppApi *api = Api();
        if (!api->loaded) return;
        Il2CppObject *room = ResolveRoom();
        if (!room) return;
        Il2CppClass *roomClass = FindClass("Assembly-CSharp.dll", "ForgeTax.Room", "ForgeRoom");
        if (!roomClass) return;
        Il2CppObject *sword = ReadObjectField(room, roomClass, "onAnvil");
        if (!sword) return;
        Il2CppClass *swordClass = api->objectGetClass ? api->objectGetClass(sword) : NULL;
        if (!swordClass) swordClass = FindClass("Assembly-CSharp.dll", "ForgeTax.Swords", "ForgeSword");
        if (!swordClass) return;

        Il2CppField *brokenField = api->classGetField(swordClass, "broken");
        if (brokenField) {
            uint8_t broken = 0;
            api->fieldGetValue(sword, brokenField, &broken);
            if (broken != 0) return;
        }
        Il2CppObject *effects = ReadObjectField(sword, swordClass, "effects");
        if (!effects) return;
        Il2CppClass *effClass = api->objectGetClass ? api->objectGetClass(effects) : NULL;
        if (!effClass) effClass = FindClass("ForgeTax.Rules.dll", "ForgeTax.Rules", "ForgeSwordEffects");
        if (!effClass) return;

        Il2CppField *chargeField = api->classGetField(effClass, "charge");
        Il2CppField *untilField  = api->classGetField(effClass, "feverUntil");
        if (!chargeField || !untilField) return;

        int32_t charge = 0;
        float feverUntil = 0.0f;
        api->fieldGetValue(effects, chargeField, &charge);
        api->fieldGetValue(effects, untilField, &feverUntil);

        // If bar is already full (>= 10), do nothing (0 work!).
        if (charge >= 10) return;

        // Read UnityEngine.Time.get_time() to check if Fever is currently active.
        float now = 0.0f;
        Il2CppClass *timeClass = FindClass("UnityEngine.CoreModule.dll", "UnityEngine", "Time");
        if (timeClass && api->objectUnbox) {
            Il2CppMethod *getTime = api->classGetMethod(timeClass, "get_time", 0);
            if (getTime) {
                Il2CppObject *exc = NULL;
                Il2CppObject *ret = api->runtimeInvoke(getTime, NULL, NULL, &exc);
                if (!exc && ret) {
                    float *fp = (float *)api->objectUnbox(ret);
                    if (fp) now = *fp;
                }
            }
        }
        // While Fever is actively ticking, do NOT refill yet.
        if (feverUntil > 0.0f && feverUntil > now) return;

        // Fever just ended (or isn't active) and bar < 10 -> refill to max immediately!
        FTC_FillFever();
    } @catch (...) {}
}

// #44: Live ticket counts from TicketDeck.Deck(campaign) + KnifeRemoved(i)
FTC_CallResult FTC_GetTicketDeckCounts(int outCounts[5], int outCut[5]) {
    if (!outCounts) return FTC_CALL_ERR_UNAVAILABLE;
    Il2CppApi *api = Api();
    if (!api->loaded) return FTC_CALL_ERR_UNAVAILABLE;
    Il2CppObject *campaign = ResolveCampaign();
    if (!campaign) return FTC_CALL_ERR_NO_INSTANCE;

    Il2CppClass *deckClass = FindClass("ForgeTax.Rules.dll", "ForgeTax.Rules", "TicketDeck");
    if (!deckClass) return FTC_CALL_ERR_NO_METHOD;
    Il2CppMethod *deckMethod = api->classGetMethod(deckClass, "Deck", 1);
    if (!deckMethod) return FTC_CALL_ERR_NO_METHOD;

    void *args[1] = { campaign };
    Il2CppObject *exc = NULL;
    Il2CppObject *arr = NULL;
    @try { arr = api->runtimeInvoke(deckMethod, NULL, args, &exc); } @catch (...) { return FTC_CALL_ERR_EXCEPTION; }
    if (exc || !arr) return FTC_CALL_ERR_EXCEPTION;

    // Il2CppArray on arm64: max_length at +0x18 (size_t), double elements at +0x20.
    uint64_t len = *(const uint64_t *)((const uint8_t *)arr + 0x18);
    if (len < 5) return FTC_CALL_ERR_EXCEPTION;
    const double *elems = (const double *)((const uint8_t *)arr + 0x20);
    for (int i = 0; i < 5; i++) {
        double v = elems[i];
        outCounts[i] = (v > 0.0) ? (int)(v + 0.5) : 0;
    }

    if (outCut) {
        Il2CppClass *campClass = api->objectGetClass ? api->objectGetClass(campaign) : NULL;
        if (!campClass) campClass = FindClass("ForgeTax.Rules.dll", "ForgeTax.Rules", "ForgeCampaign");
        Il2CppMethod *knifeM = campClass ? api->classGetMethod(campClass, "KnifeRemoved", 1) : NULL;
        for (int i = 0; i < 5; i++) {
            outCut[i] = 0;
            if (knifeM && api->objectUnbox) {
                int32_t idx = i;
                void *kargs[1] = { &idx };
                Il2CppObject *kexc = NULL;
                Il2CppObject *kret = NULL;
                @try { kret = api->runtimeInvoke(knifeM, campaign, kargs, &kexc); } @catch (...) {}
                if (!kexc && kret) {
                    int32_t *ip = (int32_t *)api->objectUnbox(kret);
                    if (ip) outCut[i] = *ip;
                }
            }
        }
    }
    return FTC_CALL_OK;
}

FTC_CallResult FTC_CutTicket(int outcome) {
    if (outcome < 0 || outcome > 4) return FTC_CALL_ERR_RETURNED_FALSE;
    Il2CppApi *api = Api();
    if (!api->loaded) return FTC_CALL_ERR_UNAVAILABLE;
    Il2CppObject *campaign = ResolveCampaign();
    if (!campaign) return FTC_CALL_ERR_NO_INSTANCE;
    Il2CppClass *campClass = api->objectGetClass ? api->objectGetClass(campaign) : NULL;
    if (!campClass) campClass = FindClass("ForgeTax.Rules.dll", "ForgeTax.Rules", "ForgeCampaign");
    if (!campClass) return FTC_CALL_ERR_NO_METHOD;
    int32_t o = (int32_t)outcome;
    void *args[1] = { &o };
    FTC_CallResult cr = InvokeBool(campClass, campaign, "CutTicket", 1, args);
    if (cr == FTC_CALL_OK) {
        RefreshRoomDisplaysBestEffort();
    }
    return cr;
}

FTC_CallResult FTC_SetSwordValueMultiplierLive(double mult) {
    Il2CppApi *api = Api();
    if (!api->loaded || !api->fieldSetValue) return FTC_CALL_ERR_UNAVAILABLE;
    Il2CppObject *room = ResolveRoom();
    if (!room) return FTC_CALL_ERR_NO_INSTANCE;
    Il2CppClass *roomClass = FindClass("Assembly-CSharp.dll", "ForgeTax.Room", "ForgeRoom");
    if (!roomClass) return FTC_CALL_ERR_NO_METHOD;
    Il2CppObject *sword = ReadObjectField(room, roomClass, "onAnvil");
    if (!sword) return FTC_CALL_ERR_RETURNED_FALSE;
    Il2CppClass *swordClass = api->objectGetClass ? api->objectGetClass(sword) : NULL;
    if (!swordClass) swordClass = FindClass("Assembly-CSharp.dll", "ForgeTax.Swords", "ForgeSword");
    if (!swordClass) return FTC_CALL_ERR_NO_METHOD;
    Il2CppObject *effects = ReadObjectField(sword, swordClass, "effects");
    if (!effects) return FTC_CALL_ERR_RETURNED_FALSE;
    Il2CppClass *effClass = api->objectGetClass ? api->objectGetClass(effects) : NULL;
    if (!effClass) effClass = FindClass("ForgeTax.Rules.dll", "ForgeTax.Rules", "ForgeSwordEffects");
    if (!effClass) return FTC_CALL_ERR_NO_METHOD;
    Il2CppField *multField = api->classGetField(effClass, "multiplier");
    if (!multField) return FTC_CALL_ERR_NO_METHOD;
    api->fieldSetValue(effects, multField, &mult);
    RefreshRoomDisplaysBestEffort();
    return FTC_CALL_OK;
}

FTC_CallResult FTC_SetDragonGodMode(bool enabled) {
    Il2CppApi *api = Api();
    if (!api->loaded) return FTC_CALL_ERR_UNAVAILABLE;
    Il2CppClass *ovClass = FindClass("ForgeTax.Rules.dll", "ForgeTax.Rules", "DeveloperOverrides");
    if (!ovClass) return FTC_CALL_ERR_NO_METHOD;
    uint8_t val = enabled ? 1 : 0;
    void *args[1] = { &val };
    FTC_CallResult cr = InvokeBool(ovClass, NULL, "set_DragonGodMode", 1, args);
    if (cr != FTC_CALL_OK) return cr;
    Il2CppObject *room = ResolveRoom();
    if (room) {
        Il2CppClass *roomClass = FindClass("Assembly-CSharp.dll", "ForgeTax.Room", "ForgeRoom");
        if (roomClass) InvokeBool(roomClass, room, "ApplyDeveloperGodMode", 0, NULL);
    }
    return FTC_CALL_OK;
}

// ---- Public calls ----
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
    // Instant, zero-stall, 100% crash-free Unity performance tuning (no mid-frame
    // Metal buffer resize or synchronous VRAM mipmap reload).
    Il2CppApi *api = Api();
    if (!api->loaded) return FTC_CALL_ERR_UNAVAILABLE;

    bool anyOk = false;
    Il2CppClass *appClass = FindClass("UnityEngine.CoreModule.dll", "UnityEngine", "Application");
    if (appClass) {
        // 240 tells Unity to run at the display's maximum hardware refresh rate
        // (60 Hz on iPhone 7 Plus, 120 Hz on ProMotion iPhones/iPads, etc.).
        int32_t fps = enabled ? 240 : 60;
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
    Il2CppClass *qtClass = FindClass("Assembly-CSharp.dll", "ForgeTax.Quality", "ForgeQualityTier");
    if (!qtClass) return tools ? FTC_CALL_ERR_NO_METHOD : FTC_CALL_ERR_NO_INSTANCE;
    return InvokeBool(qtClass, NULL, "Force", 1, args);
}

FTC_CallResult FTC_AddRunTickets(int outcome, int count) {
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
