// CheatMenuView.mm — 16:9 Landscape Zero-Lag Cheat UI + Cutout Demon Logo.
//
// Design & Performance Guarantees:
//   - Transparent cutout demon mask logo (LogoImageData.h): NO backdrop circle,
//     NO extra dimming layer behind the panel, NO offscreen shadow blur.
//   - Panel ALWAYS leaves a clear gap around the logo so it never overlaps it.
//   - Two explicit header controls: "-" (minimize back to logo) and expand
//     (toggle compact 16:9 window <-> full-screen rounded card).
//   - Pure manual CGRect frame layout (ZERO UIStackView / Auto Layout solver
//     inside the scroll area) + 100% solid opaque surfaces (ZERO alpha overdraw,
//     ZERO shadowRadius blur) -> locked 60/120 FPS scrolling & instant taps.
//   - In-place state updates on every tap (NO view tear-down / rebuild).
//   - Fixed bottom-left FPS counter (detached from logo, change-only redraws).
//   - Persistent NSUserDefaults config with staggered, non-blocking restore
//     so enabling many cheats never causes startup lag or stutter.
#import "CheatMenuView.h"
#import "FeatureCatalog.h"
#import "PatchEngine.h"
#import "GameBridge.h"
#import "LogoImageData.h"

#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <string.h>

// ---- Crimson / Obsidian / Gold Palette (100% opaque solids for 0 GPU blend overhead) ----
#define FTC_C_PANEL      0x120D0E
#define FTC_C_HEADER     0x1A1113
#define FTC_C_SIDEBAR    0x160F11
#define FTC_C_TAB_ON     0x2C1519
#define FTC_C_CARD       0x1C1416
#define FTC_C_CARD_ON    0x2D1519
#define FTC_C_BTN_BG     0x2A1B1E
#define FTC_C_BORDER     0x352024
#define FTC_C_BORDER_HI  0x59252C
#define FTC_C_CRIMSON    0xE52432
#define FTC_C_CRIMSON_HI 0xFF3B49
#define FTC_C_GOLD       0xF7D774
#define FTC_C_GOLD2      0xE8B949
#define FTC_C_TEXT       0xF5ECEE
#define FTC_C_TEXT2      0xB8A3A7
#define FTC_C_OK         0x6BE684
#define FTC_C_ERR        0xFF8A65
#define FTC_C_ONACC      0x140A0B
#define FTC_C_FPS_BG     0x120C0D
#define FTC_C_FPS_TXT    0x7DFF8A

static UIColor *FTC_Color(uint32_t hex) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0 alpha:1.0];
}

static const CGFloat kLogoSize    = 54.0;
static const CGFloat kLogoGap     = 10.0;
static const CGFloat kMargin      = 8.0;
static const CGFloat kHeaderH     = 38.0;
static const CGFloat kSidebarW    = 104.0;
static const CGFloat kCompactMaxW = 540.0;
static const CGFloat kCompactMaxH = 324.0;

// NSUserDefaults persistence keys
static NSString * const kPrefSwitches  = @"FTC_v2_switches";
static NSString * const kPrefQuality   = @"FTC_v2_quality";
static NSString * const kPrefSpeed     = @"FTC_v2_speed";
static NSString * const kPrefLogoX     = @"FTC_v2_logoX";
static NSString * const kPrefLogoY     = @"FTC_v2_logoY";
static NSString * const kPrefMaximized = @"FTC_v2_maximized";
static NSString * const kPrefTab       = @"FTC_v2_tab";

typedef struct { const char *cid; const char *name; } FTCTab;
static const FTCTab kTabs[] = {
    {"forge",   "Ren"},
    {"res",     "Tai nguyen"},
    {"relic",   "Di vat"},
    {"shop",    "Thuong nhan"},
    {"dragon",  "Rong"},
    {"day",     "Ngay & Choi"},
    {"ads",     "Quang cao"},
    {"setting", "Cai dat"},
};
static const NSInteger kTabCount = (NSInteger)(sizeof(kTabs) / sizeof(kTabs[0]));

static const float kSpeedValues[] = { 1.0f, 1.5f, 2.0f, 3.0f };

@interface CheatMenuView ()
// Floating logo (transparent demon mask cutout) + fixed bottom-left FPS badge
@property (nonatomic, strong) UIButton *logoButton;
@property (nonatomic, strong) UILabel *fpsBadge;

// Main 16:9 panel + chrome
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIView *headerBar;
@property (nonatomic, strong) UIView *headerAccent;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *activeCountBadge;
@property (nonatomic, strong) UIButton *minimizeButton;
@property (nonatomic, strong) UIButton *expandButton;
@property (nonatomic, strong) UIView *sidebar;
@property (nonatomic, strong) UIView *sidebarDivider;
@property (nonatomic, strong) NSMutableArray<UIButton *> *tabButtons;
@property (nonatomic, strong) NSMutableArray<UIView *> *tabIndicators;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIButton *resetAllButton;

// Active tab's in-place card view references (for 0-lag state updates)
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UIView *> *cardMap;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UILabel *> *subLabelMap;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UISwitch *> *switchMap;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UILabel *> *stepValMap;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UISegmentedControl *> *segMap;

// Window / layout state
@property (nonatomic, assign) BOOL menuOpen;
@property (nonatomic, assign) BOOL maximized;
@property (nonatomic, assign) NSInteger selectedTab;
@property (nonatomic, assign) BOOL logoPositioned;
@property (nonatomic, assign) CGPoint dragStart;
@property (nonatomic, assign) CGPoint dragOrigin;
@property (nonatomic, assign) BOOL dragMoved;
@property (nonatomic, assign) CGSize lastLayoutSize;
@property (nonatomic, assign) CGFloat lastScrollWidth;

// FPS display link (only active while #40 is ON)
@property (nonatomic, strong) CADisplayLink *fpsLink;
@property (nonatomic, assign) NSInteger fpsFrames;
@property (nonatomic, assign) CFTimeInterval fpsLastUpdate;
@property (nonatomic, assign) NSInteger lastDisplayedFps;

// Feature state
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *switchOn;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *stepValue;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *modeIndex;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *statusText;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *statusKind; // 0=neutral, 1=ok, 2=err
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *descOpen;

// Staggered startup restore state (runs once, never blocks)
@property (nonatomic, assign) BOOL restoreScheduled;
@property (nonatomic, assign) NSInteger pendingDevRestoreTries;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *pendingDevToggleFids;
@end

@implementation CheatMenuView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = YES;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    _switchOn = [NSMutableDictionary dictionary];
    _stepValue = [NSMutableDictionary dictionary];
    _modeIndex = [NSMutableDictionary dictionary];
    _statusText = [NSMutableDictionary dictionary];
    _statusKind = [NSMutableDictionary dictionary];
    _descOpen = [NSMutableDictionary dictionary];
    _cardMap = [NSMutableDictionary dictionary];
    _subLabelMap = [NSMutableDictionary dictionary];
    _switchMap = [NSMutableDictionary dictionary];
    _stepValMap = [NSMutableDictionary dictionary];
    _segMap = [NSMutableDictionary dictionary];
    _tabButtons = [NSMutableArray array];
    _tabIndicators = [NSMutableArray array];
    _pendingDevToggleFids = [NSMutableArray array];

    _menuOpen = NO;
    _maximized = NO;
    _selectedTab = 0;
    _logoPositioned = NO;
    _lastDisplayedFps = -1;
    _restoreScheduled = NO;

    for (size_t i = 0; i < kFTC_FeatureCount; i++) {
        const FTC_Feature *f = &kFTC_Features[i];
        if (f->kind == FTC_KIND_STEP) {
            _stepValue[@(f->fid)] = (f->fid == 9) ? @(1) : @(0);
        }
        if (f->kind == FTC_KIND_MODE) {
            _modeIndex[@(f->fid)] = @(0);
        }
    }

    [self loadSavedPreferences];
    [self buildLogo];
    [self buildPanel];
    return self;
}

// Pass-through: ONLY the floating demon logo and (when open) the panel accept touches.
// No invisible backdrop layer is ever added behind the UI.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (CGRectContainsPoint(self.logoButton.frame, point)) {
        return [super hitTest:point withEvent:event];
    }
    if (_menuOpen && CGRectContainsPoint(self.panel.frame, point)) {
        return [super hitTest:point withEvent:event];
    }
    return nil;
}

#pragma mark - Safe area helper

