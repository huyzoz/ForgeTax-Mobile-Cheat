// GameBridge.h — call the game's own dev-tool / rules methods through IL2CPP.
// All calls are pure runtime_invoke / field access (no __TEXT patch, works on
// TrollStore without JIT and never crashes).
#ifndef FORGETAX_GAME_BRIDGE_H
#define FORGETAX_GAME_BRIDGE_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    FTC_CALL_OK = 0,
    FTC_CALL_ERR_UNAVAILABLE,
    FTC_CALL_ERR_NO_INSTANCE,
    FTC_CALL_ERR_NO_METHOD,
    FTC_CALL_ERR_EXCEPTION,
    FTC_CALL_ERR_RETURNED_FALSE,
} FTC_CallResult;

const char *FTC_CallResultMessage(FTC_CallResult r);
const char *FTC_CallResultMessageLang(FTC_CallResult r, bool english);

bool FTC_BridgeReady(void);
bool FTC_ToolsAvailable(void);

// #4: 0 = OFF (Normal), 1 = Success 100% (AlwaysSuccess), 2 = Great 100% (altarForced=5 + AlwaysSuccess)
FTC_CallResult FTC_SetForgeWinMode(int mode);
// Light keep-alive called only while #4 Great mode is ON (re-applies altarForced=5 if a new round cleared it).
void FTC_KeepGreatForgeAlive(void);

// Deterministic dragon god mode (works without JIT via DeveloperOverrides.set_DragonGodMode).
FTC_CallResult FTC_SetDragonGodMode(bool enabled);

// One-shot / dev-toggle calls.
FTC_CallResult FTC_AddGold(double amount);            // #2  (9.999e99)
FTC_CallResult FTC_GiveAllRelics(void);               // #3, #37
FTC_CallResult FTC_CycleForgeMode(void);              // legacy helper
FTC_CallResult FTC_SetAnvilGrade(int grade);          // #6
FTC_CallResult FTC_ToggleGodMode(void);               // #7
FTC_CallResult FTC_KillDragon(void);                  // #7 secondary
FTC_CallResult FTC_SummonMerchant(void);              // #8
FTC_CallResult FTC_JumpToDay(int day);                // #9
FTC_CallResult FTC_FillFever(void);                   // #10
FTC_CallResult FTC_AddSwordCredits(void);             // #25 (+10)
FTC_CallResult FTC_GiveSecretDoorKey(void);           // #23
FTC_CallResult FTC_EnterSkillArena(void);             // #24
FTC_CallResult FTC_OpenSwordPicker(void);             // #24 secondary
FTC_CallResult FTC_RevealCodex(void);                 // #26
FTC_CallResult FTC_ResetRun(void);                    // #27
FTC_CallResult FTC_SkipDay(void);                     // #28 (-1)
FTC_CallResult FTC_NextDay(void);                     // #28 (+1)
FTC_CallResult FTC_StartDragonFight(void);            // #29
FTC_CallResult FTC_ForceDragonLoss(void);             // #30
FTC_CallResult FTC_OpenArmory(void);                  // #31
FTC_CallResult FTC_SetQualityTier(int tier);          // #32: 0 Low, 1 Mid, 2 High
FTC_CallResult FTC_ToggleMerchantShelfSlot(void);     // #33 (credit-shelf)
FTC_CallResult FTC_ToggleFps(void);                   // #40
FTC_CallResult FTC_SetAntiLag(bool enabled);          // #41 (120 FPS + AA=0 + Quality Low)
FTC_CallResult FTC_SetTimeScale(float scale);         // #42 (Speed Hack 1x..3x)
FTC_CallResult FTC_AddRunTickets(int outcome, int count); // #12

#ifdef __cplusplus
}
#endif

#endif // FORGETAX_GAME_BRIDGE_H
