// PatchEngine.mm — see header. No patch bytes here; all bytes come from
// patch_table.h (the single table, generated from JSON).
#import "PatchEngine.h"
#import "patch_table.h"

#include <mach/mach.h>
#include <mach/vm_map.h>
#include <mach-o/dyld.h>
#include <pthread.h>
#include <string.h>
#include <unistd.h>
#include <libkern/OSCacheControl.h>

extern "C" int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);

#define FTC_CS_OPS_STATUS   0
#define FTC_CS_KILL         0x00000200U
#define FTC_CS_ENFORCEMENT  0x00001000U
#define FTC_CS_DEBUGGED     0x10000000U

static uintptr_t s_unityBase = 0;
static pthread_mutex_t s_patchMutex = PTHREAD_MUTEX_INITIALIZER;

const char *FTC_PatchResultMessageLang(FTC_PatchResult r, bool english) {
    if (english) {
        switch (r) {
            case FTC_PATCH_OK: return "OK";
            case FTC_PATCH_ERR_NO_IMAGE: return "UnityFramework not loaded in memory";
            case FTC_PATCH_ERR_NOT_APPLYABLE: return "Patch disabled (unverified entry)";
            case FTC_PATCH_ERR_MISMATCH: return "Original bytes mismatch — refused (wrong game version)";
            case FTC_PATCH_ERR_ALREADY: return "Already in desired state";
            case FTC_PATCH_ERR_PROTECT: return "Memory protection failed (needs JIT)";
            case FTC_PATCH_ERR_NO_JIT: return "Open game via 'Open with JIT' in TrollStore";
            default: return "Unknown error";
        }
    }
    switch (r) {
        case FTC_PATCH_OK: return "OK";
        case FTC_PATCH_ERR_NO_IMAGE: return "Không tìm thấy UnityFramework trong bộ nhớ";
        case FTC_PATCH_ERR_NOT_APPLYABLE: return "Patch này bị vô hiệu hóa";
        case FTC_PATCH_ERR_MISMATCH: return "Bytes gốc không khớp — từ chối ghi (sai bản 3.16.1)";
        case FTC_PATCH_ERR_ALREADY: return "Trạng thái đã đúng rồi";
        case FTC_PATCH_ERR_PROTECT: return "Không đổi được quyền bộ nhớ (cần JIT)";
        case FTC_PATCH_ERR_NO_JIT: return "Cần mở game bằng 'Open with JIT' trong TrollStore";
        default: return "Lỗi không rõ";
    }
}

const char *FTC_PatchResultMessage(FTC_PatchResult r) {
    return FTC_PatchResultMessageLang(r, false);
}

bool FTC_PatchCanModifyCode(void) {
    uint32_t flags = 0;
    if (csops(getpid(), FTC_CS_OPS_STATUS, &flags, sizeof(flags)) != 0) {
        return true;
    }
    if ((flags & FTC_CS_DEBUGGED) != 0) {
        return true;
    }
    // On jailed iOS 15.8.8 TrollStore without JIT, CS_KILL / CS_ENFORCEMENT
    // are active without CS_DEBUGGED; modifying __TEXT causes instant SIGKILL.
    if ((flags & (FTC_CS_KILL | FTC_CS_ENFORCEMENT)) != 0) {
        return false;
    }
    return true;
}

static uintptr_t FTC_FindUnityBase(void) {
    if (s_unityBase != 0) return s_unityBase;
    uint32_t count = _dyld_image_count();
    uintptr_t fallback = 0;
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        if (strstr(name, "UnityFramework.framework/UnityFramework") != NULL) {
            s_unityBase = (uintptr_t)_dyld_get_image_header(i);
            return s_unityBase;
        }
        if (fallback == 0 && strstr(name, "UnityFramework") != NULL) {
            fallback = (uintptr_t)_dyld_get_image_header(i);
        }
    }
    if (fallback != 0) {
        s_unityBase = fallback;
    }
    return s_unityBase;
}

uintptr_t FTC_UnityAddressForRVA(uint64_t rva) {
    uintptr_t base = FTC_FindUnityBase();
    if (base == 0) return 0;
    return base + (uintptr_t)rva;
}

static bool FTC_StatusApplyable(const char *status) {
    return status && (strcmp(status, "MATCH") == 0 ||
                      strcmp(status, "DERIVED") == 0 ||
                      strcmp(status, "CHECKED") == 0);
}

