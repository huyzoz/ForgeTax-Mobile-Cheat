// FeatureCatalog.h — metadata for all 39 features (#2..#40, README is the
// authority). The menu is built from this table; the mockup only supplied
// layout / colours / Vietnamese wording. No patch bytes here — those live
// only in patch_table.h.
//
// Kinds (shown differently in the menu, see CheatMenuView):
//   PATCH      — runtime byte patch; ON writes patched bytes, OFF restores
//                original bytes. State persists while the toggle is on.
//   ONESHOT    — one IL2CPP dev-tool call per tap; no kept state.
//   DEV_TOGGLE — a dev-tool boolean that flips each call (ToggleGodMode,
//                ToggleMerchantShelfSlot, ToggleFps). The menu tracks its
//                own on/off state (all OFF at launch) and calls once per
//                flip; the game flag is assumed OFF at launch.
//   MODE       — segmented choice; each option maps to a patch or a call.
//   STEP       — stepper value + an "Ap dung" button that performs the call.
#ifndef FORGETAX_FEATURE_CATALOG_H
#define FORGETAX_FEATURE_CATALOG_H

typedef enum {
    FTC_KIND_PATCH = 0,
    FTC_KIND_ONESHOT,
    FTC_KIND_DEV_TOGGLE,
    FTC_KIND_MODE,
    FTC_KIND_STEP,
} FTC_FeatureKind;

typedef struct {
    int fid;                 // README number (#2..#40)
    const char *category;    // mockup category id
    const char *name;        // Vietnamese, as in mockup / README
    const char *desc;        // Vietnamese description (tap name to reveal)
    FTC_FeatureKind kind;
    const char *impl;        // short implementation note for the reader
} FTC_Feature;

static const char *kFTC_CatForge  = "forge";
static const char *kFTC_CatRes    = "res";
static const char *kFTC_CatRelic  = "relic";
static const char *kFTC_CatShop   = "shop";
static const char *kFTC_CatDragon = "dragon";
static const char *kFTC_CatDay    = "day";
static const char *kFTC_CatAds    = "ads";
static const char *kFTC_CatSetting = "setting";

