// PatchEngine.h — runtime byte patching for UnityFramework.
//
// Method: check JIT/codesigning safety via csops first (prevents SIGKILL on
// jailed TrollStore without JIT), find UnityFramework's in-memory base via
// dyld, verify original bytes FIRST, apply atomically via 16KB page-aligned
// vm_remap, and restore originals on disable. The binary on disk is never touched.
#ifndef FORGETAX_PATCH_ENGINE_H
#define FORGETAX_PATCH_ENGINE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    FTC_PATCH_OK = 0,
    FTC_PATCH_ERR_NO_IMAGE,      // UnityFramework not found in dyld images
    FTC_PATCH_ERR_NOT_APPLYABLE, // entry disabled / unknown status
    FTC_PATCH_ERR_MISMATCH,      // bytes in memory != expected original
    FTC_PATCH_ERR_ALREADY,       // already patched (apply) / already clean (remove)
    FTC_PATCH_ERR_PROTECT,       // vm_protect / vm_remap failed
    FTC_PATCH_ERR_NO_JIT,        // jailed iOS without CS_DEBUGGED (would SIGKILL)
} FTC_PatchResult;

// Human-readable message for a result (Vietnamese with accents, or English).
const char *FTC_PatchResultMessage(FTC_PatchResult r);
const char *FTC_PatchResultMessageLang(FTC_PatchResult r, bool english);

// True when modifying __TEXT pages will not be killed by AMFI/codesigning.
bool FTC_PatchCanModifyCode(void);

// Apply / remove ALL patch sites belonging to one feature id.
FTC_PatchResult FTC_PatchApplyFeature(int featureId);
FTC_PatchResult FTC_PatchRemoveFeature(int featureId);

// True if every site of the feature currently holds patched bytes.
bool FTC_PatchFeatureIsApplied(int featureId);

// Address of RVA inside the loaded UnityFramework, or 0 when not loaded yet.
uintptr_t FTC_UnityAddressForRVA(uint64_t rva);

#ifdef __cplusplus
}
#endif

#endif // FORGETAX_PATCH_ENGINE_H