- (UIEdgeInsets)ftcSafeInsets {
    UIEdgeInsets s = self.safeAreaInsets;
    return UIEdgeInsetsMake(MAX(kMargin, s.top + 6.0),
                            MAX(kMargin, s.left + 6.0),
                            MAX(kMargin, s.bottom + 6.0),
                            MAX(kMargin, s.right + 6.0));
}

#pragma mark - Cutout Demon Logo + Fixed Bottom-Left FPS Badge

- (void)buildLogo {
    UIButton *logo = [UIButton buttonWithType:UIButtonTypeCustom];
    logo.frame = CGRectMake(0, 0, kLogoSize, kLogoSize);
    // Pure transparent cutout — NO circular backdrop, NO added layer behind logo,
    // NO offscreen shadowRadius blur.
    logo.backgroundColor = [UIColor clearColor];
    logo.opaque = NO;
    logo.clipsToBounds = NO;
    logo.adjustsImageWhenHighlighted = NO;
    logo.accessibilityLabel = @"Mo / dong menu cheat";

    NSData *pngData = [NSData dataWithBytesNoCopy:(void *)kFTC_LogoPngData
                                           length:kFTC_LogoPngSize
                                     freeWhenDone:NO];
    UIImage *img = [UIImage imageWithData:pngData scale:3.0];
    if (img) {
        [logo setImage:img forState:UIControlStateNormal];
        logo.imageView.contentMode = UIViewContentModeScaleAspectFit;
    }

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(onLogoTap:)];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(onLogoPan:)];
    [tap requireGestureRecognizerToFail:pan];
    [logo addGestureRecognizer:pan];
    [logo addGestureRecognizer:tap];
    [self addSubview:logo];
    self.logoButton = logo;

    // Fixed bottom-left FPS counter (detached from logo, solid opaque, 0 shadow).
    UILabel *fps = [[UILabel alloc] initWithFrame:CGRectZero];
    fps.text = @"-- FPS";
    fps.font = [UIFont monospacedDigitSystemFontOfSize:11.5 weight:UIFontWeightBold];
    fps.textColor = FTC_Color(FTC_C_FPS_TXT);
    fps.backgroundColor = FTC_Color(FTC_C_FPS_BG);
    fps.opaque = YES;
    fps.userInteractionEnabled = NO;
    fps.layer.borderColor = FTC_Color(FTC_C_BORDER_HI).CGColor;
    fps.layer.borderWidth = 1.0;
    fps.layer.cornerRadius = 6.0;
    fps.layer.masksToBounds = YES;
    fps.textAlignment = NSTextAlignmentCenter;
    fps.hidden = YES;
    [self addSubview:fps];
    self.fpsBadge = fps;
}

- (void)onLogoTap:(UITapGestureRecognizer *)tap {
    @try {
        if (tap.state == UIGestureRecognizerStateEnded) {
            [self setMenuOpen:!_menuOpen];
        }
    } @catch (...) {}
}

- (void)onLogoPan:(UIPanGestureRecognizer *)pan {
    @try {
        CGPoint loc = [pan locationInView:self];
        if (pan.state == UIGestureRecognizerStateBegan) {
            self.dragStart = loc;
            self.dragOrigin = self.logoButton.frame.origin;
            self.dragMoved = NO;
        } else if (pan.state == UIGestureRecognizerStateChanged) {
            CGFloat dx = loc.x - self.dragStart.x;
            CGFloat dy = loc.y - self.dragStart.y;
            if (fabs(dx) + fabs(dy) > 5.0) self.dragMoved = YES;
            if (self.dragMoved) {
                UIEdgeInsets safe = [self ftcSafeInsets];
                CGFloat maxX = MAX(safe.left, self.bounds.size.width - kLogoSize - safe.right);
                CGFloat maxY = MAX(safe.top, self.bounds.size.height - kLogoSize - safe.bottom);
                CGPoint origin = CGPointMake(self.dragOrigin.x + dx, self.dragOrigin.y + dy);
                origin.x = MAX(safe.left, MIN(origin.x, maxX));
                origin.y = MAX(safe.top, MIN(origin.y, maxY));
                self.logoButton.frame = CGRectMake(origin.x, origin.y, kLogoSize, kLogoSize);
                // Keep panel clear of logo while dragging if panel is open.
                if (_menuOpen) [self layoutPanel];
            }
        } else if (pan.state == UIGestureRecognizerStateEnded ||
                   pan.state == UIGestureRecognizerStateCancelled) {
            if (_menuOpen) [self layoutPanel];
            [self saveLogoPosition];
        }
    } @catch (...) {}
}

#pragma mark - 16:9 Landscape Panel Chrome

- (void)buildPanel {
    // 100% opaque panel with crisp border and ZERO shadowRadius offscreen blur.
    UIView *panel = [[UIView alloc] initWithFrame:CGRectZero];
    panel.backgroundColor = FTC_Color(FTC_C_PANEL);
    panel.opaque = YES;
    panel.layer.cornerRadius = 16.0;
    panel.layer.borderColor = FTC_Color(FTC_C_BORDER_HI).CGColor;
    panel.layer.borderWidth = 1.5;
    panel.layer.masksToBounds = YES;
    panel.hidden = YES;
    [self addSubview:panel];
    self.panel = panel;

    // Header bar
    UIView *header = [[UIView alloc] initWithFrame:CGRectZero];
    header.backgroundColor = FTC_Color(FTC_C_HEADER);
    header.opaque = YES;
    [panel addSubview:header];
    self.headerBar = header;

    UIView *accent = [[UIView alloc] initWithFrame:CGRectZero];
    accent.backgroundColor = FTC_Color(FTC_C_CRIMSON);
    accent.opaque = YES;
    [header addSubview:accent];
    self.headerAccent = accent;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.text = @"FORGE TAXX";
    title.font = [UIFont boldSystemFontOfSize:15];
    title.textColor = FTC_Color(FTC_C_GOLD);
    title.backgroundColor = FTC_Color(FTC_C_HEADER);
    title.opaque = YES;
    [header addSubview:title];
    self.titleLabel = title;

    UILabel *badge = [[UILabel alloc] initWithFrame:CGRectZero];
    badge.text = @"0 BAT";
    badge.font = [UIFont boldSystemFontOfSize:10.5];
    badge.textColor = FTC_Color(FTC_C_CRIMSON_HI);
    badge.backgroundColor = FTC_Color(FTC_C_TAB_ON);
    badge.opaque = YES;
    badge.textAlignment = NSTextAlignmentCenter;
    badge.layer.cornerRadius = 8.0;
    badge.layer.masksToBounds = YES;
    [header addSubview:badge];
    self.activeCountBadge = badge;

    // Minimize button ("-") -> collapses cleanly back to the floating logo
    UIButton *minBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [minBtn setTitle:@"−" forState:UIControlStateNormal];
    minBtn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [minBtn setTitleColor:FTC_Color(FTC_C_TEXT) forState:UIControlStateNormal];
    minBtn.backgroundColor = FTC_Color(FTC_C_BTN_BG);
    minBtn.opaque = YES;
    minBtn.layer.cornerRadius = 7.0;
    minBtn.layer.borderColor = FTC_Color(FTC_C_BORDER_HI).CGColor;
    minBtn.layer.borderWidth = 1.0;
    minBtn.accessibilityLabel = @"Thu gon menu";
    [minBtn addTarget:self action:@selector(onMinimizeTap) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:minBtn];
    self.minimizeButton = minBtn;

    // Expand / Restore button -> toggles compact 16:9 <-> rounded full-screen
    UIButton *expBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [expBtn setTitle:@"⤢" forState:UIControlStateNormal];
    expBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [expBtn setTitleColor:FTC_Color(FTC_C_GOLD) forState:UIControlStateNormal];
    expBtn.backgroundColor = FTC_Color(FTC_C_BTN_BG);
    expBtn.opaque = YES;
    expBtn.layer.cornerRadius = 7.0;
    expBtn.layer.borderColor = FTC_Color(FTC_C_BORDER_HI).CGColor;
    expBtn.layer.borderWidth = 1.0;
    expBtn.accessibilityLabel = @"Phong to / thu vua";
    [expBtn addTarget:self action:@selector(onExpandTap) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:expBtn];
    self.expandButton = expBtn;

    // Left Tab Sidebar (8 compact tabs -> zero sidebar scrolling on 16:9)
    UIView *sidebar = [[UIView alloc] initWithFrame:CGRectZero];
    sidebar.backgroundColor = FTC_Color(FTC_C_SIDEBAR);
    sidebar.opaque = YES;
    [panel addSubview:sidebar];
    self.sidebar = sidebar;

    UIView *divider = [[UIView alloc] initWithFrame:CGRectZero];
    divider.backgroundColor = FTC_Color(FTC_C_BORDER);
    divider.opaque = YES;
    [panel addSubview:divider];
    self.sidebarDivider = divider;

    for (NSInteger i = 0; i < kTabCount; i++) {
        UIButton *tb = [UIButton buttonWithType:UIButtonTypeCustom];
        tb.tag = i;
        tb.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        tb.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        tb.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        tb.opaque = YES;
        tb.layer.cornerRadius = 8.0;
        tb.layer.masksToBounds = YES;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        tb.contentEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 6);
#pragma clang diagnostic pop
        [tb addTarget:self action:@selector(onSelectTab:) forControlEvents:UIControlEventTouchUpInside];

        UIView *ind = [[UIView alloc] initWithFrame:CGRectMake(0, 5, 3, 20)];
        ind.backgroundColor = FTC_Color(FTC_C_CRIMSON_HI);
        ind.opaque = YES;
        ind.hidden = YES;
        [tb addSubview:ind];

        [sidebar addSubview:tb];
        [self.tabButtons addObject:tb];
        [self.tabIndicators addObject:ind];
    }

    // Right ScrollView (pure manual-frame opaque cards, 0 Auto Layout overhead)
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scroll.backgroundColor = FTC_Color(FTC_C_PANEL);
    scroll.opaque = YES;
    scroll.showsVerticalScrollIndicator = YES;
    scroll.alwaysBounceVertical = NO;
    scroll.delaysContentTouches = NO;
    [panel addSubview:scroll];
    self.scrollView = scroll;

    [self updateTabAppearance];
    [self updateExpandButtonGlyph];
}

