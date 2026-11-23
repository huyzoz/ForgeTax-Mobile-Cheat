// PatchEngine.mm — see header. No patch bytes here; all bytes come from
// patch_table.h (the single table, generated from JSON).
#import "PatchEngine.h"
#import "patch_table.h"

#include <mach/mach.h>
#include <mach/vm_map.h>
#include <mach-o/dyld.h>
#include <pthread.h>
#include <string.h>
#include <libkern/OSCacheControl.h>

static uintptr_t s_unityBase = 0;
static pthread_mutex_t s_patchMutex = PTHREAD_MUTEX_INITIALIZER;

const char *FTC_PatchResultMessage(FTC_PatchResult r) {
    switch (r) {
        case FTC_PATCH_OK: return "OK";
        case FTC_PATCH_ERR_NO_IMAGE: return "Khong tim thay UnityFramework trong bo nho";
        case FTC_PATCH_ERR_NOT_APPLYABLE: return "Patch nay bi vo hieu hoa (cho bang verified)";
        case FTC_PATCH_ERR_MISMATCH: return "Bytes goc khong khop — TU CHOI ghi (game co the khac ban 3.16.1)";
        case FTC_PATCH_ERR_ALREADY: return "Trang thai da dung roi";
        case FTC_PATCH_ERR_PROTECT: return "Khong doi duoc quyen bo nho (thu mo game bang Open with JIT trong TrollStore)";
        default: return "Loi khong ro";
    }
}

// Find UnityFramework's loaded mach header address. __TEXT vmaddr is 0 in
// this binary, so RVA == file offset == (address - image base).
// Never caches 0 so lazy dlopen of UnityFramework is picked up once loaded.
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
    // Allowlist is deliberately closed: only MATCH / DERIVED / CHECKED may
    // ever be applied. "PROVISIONAL" (and any unknown status, including
    // MISMATCH) is refused — a provisional entry must be verified first
    // and re-issued with a verified status before it can be applied.
    return status && (strcmp(status, "MATCH") == 0 ||
                      strcmp(status, "DERIVED") == 0 ||
                      strcmp(status, "CHECKED") == 0);
}

// Write `bytes` (len) at `addr` after verifying `expected` is currently
// there. Returns FTC_PATCH_OK or an error; never writes on mismatch.
//
// Primary strategy: atomic page-aligned vm_remap (copy -> RW -> memcpy ->
// cache flush -> RX -> overwrite swap). This ensures:
//   1. The live UnityFramework __TEXT page NEVER temporarily loses X
//      while Unity threads may be executing code on the same 16 KB page.
//   2. If the kernel refuses RX on a modified page (e.g. non-JIT iOS 15),
//      failure happens on the private scratch page and the live page stays
//      100% untouched and executable.
static FTC_PatchResult FTC_WriteVerified(uint8_t *addr, const uint8_t *expected,
                                         const uint8_t *bytes, size_t len) {
    if (!addr || !expected || !bytes || len == 0) return FTC_PATCH_ERR_NOT_APPLYABLE;
    if (memcmp(addr, bytes, len) == 0) return FTC_PATCH_ERR_ALREADY; // desired state
    if (memcmp(addr, expected, len) != 0) return FTC_PATCH_ERR_MISMATCH;

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
            // Do NOT touch live page if kernel refused RX on modified page.
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

    // Strategy 2: direct page-aligned vm_protect fallback (only if vm_remap
    // itself is unavailable).
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
            // Already in the desired state — not an error for this site.
            continue;
        } else if (firstError == FTC_PATCH_OK) {
            firstError = r;
        }
    }
    pthread_mutex_unlock(&s_patchMutex);
    if (!anySite) return FTC_PATCH_ERR_NOT_APPLYABLE;
    if (anyChanged) return FTC_PATCH_OK;
    return firstError; // OK when everything was already in the desired state
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