static const FTC_Feature kFTC_Features[] = {
    // ---- Ren (forge) ----
    { 4, "forge", "Ren luon thanh cong (giu Great)",
      "Moi lan dap deu thanh cong; Great van la Great.",
      FTC_KIND_PATCH,
      "Patch Guard tai 0x2751574 (csel w0,w8,w9,eq -> mov w0,w8), luon tra "
      "ket qua AlwaysSuccess (3, hoac 4 neu input la Great). Patch cu "
      "(MOV w0,#3; RET tai entry 0x2751550) DA BI LOAI vi ha Great(4) xuong "
      "Success(3). TAC DUNG PHU: khi patch nay BAT, CycleForgeMode (nut phu "
      "'Doi mode') khong con tac dung len Guard nua — luon AlwaysSuccess. "
      "Tat patch de CycleForgeMode co tac dung tro lai." },
    { 5, "forge", "Ti le gay ve 0",
      "Gay = 0 ca luc ren thuong lan tren grade 900.",
      FTC_KIND_PATCH,
      "2 patch site: FailureChance (FMOV d0,xzr;RET, DERIVED) + TopGradeBreak." },
    { 6, "forge", "Grade kiem tren de",
      "Chinh grade kiem dang ren, toi da 999.",
      FTC_KIND_STEP,
      "Stepper 0..999 (buoc 10) + nut Ap dung -> SetAnvilGrade(grade)." },
    { 10, "forge", "Fever day ngay / khong het",
      "Nap day thanh Fever, Fever khong het gio.",
      FTC_KIND_PATCH,
      "Bat: goi FillFever 1 lan + patch FeverRules.Expire = RET. "
      "Tat: go patch (Fever da nap van con, khong rut lai duoc)." },
    { 39, "forge", "Nhan gia tri kiem x10",
      "Kiem ban duoc gap 10 lan. Great x2.5 van cong them.",
      FTC_KIND_PATCH, "1 patch site: SwordValuation.Value." },
    // ---- Tai nguyen (res) ----
    { 2, "res", "Vang vo han",
      "Cong vang toi 9.999E+99 — so lon nhat game con hien thi duoc.",
      FTC_KIND_ONESHOT, "AddGold(9.999e99) moi lan bam." },
    { 16, "res", "Quota ve 1 vang",
      "Moi hop dong chi can tra 1 vang.",
      FTC_KIND_PATCH, "1 patch site: ContractQuota (FMOV d0,#1.0;RET)." },
    { 17, "res", "99 mang",
      "99 luot song, khoi lo no cong pham.",
      FTC_KIND_PATCH, "1 patch site: get_MaxLives (MOV w0,#99;RET;NOP)." },
    { 25, "res", "+10 Sword Credits",
      "Cong 10 diem dung de doi kiem.",
      FTC_KIND_ONESHOT, "AddSwordCredits() moi lan bam (+10)." },
    // ---- Di vat (relic) ----
    { 3, "relic", "Full di vat (119)",
      "Mo het 119 di vat, dung 9 o mien phi.",
      FTC_KIND_ONESHOT, "GiveAllRelics() moi lan bam." },
    { 33, "relic", "Mo o di vat bang vang",
      "Mo them o qua credit-shelf mua bang vang trong game.",
      FTC_KIND_DEV_TOGGLE,
      "ToggleMerchantShelfSlot() moi lan gat (KHONG phai o tra phi — xem ghi chu cam o GameBridge.h)." },
    { 34, "relic", "No ken ngay",
      "Ken (cocoon) no o dau vong sau, khoi cho 2 ngay.",
      FTC_KIND_PATCH, "1 patch site: HatchCocoon." },
    { 35, "relic", "Ep fusion ngay",
      "Ghep holy + dawnsheath thanh fusion luon, khoi cho.",
      FTC_KIND_PATCH, "1 patch site: TryFuse (cbz -> b)." },
    { 36, "relic", "Vat pham dung vo han",
      "Ward / rewind / chalk / powder / starshard xai hoai khong het.",
      FTC_KIND_PATCH, "1 patch site: UseConsumable (bl AddUses -> nop)." },
    { 37, "relic", "Mo 3 cup rong",
      "Mo cup Claw / Tail / Head qua GiveAllRelics.",
      FTC_KIND_ONESHOT,
      "Khong co patch/call rieng: goi GiveAllRelics() (giong #3). "
      "Game tu nhan la da co cup khi du 3 di vat cup." },
    { 38, "relic", "Hell Drop moi lan thang rong",
      "Ruong thang rong nao cung co kiem thunderbamboo.",
      FTC_KIND_PATCH, "1 patch site: get_HellDropDue (MOV w0,#1;RET)." },
    // ---- Thuong nhan (shop) ----
    { 8, "shop", "Goi thuong nhan bat cu luc nao",
      "Goi ma thuong nhan ngay, khoi cho 3 ngay.",
      FTC_KIND_ONESHOT, "SummonMerchant() moi lan bam." },
    { 12, "shop", "Ve merchant +1",
      "Cong ve doi ti le (damage / hold / success / great).",
      FTC_KIND_STEP,
      "Chon loai ve (Damage/Hold/Success/Great) + nut +1 ve -> "
      "AddRunTickets(outcome, 1) tren ForgeCampaign (can instance campaign; "
      "xem GameBridge). Nut - khong lam gi (ve da cong khong rut lai)." },
    { 13, "shop", "Mua hang merchant mien phi",
      "Mua do cua ma thuong nhan khong bi tru vang.",
      FTC_KIND_PATCH, "1 patch site: PurchaseMerchant." },
    { 14, "shop", "Shop di vat mien phi",
      "Mua di vat trong shop gia 0.",
      FTC_KIND_PATCH,
      "1 patch site: OfferPrice, CHI dung 0x275D430. Dia chi cu 0x275D428 la "
      "SAI (dau ham, ldr w8,[x0,#0x200]) — entry MISMATCH do_not_apply, khong "
      "co trong patch_table.h." },
    { 15, "shop", "Reroll mien phi",
      "Doi hang shop khong ton tien.",
      FTC_KIND_PATCH, "1 patch site: ChargeReroll (RET)." },
    // ---- Rong (dragon) ----
    { 7, "dragon", "God mode rong + Giet rong",
      "Rong khong giet duoc minh; giet rong ngay lap tuc.",
      FTC_KIND_DEV_TOGGLE,
      "Gat = ToggleGodMode() 1 lan; nut phu 'Giet ngay' = KillDragon() 1 lan." },
    { 18, "dragon", "Mot phat chet rong",
      "Mot don la HP rong ve 0.",
      FTC_KIND_PATCH, "1 patch site: DamageDragon (fsub -> fmov d1,xzr)." },
    { 19, "dragon", "Bat tu trong tran rong",
      "Trong tran rong minh khong chet.",
      FTC_KIND_PATCH, "1 patch site: get_PlayerInvulnerable." },
    { 20, "dragon", "Rong choang vinh vien",
      "Rong luon trong trang thai choang.",
      FTC_KIND_PATCH, "1 patch site: get_Stunned." },
    { 21, "dragon", "Rong khong noi gian",
      "Rong khong vao trang thai noi gian du HP thap.",
      FTC_KIND_PATCH, "1 patch site: get_Enraged." },
    { 22, "dragon", "Rong khong bay",
      "Rong khong bay len, o yen duoi dat.",
      FTC_KIND_PATCH, "1 patch site: get_FlightChance." },
    { 29, "dragon", "Danh rong bat cu luc nao",
      "Goi tran rong ngay, khoi cho den ngay rong.",
      FTC_KIND_ONESHOT, "StartDragonFight() moi lan bam." },
    { 30, "dragon", "Ep thua rong",
      "Chu dong thua tran rong khi can test.",
      FTC_KIND_ONESHOT, "ForceDragonLoss() moi lan bam." },
    // ---- Ngay & Choi (day) ----
    { 9, "day", "Nhay toi ngay",
      "Nhay toi ngay bat ky (quyet toan cong pham roi moi nhay).",
      FTC_KIND_STEP,
      "Stepper 1..24 + nut Nhay -> JumpToDay(ngay). Pill 'Ngay' tren header cap nhat theo." },
    { 23, "day", "Cua bi mat: +30 kiem vao tay",
      "Mo cua bi mat, nhan 30 kiem vao tay ngay.",
      FTC_KIND_ONESHOT, "GiveSecretDoorKey() moi lan bam." },
    { 24, "day", "Dau truong ky nang",
      "Chon kiem bat ky + grade, test ren rieng khong anh huong run chinh.",
      FTC_KIND_ONESHOT,
      "Nut 'Mo' = EnterSkillArena(); nut phu 'Chon kiem' = OpenSwordPicker()." },
    { 26, "day", "Mo Codex",
      "Mo toan bo Codex (di vat, kiem, lich su).",
      FTC_KIND_ONESHOT, "RevealCodex() moi lan bam." },
    { 27, "day", "Choi lai tu dau",
      "Reset run hien tai. Canh bao: mat run dang choi.",
      FTC_KIND_ONESHOT,
      "ResetRun() — menu hoi xac nhan truoc khi goi (mat run hien tai)." },
    { 28, "day", "Nhay ngay nhanh +-1",
      "Nhay lui / tien 1 ngay.",
      FTC_KIND_MODE,
      "Moi nut la 1 lan goi: '-1 ngay' = SkipDay(), '+1 ngay' = NextDay()." },
    { 31, "day", "Mo kho vu khi",
      "Mo Armory xem toan bo kiem da mo khoa.",
      FTC_KIND_ONESHOT, "OpenArmory() moi lan bam." },
    // ---- Quang cao (ads) ----
    { 11, "ads", "Skip quang cao nhan thuong",
      "Nut quang cao nhan thuong van con nguyen. Bam la nhan luon, khong xem video.",
      FTC_KIND_PATCH,
      "1 patch site 20 byte: ShowRewarded stub goi thang finished(true). "
      "Chi ap dung offer thuong; quang cao thuong khong dung." },
    // ---- Setting ----
    { 32, "setting", "Chat luong do hoa",
      "Doi muc do hoa Thap / Vua / Cao.",
      FTC_KIND_MODE,
      "SetQualityTier(Nullable<QualityTier>): Thap=0, Vua=1, Cao=2. "
      "Layout Nullable la struct {int32 value; bool has_value} — chua kiem chung live." },
    { 40, "setting", "Hien FPS",
      "Hien khung FPS co dinh o goc trai day man hinh (khong di chuyen theo logo).",
      FTC_KIND_DEV_TOGGLE,
      "CADisplayLink sieu nhe cua menu, co dinh goc trai day, chi cap nhat khi so FPS doi." },
    { 41, "setting", "Boost Max FPS (120 FPS + Xoa lag)",
      "Mo khoa 120 FPS (toi da theo tan so man hinh), tat AA/vSync, ha mipmap + scale 80% + Quality Low de chay muot nhat.",
      FTC_KIND_DEV_TOGGLE,
      "Goi static UnityEngine (targetFrameRate=120, vSync=0, antiAliasing=0, mipmapLimit=1, ResizeBuffers=0.8) + ForgeQualityTier.Force(Low)." },
    { 42, "setting", "Toc do game (Speed Hack)",
      "Tang toc do ren, dap bua va hoat anh len 1x / 1.5x / 2x / 3x (chay thang khong can JIT).",
      FTC_KIND_MODE,
      "Goi static UnityEngine.Time.set_timeScale(1.0 / 1.5 / 2.0 / 3.0)." },
};
static const size_t kFTC_FeatureCount = sizeof(kFTC_Features) / sizeof(kFTC_Features[0]);

static const FTC_Feature *FTC_FeatureById(int fid) {
    for (size_t i = 0; i < kFTC_FeatureCount; i++) {
        if (kFTC_Features[i].fid == fid) return &kFTC_Features[i];
    }
    return NULL;
}

#endif // FORGETAX_FEATURE_CATALOG_H