#pragma mark - Attach & Layout (Logo-Clear 16:9 + Full-Screen Rounded)

- (void)attachToWindow:(UIWindow *)window {
    @try {
        if (!window) return;
        self.frame = window.bounds;
        if (self.superview != window) {
            [window addSubview:self];
        }
        if (window.subviews.lastObject != self) {
            [window bringSubviewToFront:self];
        }
        [self ensureLogoPositioned];
        [self layoutFpsBadge];
        if (_menuOpen) {
            [self layoutPanel];
        }
        [self scheduleStaggeredRestoreIfNeeded];
    } @catch (...) {}
}

- (void)ensureLogoPositioned {
    CGFloat bw = self.bounds.size.width;
    CGFloat bh = self.bounds.size.height;
    if (bw < 100 || bh < 100) return;
    UIEdgeInsets safe = [self ftcSafeInsets];
    CGFloat maxX = MAX(safe.left, bw - kLogoSize - safe.right);
    CGFloat maxY = MAX(safe.top, bh - kLogoSize - safe.bottom);
    if (!self.logoPositioned) {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        CGFloat x, y;
        if ([ud objectForKey:kPrefLogoX] && [ud objectForKey:kPrefLogoY]) {
            x = (CGFloat)[ud doubleForKey:kPrefLogoX];
            y = (CGFloat)[ud doubleForKey:kPrefLogoY];
        } else {
            x = maxX - 4.0;
            y = safe.top + 8.0;
        }
        x = MAX(safe.left, MIN(x, maxX));
        y = MAX(safe.top, MIN(y, maxY));
        self.logoButton.frame = CGRectMake(x, y, kLogoSize, kLogoSize);
        self.logoPositioned = YES;
    } else {
        CGRect f = self.logoButton.frame;
        f.origin.x = MAX(safe.left, MIN(f.origin.x, maxX));
        f.origin.y = MAX(safe.top, MIN(f.origin.y, maxY));
        self.logoButton.frame = f;
    }
}

- (void)layoutFpsBadge {
    @try {
        CGFloat bw = self.bounds.size.width;
        CGFloat bh = self.bounds.size.height;
        if (bw < 100 || bh < 100) return;
        UIEdgeInsets safe = [self ftcSafeInsets];
        CGFloat badgeW = 64.0;
        CGFloat badgeH = 24.0;
        self.fpsBadge.frame = CGRectMake(safe.left,
                                         bh - safe.bottom - badgeH,
                                         badgeW, badgeH);
    } @catch (...) {}
}

- (void)layoutSubviews {
    [super layoutSubviews];
    @try {
        if (self.superview && self.superview.subviews.lastObject != self) {
            [self.superview bringSubviewToFront:self];
        }
        if (self.bounds.size.width < 100 || self.bounds.size.height < 100) return;
        [self ensureLogoPositioned];
        if (!CGSizeEqualToSize(self.bounds.size, self.lastLayoutSize)) {
            self.lastLayoutSize = self.bounds.size;
            [self layoutFpsBadge];
            if (_menuOpen) {
                [self layoutPanel];
            }
        }
    } @catch (...) {}
}

// Compute panel frame strictly leaving a clear gap (`kLogoGap`) around the
// floating demon mask logo so the panel NEVER covers the logo in either
// Compact 16:9 or Maximized full-screen rounded mode.
- (void)layoutPanel {
    @try {
        CGFloat bw = self.bounds.size.width;
        CGFloat bh = self.bounds.size.height;
        if (bw < 100 || bh < 100) return;

        UIEdgeInsets safe = [self ftcSafeInsets];
        CGFloat safeLeft = safe.left;
        CGFloat safeRight = bw - safe.right;
        CGFloat safeTop = safe.top;
        CGFloat safeBottom = bh - safe.bottom;
        CGFloat availH = MAX(200.0, safeBottom - safeTop);

        CGRect logo = self.logoButton.frame;
        CGFloat spaceLeft  = (logo.origin.x - kLogoGap) - safeLeft;
        CGFloat spaceRight = safeRight - (logo.origin.x + kLogoSize + kLogoGap);
        CGFloat spaceAbove = (logo.origin.y - kLogoGap) - safeTop;
        CGFloat spaceBelow = safeBottom - (logo.origin.y + kLogoSize + kLogoGap);

        CGFloat x, y, pw, ph;
        // Prefer horizontal side with more space (natural for 16:9 landscape).
        if (MAX(spaceLeft, spaceRight) >= 280.0) {
            BOOL putLeft = (spaceLeft >= spaceRight);
            CGFloat maxSideW = putLeft ? spaceLeft : spaceRight;
            if (self.maximized) {
                pw = maxSideW;
                ph = availH;
                y = safeTop;
            } else {
                pw = MIN(kCompactMaxW, maxSideW);
                ph = MIN(kCompactMaxH, availH);
                // Align vertically near the logo, clamped cleanly in safe bounds.
                y = MAX(safeTop, MIN(logo.origin.y, safeBottom - ph));
            }
            x = putLeft ? (logo.origin.x - kLogoGap - pw)
                        : (logo.origin.x + kLogoSize + kLogoGap);
        } else {
            // Fallback when logo sits horizontally centered: place above or below logo.
            BOOL putBelow = (spaceBelow >= spaceAbove);
            CGFloat maxVertH = MAX(180.0, putBelow ? spaceBelow : spaceAbove);
            CGFloat availW = MAX(260.0, safeRight - safeLeft);
            pw = self.maximized ? availW : MIN(kCompactMaxW, availW);
            ph = self.maximized ? maxVertH : MIN(kCompactMaxH, maxVertH);
            x = safeLeft + (availW - pw) * 0.5;
            y = putBelow ? (logo.origin.y + kLogoSize + kLogoGap)
                         : (logo.origin.y - kLogoGap - ph);
        }

        x = MAX(safeLeft, MIN(x, safeRight - pw));
        y = MAX(safeTop, MIN(y, safeBottom - ph));
        self.panel.frame = CGRectMake(floor(x), floor(y), floor(pw), floor(ph));
        self.panel.layer.cornerRadius = self.maximized ? 18.0 : 14.0;

        // Chrome layout inside panel (pure CGRect math, 0 Auto Layout)
        CGFloat W = self.panel.bounds.size.width;
        CGFloat H = self.panel.bounds.size.height;

        self.headerBar.frame = CGRectMake(0, 0, W, kHeaderH);
        self.headerAccent.frame = CGRectMake(0, kHeaderH - 1.5, W, 1.5);
        self.titleLabel.frame = CGRectMake(12, 0, 118, kHeaderH - 2);
        self.activeCountBadge.frame = CGRectMake(130, (kHeaderH - 20) * 0.5, 58, 20);

        CGFloat btnW = 30.0, btnH = 26.0, btnY = (kHeaderH - btnH) * 0.5;
        self.minimizeButton.frame = CGRectMake(W - 10 - btnW, btnY, btnW, btnH);
        self.expandButton.frame = CGRectMake(W - 10 - btnW - 6 - btnW, btnY, btnW, btnH);

        CGFloat bodyY = kHeaderH;
        CGFloat bodyH = MAX(80.0, H - bodyY);
        CGFloat sideW = (W < 380.0) ? 88.0 : kSidebarW;
        self.sidebar.frame = CGRectMake(0, bodyY, sideW, bodyH);
        self.sidebarDivider.frame = CGRectMake(sideW, bodyY, 1.0, bodyH);

        // Layout the 8 sidebar tabs evenly to fit bodyH with ZERO scrolling
        CGFloat padY = 6.0;
        CGFloat gapY = 3.0;
        CGFloat tabH = floor((bodyH - padY * 2.0 - gapY * (kTabCount - 1)) / (CGFloat)kTabCount);
        tabH = MAX(22.0, MIN(36.0, tabH));
        for (NSInteger i = 0; i < kTabCount; i++) {
            UIButton *tb = self.tabButtons[i];
            tb.frame = CGRectMake(5.0, padY + i * (tabH + gapY), sideW - 10.0, tabH);
            UIView *ind = self.tabIndicators[i];
            ind.frame = CGRectMake(0, 4.0, 3.0, MAX(12.0, tabH - 8.0));
        }

        CGFloat contentX = sideW + 1.0;
        CGFloat contentW = MAX(140.0, W - contentX);
        self.scrollView.frame = CGRectMake(contentX, bodyY, contentW, bodyH);

        // Only rebuild/re-layout active tab's cards when scroll width changed or empty.
        if (fabs(contentW - self.lastScrollWidth) > 1.0 || self.scrollView.subviews.count == 0) {
            self.lastScrollWidth = contentW;
            [self buildActiveTabCards];
        }
    } @catch (...) {}
}

