// GameBridge.h — call the game's own dev-tool methods (ForgeDeveloperTools)
// through the IL2CPP runtime. No game logic is re-implemented here; every
// one-shot / dev-toggle feature is one runtime_invoke of a method that
// already exists in the binary.
//
// Instance resolution (dump.cs, verified):
//   ForgePauseMenu : MonoBehaviour  --FindObjectOfType-->
//     .developerPage (ForgeDeveloperPage, field +0x20)
//       .tools (ForgeDeveloperTools, field +0x10)
//         .room (ForgeRoom, field +0x10)
//           .campaign (ForgeCampaign, field +0x2A8, for AddRunTickets)
// Fallback when the pause menu has not created the dev page yet:
//   FindObjectOfType(ForgeRoom) -> construct ForgeDeveloperTools(room)
//   with its .ctor and keep the instance. Both paths are best-effort and
//   reported, never faked: if no instance resolves, the feature shows
//   "chua goi duoc" in the menu.
//
// ---------------------------------------------------------------------------
// NHUNG THU BI CAM — tuyet doi khong goi, khong dua vao code (xem README §4):
//   - Cac method mo o tra phi / cap nhat IAP (o di vat tra phi, mua no-ads,
//     restore purchase) va bat cu method nao dung product id tra phi.
//   - Sua save / asset / text / balance truc tiep, xoa quang cao, chan SDK
//     quang cao, bat che do test cua nha phat trien (TestMode).
//   - Khong co chuoi product id tra phi nao trong repo nay.
// Chi cac method dev-tool trong README §2-§3 (AddGold, GiveAllRelics,
// CycleForgeMode, ToggleGodMode, KillDragon, SummonMerchant, JumpToDay,
// SetAnvilGrade, FillFever, ToggleFps, SetQualityTier, ...) duoc goi.
// ---------------------------------------------------------------------------
#ifndef FORGETAX_GAME_BRIDGE_H
#define FORGETAX_GAME_BRIDGE_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    FTC_CALL_OK = 0,              // method returned true (or void, no exception)
    FTC_CALL_ERR_UNAVAILABLE,     // IL2CPP symbols / classes not resolvable
    FTC_CALL_ERR_NO_INSTANCE,     // no ForgeDeveloperTools instance found yet
    FTC_CALL_ERR_NO_METHOD,       // method name/argc not found on the class
    FTC_CALL_ERR_EXCEPTION,       // the game method threw (Il2CppException)
    FTC_CALL_ERR_RETURNED_FALSE,  // method returned false (precondition failed)
} FTC_CallResult;

const char *FTC_CallResultMessage(FTC_CallResult r);

// True when the bridge resolved the IL2CPP runtime + classes at least once.
// (Does not mean an instance is available — see FTC_ToolsAvailable.)
bool FTC_BridgeReady(void);
// True when a ForgeDeveloperTools instance is currently resolvable.
bool FTC_ToolsAvailable(void);

// One-shot / dev-toggle calls. All return FTC_CALL_OK only when the game
// method ran without exception and (for bool methods) returned true.
FTC_CallResult FTC_AddGold(double amount);            // #2  (9.999e99)
FTC_CallResult FTC_GiveAllRelics(void);               // #3, #37
FTC_CallResult FTC_CycleForgeMode(void);              // #4 NoBreak (see note)
FTC_CallResult FTC_SetAnvilGrade(int grade);          // #6
FTC_CallResult FTC_ToggleGodMode(void);               // #7 (flip)
FTC_CallResult FTC_KillDragon(void);                  // #7 nut phu
FTC_CallResult FTC_SummonMerchant(void);              // #8
FTC_CallResult FTC_JumpToDay(int day);                // #9
FTC_CallResult FTC_FillFever(void);                   // #10 (on enable)
FTC_CallResult FTC_AddSwordCredits(void);             // #25 (+10)
FTC_CallResult FTC_GiveSecretDoorKey(void);           // #23
FTC_CallResult FTC_EnterSkillArena(void);             // #24
FTC_CallResult FTC_OpenSwordPicker(void);             // #24 nut phu
FTC_CallResult FTC_RevealCodex(void);                 // #26
FTC_CallResult FTC_ResetRun(void);                    // #27
FTC_CallResult FTC_SkipDay(void);                     // #28 (-1)
FTC_CallResult FTC_NextDay(void);                     // #28 (+1)
FTC_CallResult FTC_StartDragonFight(void);            // #29
FTC_CallResult FTC_ForceDragonLoss(void);             // #30
FTC_CallResult FTC_OpenArmory(void);                  // #31
FTC_CallResult FTC_SetQualityTier(int tier);          // #32: 0 Thap, 1 Vua, 2 Cao
FTC_CallResult FTC_ToggleMerchantShelfSlot(void);     // #33 (flip, credit-shelf)
FTC_CallResult FTC_ToggleFps(void);                   // #40 (flip)
// #41: Anti-lag boost (Unity QualitySettings.antiAliasing=0 + targetFrameRate=120).
FTC_CallResult FTC_SetAntiLag(bool enabled);
// #42: Speed Hack via UnityEngine.Time.set_timeScale(float).
FTC_CallResult FTC_SetTimeScale(float scale);
// #12: outcome = ForgeOutcome: 1 Damage, 2 Hold, 3 Success, 4 GreatSuccess.
FTC_CallResult FTC_AddRunTickets(int outcome, int count);

#ifdef __cplusplus
}
#endif

#endif // FORGETAX_GAME_BRIDGE_H