static FTC_PatchResult FTC_WriteVerified(uint8_t *addr, const uint8_t *expected,
                                         const uint8_t *bytes, size_t len) {
    if (!addr || !expected || !bytes || len == 0) return FTC_PATCH_ERR_NOT_APPLYABLE;
    if (memcmp(addr, bytes, len) == 0) return FTC_PATCH_ERR_ALREADY;
    if (memcmp(addr, expected, len) != 0) return FTC_PATCH_ERR_MISMATCH;
    if (!FTC_PatchCanModifyCode()) return FTC_PATCH_ERR_NO_JIT;

    vm_size_t pageSize = vm_page_size;
    if (pageSize == 0) pageSize = 16384;
    vm_address_t addrVal = (vm_address_t)addr;
    vm_address_t pageStart = addrVal & ~(pageSize - 1);
    vm_address_t pageEnd = (addrVal + len + pageSize - 1) & ~(pageSize - 1);
    vm_size_t pageLen = pageEnd - pageStart;
    size_t offsetInPage = (size_t)(addrVal - pageStart);

    // Strategy 1: atomic vm_remap via private scratch copy.
    vm_address_t scratch = 0;
    vm_prot_t curProt = VM_PROT_NONE;
    vm_prot_t maxProt = VM_PROT_NONE;
    kern_return_t kr = vm_remap(mach_task_self(), &scratch, pageLen, 0,
                                VM_FLAGS_ANYWHERE,
                                mach_task_self(), pageStart, TRUE,
                                &curProt, &maxProt, VM_INHERIT_NONE);
    if (kr == KERN_SUCCESS && scratch != 0) {
        kr = vm_protect(mach_task_self(), scratch, pageLen, FALSE,
                        VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
        if (kr != KERN_SUCCESS) {
            vm_deallocate(mach_task_self(), scratch, pageLen);
            return FTC_PATCH_ERR_PROTECT;
        }
        memcpy((uint8_t *)scratch + offsetInPage, bytes, len);
        sys_dcache_flush((void *)scratch, pageLen);
        sys_icache_invalidate((void *)scratch, pageLen);

        kr = vm_protect(mach_task_self(), scratch, pageLen, FALSE,
                        VM_PROT_READ | VM_PROT_EXECUTE);
        if (kr != KERN_SUCCESS) {
            vm_deallocate(mach_task_self(), scratch, pageLen);
            return FTC_PATCH_ERR_PROTECT;
        }
        vm_address_t target = pageStart;
        vm_prot_t targetCur = VM_PROT_NONE;
        vm_prot_t targetMax = VM_PROT_NONE;
        kr = vm_remap(mach_task_self(), &target, pageLen, 0,
                      VM_FLAGS_OVERWRITE | VM_FLAGS_FIXED,
                      mach_task_self(), scratch, FALSE,
                      &targetCur, &targetMax, VM_INHERIT_COPY);
        vm_deallocate(mach_task_self(), scratch, pageLen);
        if (kr != KERN_SUCCESS) return FTC_PATCH_ERR_PROTECT;
        sys_icache_invalidate(addr, len);
        return FTC_PATCH_OK;
    }

    // Strategy 2: direct page-aligned vm_protect fallback.
    kr = vm_protect(mach_task_self(), pageStart, pageLen, FALSE,
                    VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) return FTC_PATCH_ERR_PROTECT;
    memcpy(addr, bytes, len);
    sys_dcache_flush(addr, len);
    sys_icache_invalidate(addr, len);
    kr = vm_protect(mach_task_self(), pageStart, pageLen, FALSE,
                    VM_PROT_READ | VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS) return FTC_PATCH_ERR_PROTECT;
    sys_icache_invalidate(addr, len);
    return FTC_PATCH_OK;
}

static FTC_PatchResult FTC_ApplyOrRemoveFeature(int featureId, bool apply) {
    pthread_mutex_lock(&s_patchMutex);
    FTC_PatchResult firstError = FTC_PATCH_OK;
    bool anySite = false;
    bool anyChanged = false;
    for (size_t i = 0; i < kFTC_PatchTableCount; i++) {
        const FTC_PatchEntry *e = &kFTC_PatchTable[i];
        if (e->feature_id != featureId) continue;
        anySite = true;
        if (!FTC_StatusApplyable(e->status)) {
            if (firstError == FTC_PATCH_OK) firstError = FTC_PATCH_ERR_NOT_APPLYABLE;
            continue;
        }
        uintptr_t addr = FTC_UnityAddressForRVA(e->rva);
        if (addr == 0) {
            if (firstError == FTC_PATCH_OK) firstError = FTC_PATCH_ERR_NO_IMAGE;
            continue;
        }
        FTC_PatchResult r;
        if (apply) {
            r = FTC_WriteVerified((uint8_t *)addr, e->original, e->patched, e->len);
        } else {
            r = FTC_WriteVerified((uint8_t *)addr, e->patched, e->original, e->len);
        }
        if (r == FTC_PATCH_OK) {
            anyChanged = true;
        } else if (r == FTC_PATCH_ERR_ALREADY) {
            continue;
        } else if (firstError == FTC_PATCH_OK) {
            firstError = r;
        }
    }
    pthread_mutex_unlock(&s_patchMutex);
    if (!anySite) return FTC_PATCH_ERR_NOT_APPLYABLE;
    if (anyChanged) return FTC_PATCH_OK;
    return firstError;
}

FTC_PatchResult FTC_PatchApplyFeature(int featureId) {
    @try {
        return FTC_ApplyOrRemoveFeature(featureId, true);
    } @catch (...) {
        return FTC_PATCH_ERR_PROTECT;
    }
}

FTC_PatchResult FTC_PatchRemoveFeature(int featureId) {
    @try {
        return FTC_ApplyOrRemoveFeature(featureId, false);
    } @catch (...) {
        return FTC_PATCH_ERR_PROTECT;
    }
}

bool FTC_PatchFeatureIsApplied(int featureId) {
    bool anySite = false;
    for (size_t i = 0; i < kFTC_PatchTableCount; i++) {
        const FTC_PatchEntry *e = &kFTC_PatchTable[i];
        if (e->feature_id != featureId) continue;
        anySite = true;
        uintptr_t addr = FTC_UnityAddressForRVA(e->rva);
        if (addr == 0) return false;
        if (memcmp((const void *)addr, e->patched, e->len) != 0) return false;
    }
    return anySite;
}