- (void)setMenuOpen:(BOOL)open {
    @try {
        _menuOpen = open;
        self.panel.hidden = !open;
        if (open) {
            [self layoutPanel];
            [self updateActiveCountBadge];
            [self updateTabAppearance];
        }
    } @catch (...) {}
}

- (void)onMinimizeTap {
    [self setMenuOpen:NO];
}

- (void)onExpandTap {
    self.maximized = !self.maximized;
    [self updateExpandButtonGlyph];
    [[NSUserDefaults standardUserDefaults] setBool:self.maximized forKey:kPrefMaximized];
    [self layoutPanel];
}

- (void)updateExpandButtonGlyph {
    [self.expandButton setTitle:(self.maximized ? @"⤡" : @"⤢") forState:UIControlStateNormal];
}

#pragma mark - Tabs & Pure Manual-Frame Cards (Zero Auto Layout, Zero Scroll Lag)

- (void)onSelectTab:(UIButton *)sender {
    NSInteger idx = sender.tag;
    if (idx < 0 || idx >= kTabCount) return;
    if (idx == self.selectedTab && self.scrollView.subviews.count > 0) return;
    self.selectedTab = idx;
    [[NSUserDefaults standardUserDefaults] setInteger:idx forKey:kPrefTab];
    [self updateTabAppearance];
    self.scrollView.contentOffset = CGPointZero;
    [self buildActiveTabCards];
}

- (void)updateTabAppearance {
    for (NSInteger i = 0; i < kTabCount; i++) {
        UIButton *tb = self.tabButtons[i];
        UIView *ind = self.tabIndicators[i];
        BOOL active = (i == self.selectedTab);
        NSInteger onCount = [self activeFeatureCountInTab:i];
        NSString *baseName = [NSString stringWithUTF8String:kTabs[i].name];
        NSString *label = (onCount > 0)
            ? [NSString stringWithFormat:@"%@ (%ld)", baseName, (long)onCount]
            : baseName;
        [tb setTitle:label forState:UIControlStateNormal];
        tb.backgroundColor = active ? FTC_Color(FTC_C_TAB_ON) : FTC_Color(FTC_C_SIDEBAR);
        [tb setTitleColor:active ? FTC_Color(FTC_C_GOLD)
                                 : (onCount > 0 ? FTC_Color(FTC_C_CRIMSON_HI) : FTC_Color(FTC_C_TEXT2))
                 forState:UIControlStateNormal];
        ind.hidden = !active;
    }
}

- (NSInteger)activeFeatureCountInTab:(NSInteger)tabIdx {
    const char *cid = kTabs[tabIdx].cid;
    NSInteger count = 0;
    for (size_t i = 0; i < kFTC_FeatureCount; i++) {
        const FTC_Feature *f = &kFTC_Features[i];
        if (strcmp(f->category, cid) != 0) continue;
        if ((f->kind == FTC_KIND_PATCH || f->kind == FTC_KIND_DEV_TOGGLE) &&
            [self.switchOn[@(f->fid)] boolValue]) {
            count++;
        } else if (f->fid == 42 && [self.modeIndex[@(42)] integerValue] > 0) {
            count++;
        }
    }
    return count;
}

- (void)updateActiveCountBadge {
    NSInteger total = 0;
    for (NSInteger i = 0; i < kTabCount; i++) total += [self activeFeatureCountInTab:i];
    self.activeCountBadge.text = [NSString stringWithFormat:@"%ld BAT", (long)total];
}

// Build ONLY the 1..8 cards for the currently selected tab using pure manual CGRects.
// In 2-column grid mode (when contentW >= 420pt), nearly every tab fits on 1 screen
// without scrolling!
- (void)buildActiveTabCards {
    @try {
        for (UIView *sub in [self.scrollView.subviews copy]) {
            [sub removeFromSuperview];
        }
        [self.cardMap removeAllObjects];
        [self.subLabelMap removeAllObjects];
        [self.switchMap removeAllObjects];
        [self.stepValMap removeAllObjects];
        [self.segMap removeAllObjects];
        self.resetAllButton = nil;

        CGFloat W = self.scrollView.bounds.size.width;
        if (W < 120.0) return;

        const char *cid = kTabs[self.selectedTab].cid;
        CGFloat pad = 8.0;
        CGFloat gap = 7.0;
        BOOL twoCol = (W >= 415.0);
        CGFloat colW = twoCol ? floor((W - pad * 2.0 - gap) * 0.5) : (W - pad * 2.0);

        CGFloat colY[2] = { pad, pad };

        for (size_t i = 0; i < kFTC_FeatureCount; i++) {
            const FTC_Feature *f = &kFTC_Features[i];
            if (strcmp(f->category, cid) != 0) continue;

            // Wide controls (STEP / MODE / combined secondary buttons) span full width
            // when in 2-col mode if single column would be cramped.
            BOOL forceFull = (twoCol && colW < 235.0 &&
                              (f->kind == FTC_KIND_STEP || f->kind == FTC_KIND_MODE ||
                               f->fid == 4 || f->fid == 7 || f->fid == 24));
            CGFloat cardW = forceFull ? (W - pad * 2.0) : colW;
            CGFloat cardH = (f->fid == 12) ? 74.0 : 58.0;

            CGFloat cx, cy;
            if (!twoCol || forceFull) {
                cy = MAX(colY[0], colY[1]);
                cx = pad;
                colY[0] = cy + cardH + gap;
                colY[1] = colY[0];
            } else {
                NSInteger col = (colY[0] <= colY[1]) ? 0 : 1;
                cx = pad + col * (colW + gap);
                cy = colY[col];
                colY[col] = cy + cardH + gap;
            }

            UIView *card = [self makeCardForFeature:f frame:CGRectMake(cx, cy, cardW, cardH)];
            [self.scrollView addSubview:card];
        }

        CGFloat totalH = MAX(colY[0], colY[1]);

        // In "Cai dat" tab, add a convenient "Tat het cheat & xoa cau hinh luu" button.
        if (strcmp(cid, "setting") == 0) {
            UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeCustom];
            resetBtn.frame = CGRectMake(pad, totalH + 2.0, W - pad * 2.0, 34.0);
            [resetBtn setTitle:@"Tat het cheat & Xoa cau hinh da luu" forState:UIControlStateNormal];
            resetBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
            [resetBtn setTitleColor:FTC_Color(FTC_C_CRIMSON_HI) forState:UIControlStateNormal];
            resetBtn.backgroundColor = FTC_Color(FTC_C_TAB_ON);
            resetBtn.opaque = YES;
            resetBtn.layer.cornerRadius = 10.0;
            resetBtn.layer.borderColor = FTC_Color(FTC_C_CRIMSON).CGColor;
            resetBtn.layer.borderWidth = 1.0;
            [resetBtn addTarget:self action:@selector(onResetAllCheats) forControlEvents:UIControlEventTouchUpInside];
            [self.scrollView addSubview:resetBtn];
            self.resetAllButton = resetBtn;
            totalH += 44.0;
        }

        self.scrollView.contentSize = CGSizeMake(W, MAX(totalH + 4.0, self.scrollView.bounds.size.height));
    } @catch (...) {}
}

- (UIView *)makeCardForFeature:(const FTC_Feature *)f frame:(CGRect)frame {
    CGFloat W = frame.size.width;
    CGFloat H = frame.size.height;
    BOOL on = [self.switchOn[@(f->fid)] boolValue];

    UIView *card = [[UIView alloc] initWithFrame:frame];
    card.opaque = YES;
    card.backgroundColor = on ? FTC_Color(FTC_C_CARD_ON) : FTC_Color(FTC_C_CARD);
    card.layer.borderColor = on ? FTC_Color(FTC_C_CRIMSON).CGColor : FTC_Color(FTC_C_BORDER).CGColor;
    card.layer.borderWidth = 1.0;
    card.layer.cornerRadius = 11.0;
    self.cardMap[@(f->fid)] = card;

    // Right control area width
    BOOL hasSecondary = (f->fid == 4 || f->fid == 7 || f->fid == 24);
    CGFloat ctrlAreaW = 66.0;
    if (f->kind == FTC_KIND_STEP) ctrlAreaW = 178.0;
    else if (f->kind == FTC_KIND_MODE) ctrlAreaW = (f->fid == 42) ? 168.0 : 148.0;
    else if (hasSecondary) ctrlAreaW = 136.0;

    CGFloat textW = MAX(60.0, W - ctrlAreaW - 18.0);

    // Feature title button (tap title to toggle short Vietnamese description in subtitle)
    UIButton *titleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    titleBtn.frame = CGRectMake(10, 6, textW, 22);
    [titleBtn setTitle:[NSString stringWithUTF8String:f->name] forState:UIControlStateNormal];
    titleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12.5];
    titleBtn.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [titleBtn setTitleColor:FTC_Color(FTC_C_TEXT) forState:UIControlStateNormal];
    titleBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    titleBtn.tag = f->fid;
    [titleBtn addTarget:self action:@selector(onToggleDesc:) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:titleBtn];

    // Subtitle / live status line (updated in-place without rebuilding any view)
    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(10, 28, textW, H - 32)];
    sub.font = [UIFont systemFontOfSize:10.5];
    sub.numberOfLines = 2;
    sub.lineBreakMode = NSLineBreakByTruncatingTail;
    [card addSubview:sub];
    self.subLabelMap[@(f->fid)] = sub;
    [self refreshCardSubtitle:f];

    // Control on the right side (manual frames, 0 Auto Layout)
    switch (f->kind) {
        case FTC_KIND_PATCH:
        case FTC_KIND_DEV_TOGGLE: {
            UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
            CGSize sz = sw.intrinsicContentSize;
            sw.frame = CGRectMake(W - sz.width - 8.0, floor((H - sz.height) * 0.5), sz.width, sz.height);
            sw.on = on;
            sw.onTintColor = FTC_Color(FTC_C_CRIMSON);
            sw.tag = f->fid;
            [sw addTarget:self action:@selector(onSwitch:) forControlEvents:UIControlEventValueChanged];
            [card addSubview:sw];
            self.switchMap[@(f->fid)] = sw;

            if (hasSecondary) {
                UIButton *ex = [self makeSecondaryButtonForFeature:f
                                                             frame:CGRectMake(sw.frame.origin.x - 72.0,
                                                                              floor((H - 28.0) * 0.5), 66.0, 28.0)];
                [card addSubview:ex];
            }
            break;
        }
        case FTC_KIND_ONESHOT: {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
            b.frame = CGRectMake(W - 62.0, floor((H - 30.0) * 0.5), 54.0, 30.0);
            [b setTitle:@"Chay" forState:UIControlStateNormal];
            b.titleLabel.font = [UIFont boldSystemFontOfSize:12];
            [b setTitleColor:FTC_Color(FTC_C_TEXT) forState:UIControlStateNormal];
            b.backgroundColor = FTC_Color(FTC_C_CRIMSON);
            b.opaque = YES;
            b.layer.cornerRadius = 8.0;
            b.tag = f->fid;
            [b addTarget:self action:@selector(onOneshot:) forControlEvents:UIControlEventTouchUpInside];
            [card addSubview:b];

            if (hasSecondary) {
                UIButton *ex = [self makeSecondaryButtonForFeature:f
                                                             frame:CGRectMake(b.frame.origin.x - 74.0,
                                                                              floor((H - 30.0) * 0.5), 68.0, 30.0)];
                [card addSubview:ex];
            }
            break;
        }
        case FTC_KIND_MODE: {
            UISegmentedControl *seg = nil;
            CGFloat segW = 142.0;
            if (f->fid == 28) {
                seg = [[UISegmentedControl alloc] initWithItems:@[@"-1 ngay", @"+1 ngay"]];
                seg.momentary = YES;
            } else if (f->fid == 32) {
                seg = [[UISegmentedControl alloc] initWithItems:@[@"Thap", @"Vua", @"Cao"]];
                seg.selectedSegmentIndex = [self.modeIndex[@(32)] integerValue];
            } else if (f->fid == 42) {
                seg = [[UISegmentedControl alloc] initWithItems:@[@"1x", @"1.5x", @"2x", @"3x"]];
                seg.selectedSegmentIndex = [self.modeIndex[@(42)] integerValue];
                segW = 162.0;
            } else {
                seg = [[UISegmentedControl alloc] initWithItems:@[@"--"]];
            }
            seg.frame = CGRectMake(W - segW - 8.0, floor((H - 30.0) * 0.5), segW, 30.0);
            seg.tag = f->fid;
            seg.selectedSegmentTintColor = FTC_Color(FTC_C_CRIMSON);
            [seg setTitleTextAttributes:@{
                NSFontAttributeName: [UIFont boldSystemFontOfSize:11],
                NSForegroundColorAttributeName: FTC_Color(FTC_C_TEXT)
            } forState:UIControlStateNormal];
            [seg addTarget:self action:@selector(onSegment:) forControlEvents:UIControlEventValueChanged];
            [card addSubview:seg];
            self.segMap[@(f->fid)] = seg;
            break;
        }
        case FTC_KIND_STEP: {
            if (f->fid == 12) {
                CGFloat sx = W - 176.0;
                UISegmentedControl *seg = [[UISegmentedControl alloc]
                    initWithItems:@[@"Dmg", @"Hold", @"Succ", @"Great"]];
                seg.frame = CGRectMake(sx, 7.0, 168.0, 26.0);
                seg.selectedSegmentIndex = [self.modeIndex[@(12)] integerValue];
                seg.tag = 12;
                seg.selectedSegmentTintColor = FTC_Color(FTC_C_CRIMSON);
                [seg setTitleTextAttributes:@{
                    NSFontAttributeName: [UIFont boldSystemFontOfSize:10],
                    NSForegroundColorAttributeName: FTC_Color(FTC_C_TEXT)
                } forState:UIControlStateNormal];
                [seg addTarget:self action:@selector(onTicketKind:) forControlEvents:UIControlEventValueChanged];
                [card addSubview:seg];

                UIButton *plus = [UIButton buttonWithType:UIButtonTypeCustom];
                plus.frame = CGRectMake(W - 76.0, 39.0, 68.0, 26.0);
                [plus setTitle:@"+1 ve" forState:UIControlStateNormal];
                plus.titleLabel.font = [UIFont boldSystemFontOfSize:11.5];
                [plus setTitleColor:FTC_Color(FTC_C_TEXT) forState:UIControlStateNormal];
                plus.backgroundColor = FTC_Color(FTC_C_CRIMSON);
                plus.opaque = YES;
                plus.layer.cornerRadius = 7.0;
                plus.tag = 12;
                [plus addTarget:self action:@selector(onTicketPlus:) forControlEvents:UIControlEventTouchUpInside];
                [card addSubview:plus];
            } else {
                CGFloat sx = W - 178.0;
                CGFloat sy = floor((H - 29.0) * 0.5);
                UIStepper *stepper = [[UIStepper alloc] initWithFrame:CGRectMake(sx, sy, 94.0, 29.0)];
                stepper.tag = f->fid;
                NSInteger v = [self.stepValue[@(f->fid)] integerValue];
                if (f->fid == 6) { stepper.minimumValue = 0; stepper.maximumValue = 999; stepper.stepValue = 10; }
                if (f->fid == 9) { stepper.minimumValue = 1; stepper.maximumValue = 24; stepper.stepValue = 1; }
                stepper.value = v;
                [stepper addTarget:self action:@selector(onStepper:) forControlEvents:UIControlEventValueChanged];
                [card addSubview:stepper];

                UILabel *val = [[UILabel alloc] initWithFrame:CGRectMake(sx + 96.0, sy, 32.0, 29.0)];
                val.text = [NSString stringWithFormat:@"%ld", (long)v];
                val.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightBold];
                val.textColor = FTC_Color(FTC_C_GOLD);
                val.textAlignment = NSTextAlignmentCenter;
                [card addSubview:val];
                self.stepValMap[@(f->fid)] = val;

                UIButton *apply = [UIButton buttonWithType:UIButtonTypeCustom];
                apply.frame = CGRectMake(sx + 130.0, sy, 42.0, 29.0);
                [apply setTitle:(f->fid == 9) ? @"Nhay" : @"Dat" forState:UIControlStateNormal];
                apply.titleLabel.font = [UIFont boldSystemFontOfSize:11.5];
                [apply setTitleColor:FTC_Color(FTC_C_TEXT) forState:UIControlStateNormal];
                apply.backgroundColor = FTC_Color(FTC_C_CRIMSON);
                apply.opaque = YES;
                apply.layer.cornerRadius = 7.0;
                apply.tag = f->fid;
                [apply addTarget:self action:@selector(onStepApply:) forControlEvents:UIControlEventTouchUpInside];
                [card addSubview:apply];
            }
            break;
        }
    }
    return card;
}

- (UIButton *)makeSecondaryButtonForFeature:(const FTC_Feature *)f frame:(CGRect)frame {
    UIButton *ex = [UIButton buttonWithType:UIButtonTypeCustom];
    ex.frame = frame;
    NSString *t = (f->fid == 4) ? @"Doi mode" : (f->fid == 7) ? @"Giet ngay" : @"Chon kiem";
    [ex setTitle:t forState:UIControlStateNormal];
    ex.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [ex setTitleColor:FTC_Color(FTC_C_GOLD) forState:UIControlStateNormal];
    ex.backgroundColor = FTC_Color(FTC_C_BTN_BG);
    ex.opaque = YES;
    ex.layer.cornerRadius = 7.0;
    ex.layer.borderColor = FTC_Color(FTC_C_BORDER_HI).CGColor;
    ex.layer.borderWidth = 1.0;
    ex.tag = f->fid;
    [ex addTarget:self action:@selector(onSecondary:) forControlEvents:UIControlEventTouchUpInside];
    return ex;
}

// Fast O(1) in-place UI refresh for one single card (ZERO view creation/destruction).
- (void)refreshCardSubtitle:(const FTC_Feature *)f {
    if (!f) return;
    UILabel *sub = self.subLabelMap[@(f->fid)];
    if (!sub) return;
    NSString *status = self.statusText[@(f->fid)];
    BOOL showDesc = [self.descOpen[@(f->fid)] boolValue];
    NSInteger kind = [self.statusKind[@(f->fid)] integerValue];
    if (showDesc) {
        sub.text = [NSString stringWithUTF8String:f->desc];
        sub.textColor = FTC_Color(FTC_C_TEXT2);
    } else if (status.length > 0) {
        sub.text = status;
        sub.textColor = (kind == 1) ? FTC_Color(FTC_C_OK)
                      : (kind == 2) ? FTC_Color(FTC_C_ERR)
                                    : FTC_Color(FTC_C_TEXT2);
    } else {
        sub.text = [NSString stringWithUTF8String:f->desc];
        sub.textColor = FTC_Color(FTC_C_TEXT2);
    }
}

- (void)updateCardInPlace:(int)fid {
    const FTC_Feature *f = FTC_FeatureById(fid);
    if (!f) return;
    BOOL on = [self.switchOn[@(fid)] boolValue];
    UIView *card = self.cardMap[@(fid)];
    if (card) {
        card.backgroundColor = on ? FTC_Color(FTC_C_CARD_ON) : FTC_Color(FTC_C_CARD);
        card.layer.borderColor = on ? FTC_Color(FTC_C_CRIMSON).CGColor : FTC_Color(FTC_C_BORDER).CGColor;
    }
    UISwitch *sw = self.switchMap[@(fid)];
    if (sw && sw.isOn != on) {
        [sw setOn:on animated:NO];
    }
    [self refreshCardSubtitle:f];
    [self updateActiveCountBadge];
    [self updateTabAppearance];
}

- (void)setStatus:(int)fid text:(NSString *)text kind:(NSInteger)kind {
    if (text) {
        self.statusText[@(fid)] = text;
        self.statusKind[@(fid)] = @(kind);
        self.descOpen[@(fid)] = @(NO);
    } else {
        [self.statusText removeObjectForKey:@(fid)];
        [self.statusKind removeObjectForKey:@(fid)];
    }
}

- (NSString *)messageForCall:(FTC_CallResult)r {
    return [NSString stringWithUTF8String:FTC_CallResultMessage(r)];
}

- (UIViewController *)topViewController {
    UIViewController *vc = self.window.rootViewController;
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    return vc;
}

#pragma mark - Persistence (NSUserDefaults + Staggered Non-Blocking Startup Restore)

- (void)loadSavedPreferences {
    @try {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        self.maximized = [ud boolForKey:kPrefMaximized];
        NSInteger savedTab = [ud integerForKey:kPrefTab];
        if (savedTab >= 0 && savedTab < kTabCount) self.selectedTab = savedTab;
        if ([ud objectForKey:kPrefQuality]) {
            NSInteger q = [ud integerForKey:kPrefQuality];
            if (q >= 0 && q <= 2) self.modeIndex[@(32)] = @(q);
        }
        if ([ud objectForKey:kPrefSpeed]) {
            NSInteger sp = [ud integerForKey:kPrefSpeed];
            if (sp >= 0 && sp <= 3) self.modeIndex[@(42)] = @(sp);
        }
    } @catch (...) {}
}

- (void)saveLogoPosition {
    @try {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setDouble:self.logoButton.frame.origin.x forKey:kPrefLogoX];
        [ud setDouble:self.logoButton.frame.origin.y forKey:kPrefLogoY];
    } @catch (...) {}
}

- (void)saveSwitchState:(int)fid on:(BOOL)on {
    @try {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        NSDictionary *old = [ud dictionaryForKey:kPrefSwitches];
        NSMutableDictionary *m = old ? [old mutableCopy] : [NSMutableDictionary dictionary];
        NSString *key = [NSString stringWithFormat:@"%d", fid];
        if (on) m[key] = @(YES);
        else [m removeObjectForKey:key];
        [ud setObject:m forKey:kPrefSwitches];
    } @catch (...) {}
}

// Staggered restore: waits 1.2s after game window attach, then applies saved
// settings smoothly 1-by-1 (0.08s apart) so startup NEVER lags or stutters
// even when many cheats were left ON.
- (void)scheduleStaggeredRestoreIfNeeded {
    if (self.restoreScheduled) return;
    self.restoreScheduled = YES;

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [weakSelf beginStaggeredRestore];
    });
}

- (void)beginStaggeredRestore {
    @try {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        NSDictionary *saved = [ud dictionaryForKey:kPrefSwitches];
        NSMutableArray<dispatch_block_t> *queue = [NSMutableArray array];
        __weak typeof(self) weakSelf = self;

        // 1. FPS badge (instant, 0 game cost)
        if ([saved[@"40"] boolValue]) {
            self.switchOn[@(40)] = @(YES);
            [self setStatus:40 text:@"Da bat (goc trai day)" kind:1];
            [self setFpsBadgeVisible:YES];
        }

        // 2. Boost Max FPS (#41) or saved Quality Tier (#32)
        if ([saved[@"41"] boolValue]) {
            [queue addObject:^{
                CheatMenuView *s = weakSelf;
                if (!s) return;
                if (FTC_SetAntiLag(true) == FTC_CALL_OK) {
                    s.switchOn[@(41)] = @(YES);
                    [s setStatus:41 text:@"Da khoi phuc" kind:1];
                    [s updateCardInPlace:41];
                }
            }];
        } else if ([ud objectForKey:kPrefQuality]) {
            NSInteger qIdx = [ud integerForKey:kPrefQuality];
            if (qIdx >= 0 && qIdx <= 2) {
                [queue addObject:^{
                    CheatMenuView *s = weakSelf;
                    if (!s) return;
                    if (FTC_SetQualityTier((int)qIdx) == FTC_CALL_OK) {
                        s.modeIndex[@(32)] = @(qIdx);
                        [s setStatus:32 text:@"Da khoi phuc" kind:1];
                        [s updateCardInPlace:32];
                    }
                }];
            }
        }

        // 3. Speed Hack (#42) if > 1x
        if ([ud objectForKey:kPrefSpeed]) {
            NSInteger spIdx = [ud integerForKey:kPrefSpeed];
            if (spIdx > 0 && spIdx <= 3) {
                [queue addObject:^{
                    CheatMenuView *s = weakSelf;
                    if (!s) return;
                    if (FTC_SetTimeScale(kSpeedValues[spIdx]) == FTC_CALL_OK) {
                        s.modeIndex[@(42)] = @(spIdx);
                        [s setStatus:42 text:@"Da khoi phuc" kind:1];
                        [s updateCardInPlace:42];
                    }
                }];
            }
        }

        // 4. Saved runtime PATCH switches (staggered 1-by-1)
        for (size_t i = 0; i < kFTC_FeatureCount; i++) {
            const FTC_Feature *f = &kFTC_Features[i];
            NSString *k = [NSString stringWithFormat:@"%d", f->fid];
            if (![saved[k] boolValue]) continue;
            if (f->kind == FTC_KIND_PATCH) {
                int fid = f->fid;
                [queue addObject:^{
                    CheatMenuView *s = weakSelf;
                    if (!s) return;
                    FTC_PatchResult r = FTC_PatchApplyFeature(fid);
                    if (r == FTC_PATCH_OK) {
                        s.switchOn[@(fid)] = @(YES);
                        [s setStatus:fid text:@"Da khoi phuc" kind:1];
                    } else {
                        s.switchOn[@(fid)] = @(NO);
                        [s setStatus:fid text:[NSString stringWithUTF8String:FTC_PatchResultMessage(r)] kind:2];
                    }
                    [s updateCardInPlace:fid];
                }];
            } else if (f->fid == 7 || f->fid == 33) {
                [self.pendingDevToggleFids addObject:@(f->fid)];
            }
        }

        // Execute queued items spaced 80ms apart -> zero frame hitch!
        for (NSUInteger idx = 0; idx < queue.count; idx++) {
            dispatch_block_t task = queue[idx];
            int64_t delayNs = (int64_t)(idx * 80 * NSEC_PER_MSEC);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delayNs),
                           dispatch_get_main_queue(), task);
        }

        // Dev-toggles needing live ForgeRoom (#7, #33) retry gently until room loads.
        if (self.pendingDevToggleFids.count > 0) {
            self.pendingDevRestoreTries = 0;
            [self tryRestorePendingDevToggles];
        }
        [self updateActiveCountBadge];
        [self updateTabAppearance];
    } @catch (...) {}
}

- (void)tryRestorePendingDevToggles {
    @try {
        if (self.pendingDevToggleFids.count == 0) return;
        if (FTC_ToolsAvailable()) {
            NSArray<NSNumber *> *items = [self.pendingDevToggleFids copy];
            [self.pendingDevToggleFids removeAllObjects];
            for (NSNumber *num in items) {
                int fid = [num intValue];
                FTC_CallResult cr = (fid == 7) ? FTC_ToggleGodMode()
                                  : (fid == 33) ? FTC_ToggleMerchantShelfSlot()
                                                : FTC_CALL_ERR_UNAVAILABLE;
                if (cr == FTC_CALL_OK) {
                    self.switchOn[@(fid)] = @(YES);
                    [self setStatus:fid text:@"Da khoi phuc" kind:1];
                    [self updateCardInPlace:fid];
                }
            }
            return;
        }
        self.pendingDevRestoreTries++;
        if (self.pendingDevRestoreTries < 20) {
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [weakSelf tryRestorePendingDevToggles];
            });
        }
    } @catch (...) {}
}

- (void)onResetAllCheats {
    @try {
        for (size_t i = 0; i < kFTC_FeatureCount; i++) {
            const FTC_Feature *f = &kFTC_Features[i];
            if (f->kind == FTC_KIND_PATCH && [self.switchOn[@(f->fid)] boolValue]) {
                FTC_PatchRemoveFeature(f->fid);
            }
            if (f->fid == 41 && [self.switchOn[@(41)] boolValue]) {
                FTC_SetAntiLag(false);
            }
            if (f->fid == 7 && [self.switchOn[@(7)] boolValue]) {
                FTC_ToggleGodMode();
            }
            if (f->fid == 33 && [self.switchOn[@(33)] boolValue]) {
                FTC_ToggleMerchantShelfSlot();
            }
            self.switchOn[@(f->fid)] = @(NO);
            [self setStatus:f->fid text:nil kind:0];
        }
        [self setFpsBadgeVisible:NO];
        if ([self.modeIndex[@(42)] integerValue] != 0) {
            FTC_SetTimeScale(1.0f);
            self.modeIndex[@(42)] = @(0);
            UISegmentedControl *seg = self.segMap[@(42)];
            if (seg) seg.selectedSegmentIndex = 0;
        }
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud removeObjectForKey:kPrefSwitches];
        [ud removeObjectForKey:kPrefQuality];
        [ud removeObjectForKey:kPrefSpeed];
        [self buildActiveTabCards];
        [self updateActiveCountBadge];
        [self updateTabAppearance];
    } @catch (...) {}
}

#pragma mark - Feature Actions (Zero-Lag In-Place Updates)

- (void)onToggleDesc:(UIButton *)sender {
    int fid = (int)sender.tag;
    self.descOpen[@(fid)] = @(![self.descOpen[@(fid)] boolValue]);
    [self refreshCardSubtitle:FTC_FeatureById(fid)];
}

- (void)onSwitch:(UISwitch *)sender {
    @try {
        int fid = (int)sender.tag;
        BOOL wantOn = sender.isOn;
        const FTC_Feature *f = FTC_FeatureById(fid);
        if (!f) return;

        if (f->kind == FTC_KIND_PATCH) {
            FTC_PatchResult r = wantOn ? FTC_PatchApplyFeature(fid)
                                       : FTC_PatchRemoveFeature(fid);
            if (r == FTC_PATCH_OK) {
                self.switchOn[@(fid)] = @(wantOn);
                [self saveSwitchState:fid on:wantOn];
                [self setStatus:fid text:(wantOn ? @"Da bat" : @"Da tat") kind:1];
                if (fid == 10 && wantOn) {
                    FTC_CallResult cr = FTC_FillFever();
                    if (cr != FTC_CALL_OK) {
                        [self setStatus:fid text:[NSString stringWithFormat:@"Patch bat; %@",
                                                  [self messageForCall:cr]] kind:1];
                    }
                }
            } else {
                sender.on = !wantOn;
                [self setStatus:fid text:[NSString stringWithUTF8String:FTC_PatchResultMessage(r)] kind:2];
            }
        } else { // DEV_TOGGLE
            if (fid == 40) {
                self.switchOn[@(40)] = @(wantOn);
                [self saveSwitchState:40 on:wantOn];
                [self setStatus:40 text:(wantOn ? @"Da bat (goc trai day)" : @"Da tat") kind:1];
                [self setFpsBadgeVisible:wantOn];
                [self updateCardInPlace:40];
                return;
            }
            FTC_CallResult cr = FTC_CALL_ERR_UNAVAILABLE;
            if (fid == 7) cr = FTC_ToggleGodMode();
            else if (fid == 33) cr = FTC_ToggleMerchantShelfSlot();
            else if (fid == 41) cr = FTC_SetAntiLag(wantOn);
            if (cr == FTC_CALL_OK) {
                self.switchOn[@(fid)] = @(wantOn);
                [self saveSwitchState:fid on:wantOn];
                [self setStatus:fid text:(wantOn ? @"Da bat" : @"Da tat") kind:1];
            } else {
                sender.on = !wantOn;
                [self setStatus:fid text:[self messageForCall:cr] kind:2];
            }
        }
        [self updateCardInPlace:fid];
    } @catch (...) {}
}

- (void)onOneshot:(UIButton *)sender {
    @try {
        int fid = (int)sender.tag;
        if (fid == 27) {
            UIViewController *root = [self topViewController];
            if (!root) {
                [self setStatus:27 text:@"Khong hien duoc hop thoai xac nhan" kind:2];
                [self updateCardInPlace:27];
                return;
            }
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:@"Choi lai tu dau?"
                                 message:@"Reset run hien tai. Run dang choi se MAT."
                          preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Huy"
                                                      style:UIAlertActionStyleCancel handler:nil]];
            __weak typeof(self) weakSelf = self;
            [alert addAction:[UIAlertAction actionWithTitle:@"Reset"
                                                      style:UIAlertActionStyleDestructive
                                                    handler:^(UIAlertAction *a) {
                [weakSelf runOneshot:27];
            }]];
            [root presentViewController:alert animated:YES completion:nil];
            return;
        }
        [self runOneshot:fid];
    } @catch (...) {}
}

- (void)runOneshot:(int)fid {
    @try {
        FTC_CallResult cr = FTC_CALL_ERR_UNAVAILABLE;
        switch (fid) {
            case 2: cr = FTC_AddGold(9.999e99); break;
            case 3: case 37: cr = FTC_GiveAllRelics(); break;
            case 8: cr = FTC_SummonMerchant(); break;
            case 23: cr = FTC_GiveSecretDoorKey(); break;
            case 24: cr = FTC_EnterSkillArena(); break;
            case 25: cr = FTC_AddSwordCredits(); break;
            case 26: cr = FTC_RevealCodex(); break;
            case 27: cr = FTC_ResetRun(); break;
            case 29: cr = FTC_StartDragonFight(); break;
            case 30: cr = FTC_ForceDragonLoss(); break;
            case 31: cr = FTC_OpenArmory(); break;
            default: break;
        }
        [self setStatus:fid
                   text:(cr == FTC_CALL_OK) ? @"Da chay thanh cong" : [self messageForCall:cr]
                   kind:(cr == FTC_CALL_OK) ? 1 : 2];
        [self updateCardInPlace:fid];
    } @catch (...) {}
}

- (void)onSecondary:(UIButton *)sender {
    @try {
        int fid = (int)sender.tag;
        FTC_CallResult cr = FTC_CALL_ERR_UNAVAILABLE;
        if (fid == 4) {
            cr = FTC_CycleForgeMode();
            if (cr == FTC_CALL_OK && [self.switchOn[@(4)] boolValue]) {
                [self setStatus:4 text:@"Da doi mode (patch #4 dang BAT -> luon AlwaysSuccess)" kind:1];
                [self updateCardInPlace:4];
                return;
            }
        }
        else if (fid == 7) cr = FTC_KillDragon();
        else if (fid == 24) cr = FTC_OpenSwordPicker();
        [self setStatus:fid
                   text:(cr == FTC_CALL_OK) ? @"Da chay thanh cong" : [self messageForCall:cr]
                   kind:(cr == FTC_CALL_OK) ? 1 : 2];
        [self updateCardInPlace:fid];
    } @catch (...) {}
}

- (void)onSegment:(UISegmentedControl *)sender {
    @try {
        int fid = (int)sender.tag;
        NSInteger idx = sender.selectedSegmentIndex;
        if (fid == 28) {
            FTC_CallResult cr = (idx == 0) ? FTC_SkipDay() : FTC_NextDay();
            [self setStatus:fid
                       text:(cr == FTC_CALL_OK) ? (idx == 0 ? @"Da lui 1 ngay" : @"Da tien 1 ngay")
                                                : [self messageForCall:cr]
                       kind:(cr == FTC_CALL_OK) ? 1 : 2];
            [self updateCardInPlace:fid];
            return;
        }
        if (fid == 32) {
            FTC_CallResult cr = FTC_SetQualityTier((int)idx);
            if (cr == FTC_CALL_OK) {
                self.modeIndex[@(32)] = @(idx);
                [[NSUserDefaults standardUserDefaults] setInteger:idx forKey:kPrefQuality];
                [self setStatus:32 text:@"Da doi do hoa" kind:1];
            } else {
                [self setStatus:32 text:[self messageForCall:cr] kind:2];
            }
            [self updateCardInPlace:32];
            return;
        }
        if (fid == 42) {
            if (idx < 0 || idx > 3) idx = 0;
            FTC_CallResult cr = FTC_SetTimeScale(kSpeedValues[idx]);
            if (cr == FTC_CALL_OK) {
                self.modeIndex[@(42)] = @(idx);
                [[NSUserDefaults standardUserDefaults] setInteger:idx forKey:kPrefSpeed];
                [self setStatus:42
                           text:[NSString stringWithFormat:@"Toc do %.1fx", kSpeedValues[idx]]
                           kind:1];
            } else {
                [self setStatus:42 text:[self messageForCall:cr] kind:2];
            }
            [self updateCardInPlace:42];
        }
    } @catch (...) {}
}

- (void)onTicketKind:(UISegmentedControl *)sender {
    self.modeIndex[@(12)] = @(sender.selectedSegmentIndex);
}

- (void)onTicketPlus:(UIButton *)sender {
    @try {
        int outcome = (int)[self.modeIndex[@(12)] integerValue] + 1;
        FTC_CallResult cr = FTC_AddRunTickets(outcome, 1);
        [self setStatus:12
                   text:(cr == FTC_CALL_OK) ? @"Da cong +1 ve" : [self messageForCall:cr]
                   kind:(cr == FTC_CALL_OK) ? 1 : 2];
        [self updateCardInPlace:12];
    } @catch (...) {}
}

- (void)onStepper:(UIStepper *)sender {
    @try {
        NSInteger fid = sender.tag;
        NSInteger v = (NSInteger)sender.value;
        self.stepValue[@(fid)] = @(v);
        UILabel *val = self.stepValMap[@(fid)];
        if (val) val.text = [NSString stringWithFormat:@"%ld", (long)v];
    } @catch (...) {}
}

- (void)onStepApply:(UIButton *)sender {
    @try {
        int fid = (int)sender.tag;
        NSInteger v = [self.stepValue[@(fid)] integerValue];
        FTC_CallResult cr = FTC_CALL_ERR_UNAVAILABLE;
        if (fid == 6) cr = FTC_SetAnvilGrade((int)v);
        else if (fid == 9) cr = FTC_JumpToDay((int)v);
        [self setStatus:fid
                   text:(cr == FTC_CALL_OK) ? [NSString stringWithFormat:@"Da ap dung (%ld)", (long)v]
                                            : [self messageForCall:cr]
                   kind:(cr == FTC_CALL_OK) ? 1 : 2];
        [self updateCardInPlace:fid];
    } @catch (...) {}
}

#pragma mark - FPS Badge (Fixed Bottom-Left, Ultra-Lightweight)

- (void)setFpsBadgeVisible:(BOOL)visible {
    @try {
        [self layoutFpsBadge];
        self.fpsBadge.hidden = !visible;
        if (visible) {
            [self stopFpsLink];
            self.fpsFrames = 0;
            self.fpsLastUpdate = 0;
            self.lastDisplayedFps = -1;
            self.fpsBadge.text = @"-- FPS";
            CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self
                                                               selector:@selector(onFpsTick:)];
            if (@available(iOS 15.0, *)) {
                link.preferredFrameRateRange = CAFrameRateRangeMake(60, 120, 120);
            }
            [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
            self.fpsLink = link;
        } else {
            [self stopFpsLink];
            self.lastDisplayedFps = -1;
            self.fpsBadge.text = @"-- FPS";
        }
    } @catch (...) {}
}

- (void)stopFpsLink {
    [self.fpsLink invalidate];
    self.fpsLink = nil;
}

- (void)onFpsTick:(CADisplayLink *)link {
    CFTimeInterval now = link.timestamp;
    if (self.fpsLastUpdate == 0) {
        self.fpsLastUpdate = now;
        self.fpsFrames = 0;
        return;
    }
    self.fpsFrames++;
    CFTimeInterval elapsed = now - self.fpsLastUpdate;
    if (elapsed >= 1.0) {
        NSInteger fps = (NSInteger)lround(self.fpsFrames / elapsed);
        if (fps != self.lastDisplayedFps) {
            self.lastDisplayedFps = fps;
            self.fpsBadge.text = [NSString stringWithFormat:@"%ld FPS", (long)fps];
        }
        self.fpsFrames = 0;
        self.fpsLastUpdate = now;
    }
}

- (void)dealloc {
    [self stopFpsLink];
}

@end
