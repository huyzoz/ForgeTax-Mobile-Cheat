// CheatMenuView.mm — Peak 16:9 Zero-Lag Landscape UI + Cutout Demon Logo.
//
// Performance & Crash-Free Architecture:
//   - Zero masksToBounds+cornerRadius on scrollView's ancestor panel (eliminates
//     the #1 iOS Core Animation offscreen-render scroll drop on A10 3x Retina).
//   - Zero heavy UISwitch / UISegmentedControl / UIStepper inside scroll cards;
//     all controls are flat, solid-opaque UIButtons (0 blur, 0 shadow layers).
//   - Zero layoutPanel / view rebuild during logo drag (moves CALayer position
//     only via .center during drag; repositions panel once on drag end).
//   - GPU-accelerated marquee text (FTCMarqueeLabel) with dual-edge fade mask
//     applied ONLY to overflowing labels (0 main-thread CPU cost).
//   - #4 Forge Always Win: 2 modes — Success 100% vs Great Success 100% (Purple),
//     100% IL2CPP (no JIT needed), updates outside display live.
//   - Top-left fixed FPS counter (detached from logo).
//   - Full Vietnamese (with diacritics) + English switcher (#43) persisted in NSUserDefaults.
#import "CheatMenuView.h"
#import "FeatureCatalog.h"
#import "PatchEngine.h"
#import "GameBridge.h"
#import "LogoImageData.h"

#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <string.h>

// ---- Crimson / Obsidian / Gold / Purple Palette (100% solid opaques) ----
#define FTC_C_PANEL      0x120D0E
#define FTC_C_HEADER     0x1A1113
#define FTC_C_SIDEBAR    0x160F11
#define FTC_C_TAB_ON     0x2C1519
#define FTC_C_CARD       0x1C1416
#define FTC_C_CARD_ON    0x2D1519
#define FTC_C_CARD_PURP  0x231136
#define FTC_C_BTN_BG     0x2A1B1E
#define FTC_C_BTN_OFF    0x261B1D
#define FTC_C_BORDER     0x352024
#define FTC_C_BORDER_HI  0x59252C
#define FTC_C_CRIMSON    0xE52432
#define FTC_C_CRIMSON_HI 0xFF4554
#define FTC_C_PURPLE     0x9B30FF
#define FTC_C_PURPLE_HI  0xD4A5FF
#define FTC_C_GOLD       0xF7D774
#define FTC_C_TEXT       0xF5ECEE
#define FTC_C_TEXT2      0xB8A3A7
#define FTC_C_OK         0x6BE684
#define FTC_C_ERR        0xFF8A65
#define FTC_C_FPS_BG     0x120C0D
#define FTC_C_FPS_TXT    0x7DFF8A

static UIColor *FTC_Color(uint32_t hex) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0 alpha:1.0];
}

static const CGFloat kLogoSize    = 52.0;
static const CGFloat kLogoGap     = 10.0;
static const CGFloat kMargin      = 8.0;
static const CGFloat kHeaderH     = 38.0;
static const CGFloat kSidebarW    = 112.0;
static const CGFloat kCompactMaxW = 548.0;
static const CGFloat kCompactMaxH = 326.0;

// Persistence keys
static NSString * const kPrefSwitches   = @"FTC_v3_switches";
static NSString * const kPrefForgeGreat = @"FTC_v3_forgeGreat";
static NSString * const kPrefQuality    = @"FTC_v3_quality";
static NSString * const kPrefSpeed      = @"FTC_v3_speed";
static NSString * const kPrefLangEn     = @"FTC_v3_langEn";
static NSString * const kPrefLogoX      = @"FTC_v3_logoX";
static NSString * const kPrefLogoY      = @"FTC_v3_logoY";
static NSString * const kPrefMaximized  = @"FTC_v3_maximized";
static NSString * const kPrefTab        = @"FTC_v3_tab";

typedef struct {
    const char *cid;
    const char *vi;
    const char *en;
} FTCTab;

static const FTCTab kTabs[] = {
    {"forge",   "Rèn",         "Forge"},
    {"res",     "Tài nguyên",  "Resources"},
    {"relic",   "Di vật",      "Relics"},
    {"shop",    "Thương nhân", "Merchant"},
    {"dragon",  "Rồng",        "Dragon"},
    {"day",     "Ngày & Chơi", "Day & Play"},
    {"ads",     "Quảng cáo",   "Ads"},
    {"setting", "Cài đặt",     "Settings"},
};
static const NSInteger kTabCount = (NSInteger)(sizeof(kTabs) / sizeof(kTabs[0]));
static const float kSpeedValues[] = { 1.0f, 1.5f, 2.0f, 3.0f };

#pragma mark - FTCMarqueeLabel (GPU-only glide + dual-edge fade when overflowing)

@interface FTCMarqueeLabel : UIView
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) CAGradientLayer *fadeMask;
@property (nonatomic, copy) NSString *currentText;
@property (nonatomic, assign) CGFloat lastWidth;
- (void)configureText:(NSString *)text font:(UIFont *)font color:(UIColor *)color;
@end

@implementation FTCMarqueeLabel

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.clipsToBounds = YES;
    self.userInteractionEnabled = NO;
    self.backgroundColor = [UIColor clearColor];
    _label = [[UILabel alloc] initWithFrame:self.bounds];
    _label.numberOfLines = 1;
    _label.lineBreakMode = NSLineBreakByClipping;
    _label.backgroundColor = [UIColor clearColor];
    [self addSubview:_label];
    return self;
}

- (void)configureText:(NSString *)text font:(UIFont *)font color:(UIColor *)color {
    NSString *safeText = text ?: @"";
    self.label.font = font;
    self.label.textColor = color;
    CGFloat viewW = self.bounds.size.width;
    CGFloat viewH = self.bounds.size.height;
    if ([self.currentText isEqualToString:safeText] && fabs(self.lastWidth - viewW) < 1.0) {
        return;
    }
    self.currentText = safeText;
    self.lastWidth = viewW;
    self.label.text = safeText;
    [self.label.layer removeAllAnimations];
    self.label.layer.transform = CATransform3DIdentity;

    CGFloat textW = ceil([safeText sizeWithAttributes:@{NSFontAttributeName: font}].width);
    if (textW <= viewW || viewW < 20.0) {
        // Fits statically: ZERO mask, ZERO animation, ZERO GPU cost!
        self.label.frame = CGRectMake(0, 0, viewW, viewH);
        self.layer.mask = nil;
        return;
    }

    // Overflows: apply smooth fade on BOTH left & right edges + GPU-only keyframe glide.
    CGFloat edgePad = 8.0;
    self.label.frame = CGRectMake(edgePad, 0, textW + edgePad, viewH);

    if (!self.fadeMask) {
        CAGradientLayer *g = [CAGradientLayer layer];
        g.startPoint = CGPointMake(0.0, 0.5);
        g.endPoint = CGPointMake(1.0, 0.5);
        g.colors = @[
            (id)[UIColor clearColor].CGColor,
            (id)[UIColor blackColor].CGColor,
            (id)[UIColor blackColor].CGColor,
            (id)[UIColor clearColor].CGColor,
        ];
        g.locations = @[@0.0, @0.09, @0.91, @1.0];
        self.fadeMask = g;
    }
    self.fadeMask.frame = self.bounds;
    self.layer.mask = self.fadeMask;

    CGFloat travel = (textW + edgePad * 2.0) - viewW;
    CFTimeInterval moveDur = MAX(2.0, travel / 32.0);
    CFTimeInterval pauseDur = 1.2;
    CFTimeInterval totalDur = moveDur * 2.0 + pauseDur * 2.0;

    CAKeyframeAnimation *anim = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    anim.values = @[@(0.0), @(0.0), @(-travel), @(-travel), @(0.0)];
    anim.keyTimes = @[
        @(0.0),
        @(pauseDur / totalDur),
        @((pauseDur + moveDur) / totalDur),
        @((pauseDur * 2.0 + moveDur) / totalDur),
        @(1.0)
    ];
    anim.duration = totalDur;
    anim.repeatCount = HUGE_VALF;
    anim.removedOnCompletion = NO;
    anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [self.label.layer addAnimation:anim forKey:@"ftcMarquee"];
}

@end

#pragma mark - CheatMenuView

@interface CheatMenuView ()
@property (nonatomic, strong) UIButton *logoButton;
@property (nonatomic, strong) UILabel *fpsBadge;

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

// Active tab card references for O(1) in-place updates (ZERO view rebuild on tap)
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UIView *> *cardMap;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, FTCMarqueeLabel *> *titleMarqueeMap;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, FTCMarqueeLabel *> *subMarqueeMap;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UIButton *> *toggleBtnMap;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UIButton *> *forgeModeBtnMap;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UILabel *> *stepValMap;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSArray<UIButton *> *> *pillGroupMap;

// Window / layout state
@property (nonatomic, assign) BOOL menuOpen;
@property (nonatomic, assign) BOOL maximized;
@property (nonatomic, assign) BOOL english;
@property (nonatomic, assign) BOOL forgeGreatMode; // #4 mode: NO = Thành công 100%, YES = Đại thành công 100% (tím)
@property (nonatomic, assign) NSInteger selectedTab;
@property (nonatomic, assign) BOOL logoPositioned;
@property (nonatomic, assign) BOOL isDraggingLogo;
@property (nonatomic, assign) CGPoint dragStart;
@property (nonatomic, assign) CGPoint dragStartCenter;
@property (nonatomic, assign) CGSize lastLayoutSize;
@property (nonatomic, assign) CGFloat lastScrollWidth;

// FPS counter (only while #40 is ON) + Great forge keep-alive (only while #4 Great is ON)
@property (nonatomic, strong) CADisplayLink *fpsLink;
@property (nonatomic, assign) NSInteger fpsFrames;
@property (nonatomic, assign) CFTimeInterval fpsLastUpdate;
@property (nonatomic, assign) NSInteger lastDisplayedFps;
@property (nonatomic, strong) NSTimer *greatForgeTimer;

// Feature state
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *switchOn;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *stepValue;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *modeIndex;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *statusText;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *statusKind; // 0=neutral, 1=ok, 2=err, 3=purple
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *descOpen;

// Staggered non-blocking startup restore
@property (nonatomic, assign) BOOL restoreScheduled;
@property (nonatomic, assign) NSInteger pendingDevRestoreTries;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *pendingDevToggleFids;
@end

@implementation CheatMenuView

- (NSString *)L:(NSString *)vi en:(NSString *)en {
    return self.english ? en : vi;
}

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
    _titleMarqueeMap = [NSMutableDictionary dictionary];
    _subMarqueeMap = [NSMutableDictionary dictionary];
    _toggleBtnMap = [NSMutableDictionary dictionary];
    _forgeModeBtnMap = [NSMutableDictionary dictionary];
    _stepValMap = [NSMutableDictionary dictionary];
    _pillGroupMap = [NSMutableDictionary dictionary];
    _tabButtons = [NSMutableArray array];
    _tabIndicators = [NSMutableArray array];
    _pendingDevToggleFids = [NSMutableArray array];

    _menuOpen = NO;
    _maximized = NO;
    _english = NO;
    _forgeGreatMode = NO;
    _selectedTab = 0;
    _logoPositioned = NO;
    _isDraggingLogo = NO;
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

#pragma mark - Cutout Demon Logo + Top-Left Fixed FPS Badge

- (void)buildLogo {
    UIButton *logo = [UIButton buttonWithType:UIButtonTypeCustom];
    logo.frame = CGRectMake(0, 0, kLogoSize, kLogoSize);
    logo.backgroundColor = [UIColor clearColor];
    logo.opaque = NO;
    logo.clipsToBounds = NO;
    logo.accessibilityLabel = @"Mở / đóng menu cheat";

    NSData *pngData = [NSData dataWithBytesNoCopy:(void *)kFTC_LogoPngData
                                           length:kFTC_LogoPngSize
                                     freeWhenDone:NO];
    UIImage *img = [UIImage imageWithData:pngData scale:3.0];
    if (img) {
        [logo setImage:img forState:UIControlStateNormal];
        [logo setImage:img forState:UIControlStateHighlighted];
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

    // Top-left fixed FPS counter (solid opaque, no shadow, completely detached from logo)
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

// ZERO-LAG DRAG: During UIGestureRecognizerStateChanged, ONLY updates logoButton.center
// (pure GPU layer position update, ZERO layoutSubviews, ZERO layoutPanel, ZERO card rebuild).
- (void)onLogoPan:(UIPanGestureRecognizer *)pan {
    @try {
        CGPoint loc = [pan locationInView:self];
        if (pan.state == UIGestureRecognizerStateBegan) {
            self.isDraggingLogo = YES;
            self.dragStart = loc;
            self.dragStartCenter = self.logoButton.center;
        } else if (pan.state == UIGestureRecognizerStateChanged) {
            UIEdgeInsets safe = [self ftcSafeInsets];
            CGFloat half = kLogoSize * 0.5;
            CGFloat minX = safe.left + half;
            CGFloat maxX = MAX(minX, self.bounds.size.width - safe.right - half);
            CGFloat minY = safe.top + half;
            CGFloat maxY = MAX(minY, self.bounds.size.height - safe.bottom - half);
            CGFloat cx = MAX(minX, MIN(self.dragStartCenter.x + (loc.x - self.dragStart.x), maxX));
            CGFloat cy = MAX(minY, MIN(self.dragStartCenter.y + (loc.y - self.dragStart.y), maxY));
            self.logoButton.center = CGPointMake(cx, cy);
        } else if (pan.state == UIGestureRecognizerStateEnded ||
                   pan.state == UIGestureRecognizerStateCancelled) {
            self.isDraggingLogo = NO;
            [self saveLogoPosition];
            if (_menuOpen) [self layoutPanel];
        }
    } @catch (...) {
        self.isDraggingLogo = NO;
    }
}

#pragma mark - 16:9 Panel Chrome (Zero Offscreen Masks Around ScrollView)

- (void)buildPanel {
    // CRITICAL PERFORMANCE FIX: masksToBounds = NO on the panel container so
    // UIScrollView inside NEVER triggers an offscreen 3x Retina rounded-mask render pass!
    UIView *panel = [[UIView alloc] initWithFrame:CGRectZero];
    panel.backgroundColor = FTC_Color(FTC_C_PANEL);
    panel.opaque = YES;
    panel.layer.cornerRadius = 14.0;
    panel.layer.borderColor = FTC_Color(FTC_C_BORDER_HI).CGColor;
    panel.layer.borderWidth = 1.5;
    panel.layer.masksToBounds = NO;
    panel.hidden = YES;
    [self addSubview:panel];
    self.panel = panel;

    // Header bar (top corners rounded to fit cleanly inside panel border)
    UIView *header = [[UIView alloc] initWithFrame:CGRectZero];
    header.backgroundColor = FTC_Color(FTC_C_HEADER);
    header.opaque = YES;
    header.layer.cornerRadius = 12.0;
    header.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
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
    badge.font = [UIFont boldSystemFontOfSize:10.5];
    badge.textColor = FTC_Color(FTC_C_CRIMSON_HI);
    badge.backgroundColor = FTC_Color(FTC_C_TAB_ON);
    badge.opaque = YES;
    badge.textAlignment = NSTextAlignmentCenter;
    badge.layer.cornerRadius = 7.0;
    badge.layer.masksToBounds = YES;
    [header addSubview:badge];
    self.activeCountBadge = badge;

    // Minimize button ("−") -> collapses back to demon logo
    UIButton *minBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [minBtn setTitle:@"−" forState:UIControlStateNormal];
    minBtn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [minBtn setTitleColor:FTC_Color(FTC_C_TEXT) forState:UIControlStateNormal];
    minBtn.backgroundColor = FTC_Color(FTC_C_BTN_BG);
    minBtn.opaque = YES;
    minBtn.layer.cornerRadius = 7.0;
    minBtn.layer.borderColor = FTC_Color(FTC_C_BORDER_HI).CGColor;
    minBtn.layer.borderWidth = 1.0;
    [minBtn addTarget:self action:@selector(onMinimizeTap) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:minBtn];
    self.minimizeButton = minBtn;

    // Expand / Restore button -> compact 16:9 <-> rounded full-screen
    UIButton *expBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    expBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [expBtn setTitleColor:FTC_Color(FTC_C_GOLD) forState:UIControlStateNormal];
    expBtn.backgroundColor = FTC_Color(FTC_C_BTN_BG);
    expBtn.opaque = YES;
    expBtn.layer.cornerRadius = 7.0;
    expBtn.layer.borderColor = FTC_Color(FTC_C_BORDER_HI).CGColor;
    expBtn.layer.borderWidth = 1.0;
    [expBtn addTarget:self action:@selector(onExpandTap) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:expBtn];
    self.expandButton = expBtn;

    // Left Sidebar (bottom-left corner rounded cleanly)
    UIView *sidebar = [[UIView alloc] initWithFrame:CGRectZero];
    sidebar.backgroundColor = FTC_Color(FTC_C_SIDEBAR);
    sidebar.opaque = YES;
    sidebar.layer.cornerRadius = 12.0;
    sidebar.layer.maskedCorners = kCALayerMinXMaxYCorner;
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
        tb.titleLabel.font = [UIFont boldSystemFontOfSize:11.5];
        tb.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        tb.opaque = YES;
        tb.layer.cornerRadius = 7.0;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        tb.contentEdgeInsets = UIEdgeInsetsMake(0, 9, 0, 5);
#pragma clang diagnostic pop
        [tb addTarget:self action:@selector(onSelectTab:) forControlEvents:UIControlEventTouchUpInside];

        UIView *ind = [[UIView alloc] initWithFrame:CGRectMake(0, 4, 3, 18)];
        ind.backgroundColor = FTC_Color(FTC_C_CRIMSON_HI);
        ind.opaque = YES;
        ind.hidden = YES;
        [tb addSubview:ind];

        [sidebar addSubview:tb];
        [self.tabButtons addObject:tb];
        [self.tabIndicators addObject:ind];
    }

    // Right ScrollView: solid opaque, NO cornerRadius -> 0 offscreen rendering!
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scroll.backgroundColor = FTC_Color(FTC_C_PANEL);
    scroll.opaque = YES;
    scroll.clipsToBounds = YES;
    scroll.showsVerticalScrollIndicator = YES;
    scroll.alwaysBounceVertical = NO;
    scroll.delaysContentTouches = NO;
    [panel addSubview:scroll];
    self.scrollView = scroll;

    [self updateTabAppearance];
    [self updateActiveCountBadge];
    [self updateExpandButtonGlyph];
}

#pragma mark - Attach & Layout (Logo-Clear 16:9 + Full-Screen Rounded + Top-Left FPS)

- (void)attachToWindow:(UIWindow *)window {
    @try {
        if (!window) return;
        self.frame = window.bounds;
        if (self.superview != window) [window addSubview:self];
        if (window.subviews.lastObject != self) [window bringSubviewToFront:self];
        [self ensureLogoPositioned];
        [self layoutFpsBadge];
        if (_menuOpen) [self layoutPanel];
        [self scheduleStaggeredRestoreIfNeeded];
    } @catch (...) {}
}

- (void)ensureLogoPositioned {
    if (self.isDraggingLogo) return;
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

// Top-left fixed FPS counter (always pinned top-left inside safe area).
- (void)layoutFpsBadge {
    @try {
        CGFloat bw = self.bounds.size.width;
        CGFloat bh = self.bounds.size.height;
        if (bw < 100 || bh < 100) return;
        UIEdgeInsets safe = [self ftcSafeInsets];
        self.fpsBadge.frame = CGRectMake(safe.left, safe.top, 64.0, 24.0);
    } @catch (...) {}
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.isDraggingLogo) return;
    @try {
        if (self.superview && self.superview.subviews.lastObject != self) {
            [self.superview bringSubviewToFront:self];
        }
        if (self.bounds.size.width < 100 || self.bounds.size.height < 100) return;
        [self ensureLogoPositioned];
        if (!CGSizeEqualToSize(self.bounds.size, self.lastLayoutSize)) {
            self.lastLayoutSize = self.bounds.size;
            [self layoutFpsBadge];
            if (_menuOpen) [self layoutPanel];
        }
    } @catch (...) {}
}

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
                y = MAX(safeTop, MIN(logo.origin.y, safeBottom - ph));
            }
            x = putLeft ? (logo.origin.x - kLogoGap - pw)
                        : (logo.origin.x + kLogoSize + kLogoGap);
        } else {
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
        self.panel.layer.cornerRadius = self.maximized ? 16.0 : 14.0;

        CGFloat W = self.panel.bounds.size.width;
        CGFloat H = self.panel.bounds.size.height;
        CGFloat inset = 2.0;

        self.headerBar.frame = CGRectMake(inset, inset, W - inset * 2.0, kHeaderH);
        self.headerAccent.frame = CGRectMake(0, kHeaderH - 1.5, W - inset * 2.0, 1.5);
        self.titleLabel.frame = CGRectMake(12, 0, 114, kHeaderH - 2);
        self.activeCountBadge.frame = CGRectMake(126, (kHeaderH - 20) * 0.5, 62, 20);

        CGFloat btnW = 30.0, btnH = 26.0, btnY = (kHeaderH - btnH) * 0.5;
        CGFloat hW = W - inset * 2.0;
        self.minimizeButton.frame = CGRectMake(hW - 8 - btnW, btnY, btnW, btnH);
        self.expandButton.frame = CGRectMake(hW - 8 - btnW - 6 - btnW, btnY, btnW, btnH);

        CGFloat bodyY = inset + kHeaderH;
        CGFloat bodyH = MAX(80.0, H - bodyY - inset - 4.0);
        CGFloat sideW = (W < 380.0) ? 94.0 : kSidebarW;
        self.sidebar.frame = CGRectMake(inset, bodyY, sideW, bodyH);
        self.sidebarDivider.frame = CGRectMake(inset + sideW, bodyY, 1.0, bodyH);

        CGFloat padY = 5.0, gapY = 3.0;
        CGFloat tabH = floor((bodyH - padY * 2.0 - gapY * (kTabCount - 1)) / (CGFloat)kTabCount);
        tabH = MAX(22.0, MIN(36.0, tabH));
        for (NSInteger i = 0; i < kTabCount; i++) {
            UIButton *tb = self.tabButtons[i];
            tb.frame = CGRectMake(5.0, padY + i * (tabH + gapY), sideW - 10.0, tabH);
            UIView *ind = self.tabIndicators[i];
            ind.frame = CGRectMake(0, 4.0, 3.0, MAX(12.0, tabH - 8.0));
        }

        CGFloat contentX = inset + sideW + 1.0;
        CGFloat contentW = MAX(140.0, W - contentX - inset - 4.0);
        self.scrollView.frame = CGRectMake(contentX, bodyY, contentW, bodyH);

        if (fabs(contentW - self.lastScrollWidth) > 8.0 || self.scrollView.subviews.count == 0) {
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

- (void)onMinimizeTap { [self setMenuOpen:NO]; }

- (void)onExpandTap {
    self.maximized = !self.maximized;
    [self updateExpandButtonGlyph];
    [[NSUserDefaults standardUserDefaults] setBool:self.maximized forKey:kPrefMaximized];
    [self layoutPanel];
}

- (void)updateExpandButtonGlyph {
    [self.expandButton setTitle:(self.maximized ? @"⤡" : @"⤢") forState:UIControlStateNormal];
}

#pragma mark - Tabs & Ultra-Lightweight Flat Cards (0 UISwitch, 0 UISegmentedControl, 0 Auto Layout)

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
        NSString *baseName = [NSString stringWithUTF8String:(self.english ? kTabs[i].en : kTabs[i].vi)];
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
    self.activeCountBadge.text = [NSString stringWithFormat:@"%ld %@", (long)total,
                                  [self L:@"BẬT" en:@"ON"]];
}

- (void)buildActiveTabCards {
    @try {
        for (UIView *sub in [self.scrollView.subviews copy]) {
            [sub removeFromSuperview];
        }
        [self.cardMap removeAllObjects];
        [self.titleMarqueeMap removeAllObjects];
        [self.subMarqueeMap removeAllObjects];
        [self.toggleBtnMap removeAllObjects];
        [self.forgeModeBtnMap removeAllObjects];
        [self.stepValMap removeAllObjects];
        [self.pillGroupMap removeAllObjects];
        self.resetAllButton = nil;

        CGFloat W = self.scrollView.bounds.size.width;
        if (W < 120.0) return;

        const char *cid = kTabs[self.selectedTab].cid;
        CGFloat pad = 7.0;
        CGFloat gap = 6.0;
        BOOL twoCol = (W >= 420.0);
        CGFloat colW = twoCol ? floor((W - pad * 2.0 - gap) * 0.5) : (W - pad * 2.0);
        CGFloat colY[2] = { pad, pad };

        for (size_t i = 0; i < kFTC_FeatureCount; i++) {
            const FTC_Feature *f = &kFTC_Features[i];
            if (strcmp(f->category, cid) != 0) continue;

            // #4 (2-mode Forge Win) and wide controls span full width when in 2-col if cramped
            BOOL forceFull = (twoCol &&
                              (f->fid == 4 || f->kind == FTC_KIND_STEP || f->kind == FTC_KIND_MODE ||
                               (colW < 245.0 && (f->fid == 7 || f->fid == 24))));
            CGFloat cardW = forceFull ? (W - pad * 2.0) : colW;
            CGFloat cardH = (f->fid == 12) ? 70.0 : 54.0;

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
        if (strcmp(cid, "setting") == 0) {
            UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeCustom];
            resetBtn.frame = CGRectMake(pad, totalH + 2.0, W - pad * 2.0, 32.0);
            [resetBtn setTitle:[self L:@"Tắt hết cheat & Xóa cấu hình đã lưu"
                                    en:@"Disable All Cheats & Clear Saved Config"]
                      forState:UIControlStateNormal];
            resetBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11.5];
            [resetBtn setTitleColor:FTC_Color(FTC_C_CRIMSON_HI) forState:UIControlStateNormal];
            resetBtn.backgroundColor = FTC_Color(FTC_C_TAB_ON);
            resetBtn.opaque = YES;
            resetBtn.layer.cornerRadius = 9.0;
            resetBtn.layer.borderColor = FTC_Color(FTC_C_CRIMSON).CGColor;
            resetBtn.layer.borderWidth = 1.0;
            [resetBtn addTarget:self action:@selector(onResetAllCheats) forControlEvents:UIControlEventTouchUpInside];
            [self.scrollView addSubview:resetBtn];
            self.resetAllButton = resetBtn;
            totalH += 40.0;
        }

        self.scrollView.contentSize = CGSizeMake(W, MAX(totalH + 4.0, self.scrollView.bounds.size.height));
    } @catch (...) {}
}

- (UIView *)makeCardForFeature:(const FTC_Feature *)f frame:(CGRect)frame {
    CGFloat W = frame.size.width;
    CGFloat H = frame.size.height;
    BOOL on = [self.switchOn[@(f->fid)] boolValue];
    BOOL isPurple = (f->fid == 4 && self.forgeGreatMode);

    UIView *card = [[UIView alloc] initWithFrame:frame];
    card.opaque = YES;
    card.backgroundColor = (on && isPurple) ? FTC_Color(FTC_C_CARD_PURP)
                         : on               ? FTC_Color(FTC_C_CARD_ON)
                                            : FTC_Color(FTC_C_CARD);
    card.layer.borderColor = (on && isPurple) ? FTC_Color(FTC_C_PURPLE).CGColor
                           : on               ? FTC_Color(FTC_C_CRIMSON).CGColor
                           : isPurple         ? FTC_Color(FTC_C_PURPLE).CGColor
                                              : FTC_Color(FTC_C_BORDER).CGColor;
    card.layer.borderWidth = 1.0;
    card.layer.cornerRadius = 10.0;
    self.cardMap[@(f->fid)] = card;

    // Calculate right-side control width cleanly
    BOOL hasSecondary = (f->fid == 7 || f->fid == 24);
    CGFloat ctrlAreaW = 62.0;
    if (f->fid == 4) ctrlAreaW = 196.0;
    else if (f->kind == FTC_KIND_STEP) ctrlAreaW = 180.0;
    else if (f->kind == FTC_KIND_MODE) ctrlAreaW = (f->fid == 42) ? 168.0 : 152.0;
    else if (hasSecondary) ctrlAreaW = 136.0;

    CGFloat textW = MAX(56.0, W - ctrlAreaW - 18.0);

    // Title marquee (tap region behind it toggles full description vs status)
    FTCMarqueeLabel *titleM = [[FTCMarqueeLabel alloc] initWithFrame:CGRectMake(9, 7, textW, 18)];
    NSString *titleStr = [NSString stringWithUTF8String:(self.english ? f->name_en : f->name_vi)];
    [titleM configureText:titleStr font:[UIFont boldSystemFontOfSize:12.5] color:FTC_Color(FTC_C_TEXT)];
    [card addSubview:titleM];
    self.titleMarqueeMap[@(f->fid)] = titleM;

    // Subtitle / status marquee (dual-edge fade glide when long!)
    FTCMarqueeLabel *subM = [[FTCMarqueeLabel alloc] initWithFrame:CGRectMake(9, 28, textW, 18)];
    [card addSubview:subM];
    self.subMarqueeMap[@(f->fid)] = subM;
    [self refreshCardSubtitle:f];

    // Transparent tap overlay over text area to toggle desc/status
    UIButton *textTap = [UIButton buttonWithType:UIButtonTypeCustom];
    textTap.frame = CGRectMake(4, 2, textW + 8, H - 4);
    textTap.backgroundColor = [UIColor clearColor];
    textTap.tag = f->fid;
    [textTap addTarget:self action:@selector(onToggleDesc:) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:textTap];

    // ---- Lightweight Flat Opaque Controls ----
    if (f->fid == 4) {
        // #4: 2-Mode Forge Always Win: [Thành công / Đại thành công (Tím)] + [BẬT/TẮT]
        UIButton *toggleBtn = [self makeFlatToggleButton:4
                                                   frame:CGRectMake(W - 58.0, floor((H - 28.0) * 0.5), 50.0, 28.0)
                                                      on:on purple:isPurple];
        [card addSubview:toggleBtn];
        self.toggleBtnMap[@(4)] = toggleBtn;

        UIButton *modeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        modeBtn.frame = CGRectMake(W - 58.0 - 134.0, floor((H - 28.0) * 0.5), 128.0, 28.0);
        modeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        modeBtn.opaque = YES;
        modeBtn.layer.cornerRadius = 7.0;
        modeBtn.layer.borderWidth = 1.0;
        [modeBtn addTarget:self action:@selector(onToggleForgeMode) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:modeBtn];
        self.forgeModeBtnMap[@(4)] = modeBtn;
        [self styleForgeModeButton:modeBtn];
    } else if (f->kind == FTC_KIND_PATCH || f->kind == FTC_KIND_DEV_TOGGLE) {
        UIButton *toggleBtn = [self makeFlatToggleButton:f->fid
                                                   frame:CGRectMake(W - 58.0, floor((H - 28.0) * 0.5), 50.0, 28.0)
                                                      on:on purple:NO];
        [card addSubview:toggleBtn];
        self.toggleBtnMap[@(f->fid)] = toggleBtn;

        if (hasSecondary) {
            UIButton *ex = [self makeSecondaryButtonForFeature:f
                                                         frame:CGRectMake(W - 58.0 - 74.0, floor((H - 28.0) * 0.5), 68.0, 28.0)];
            [card addSubview:ex];
        }
    } else if (f->kind == FTC_KIND_ONESHOT) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(W - 60.0, floor((H - 28.0) * 0.5), 52.0, 28.0);
        [b setTitle:[self L:@"Chạy" en:@"Run"] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:11.5];
        [b setTitleColor:FTC_Color(FTC_C_TEXT) forState:UIControlStateNormal];
        b.backgroundColor = FTC_Color(FTC_C_CRIMSON);
        b.opaque = YES;
        b.layer.cornerRadius = 7.0;
        b.tag = f->fid;
        [b addTarget:self action:@selector(onOneshot:) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:b];

        if (hasSecondary) {
            UIButton *ex = [self makeSecondaryButtonForFeature:f
                                                         frame:CGRectMake(W - 60.0 - 76.0, floor((H - 28.0) * 0.5), 70.0, 28.0)];
            [card addSubview:ex];
        }
    } else if (f->kind == FTC_KIND_MODE) {
        NSArray<NSString *> *items = nil;
        CGFloat totalW = 146.0;
        NSInteger selIdx = [self.modeIndex[@(f->fid)] integerValue];
        if (f->fid == 28) {
            items = @[ [self L:@"-1 ngày" en:@"-1 Day"], [self L:@"+1 ngày" en:@"+1 Day"] ];
            selIdx = -1; // momentary
        } else if (f->fid == 32) {
            items = @[ [self L:@"Thấp" en:@"Low"], [self L:@"Vừa" en:@"Mid"], [self L:@"Cao" en:@"High"] ];
        } else if (f->fid == 42) {
            items = @[ @"1x", @"1.5x", @"2x", @"3x" ];
            totalW = 162.0;
        } else if (f->fid == 43) {
            items = @[ @"Tiếng Việt", @"English" ];
            selIdx = self.english ? 1 : 0;
        } else {
            items = @[ @"--" ];
        }
        [self addFlatPillGroupToCard:card fid:f->fid items:items selectedIndex:selIdx
                               frame:CGRectMake(W - totalW - 8.0, floor((H - 28.0) * 0.5), totalW, 28.0)];
    } else if (f->kind == FTC_KIND_STEP) {
        if (f->fid == 12) {
            NSArray<NSString *> *tItems = @[
                [self L:@"Hỏng" en:@"Dmg"],
                [self L:@"Giữ" en:@"Hold"],
                [self L:@"TC" en:@"Succ"],
                [self L:@"ĐTC" en:@"Great"]
            ];
            NSInteger sel = [self.modeIndex[@(12)] integerValue];
            [self addFlatPillGroupToCard:card fid:12 items:tItems selectedIndex:sel
                                   frame:CGRectMake(W - 176.0, 6.0, 168.0, 26.0)];

            UIButton *plus = [UIButton buttonWithType:UIButtonTypeCustom];
            plus.frame = CGRectMake(W - 84.0, 38.0, 76.0, 25.0);
            [plus setTitle:[self L:@"+1 vé" en:@"+1 Ticket"] forState:UIControlStateNormal];
            plus.titleLabel.font = [UIFont boldSystemFontOfSize:11];
            [plus setTitleColor:FTC_Color(FTC_C_TEXT) forState:UIControlStateNormal];
            plus.backgroundColor = FTC_Color(FTC_C_CRIMSON);
            plus.opaque = YES;
            plus.layer.cornerRadius = 7.0;
            plus.tag = 12;
            [plus addTarget:self action:@selector(onTicketPlus:) forControlEvents:UIControlEventTouchUpInside];
            [card addSubview:plus];
        } else {
            // Lightweight flat stepper: [ - ] [ val ] [ + ] [ Đặt / Nhảy ]
            CGFloat sx = W - 176.0;
            CGFloat sy = floor((H - 28.0) * 0.5);
            NSInteger v = [self.stepValue[@(f->fid)] integerValue];

            UIButton *minus = [self makeFlatMiniBtn:@"−" frame:CGRectMake(sx, sy, 32, 28)
                                                tag:(f->fid * 10 + 0) action:@selector(onStepDelta:)];
            [card addSubview:minus];

            UILabel *val = [[UILabel alloc] initWithFrame:CGRectMake(sx + 34, sy, 42, 28)];
            val.text = [NSString stringWithFormat:@"%ld", (long)v];
            val.font = [UIFont monospacedDigitSystemFontOfSize:12.5 weight:UIFontWeightBold];
            val.textColor = FTC_Color(FTC_C_GOLD);
            val.backgroundColor = FTC_Color(FTC_C_PANEL);
            val.opaque = YES;
            val.textAlignment = NSTextAlignmentCenter;
            val.layer.cornerRadius = 6.0;
            val.layer.masksToBounds = YES;
            [card addSubview:val];
            self.stepValMap[@(f->fid)] = val;

            UIButton *plus = [self makeFlatMiniBtn:@"+" frame:CGRectMake(sx + 78, sy, 32, 28)
                                               tag:(f->fid * 10 + 1) action:@selector(onStepDelta:)];
            [card addSubview:plus];

            UIButton *apply = [UIButton buttonWithType:UIButtonTypeCustom];
            apply.frame = CGRectMake(sx + 114, sy, 54, 28);
            [apply setTitle:(f->fid == 9) ? [self L:@"Nhảy" en:@"Jump"] : [self L:@"Đặt" en:@"Set"]
                   forState:UIControlStateNormal];
            apply.titleLabel.font = [UIFont boldSystemFontOfSize:11.5];
            [apply setTitleColor:FTC_Color(FTC_C_TEXT) forState:UIControlStateNormal];
            apply.backgroundColor = FTC_Color(FTC_C_CRIMSON);
            apply.opaque = YES;
            apply.layer.cornerRadius = 7.0;
            apply.tag = f->fid;
            [apply addTarget:self action:@selector(onStepApply:) forControlEvents:UIControlEventTouchUpInside];
            [card addSubview:apply];
        }
    }
    return card;
}

- (UIButton *)makeFlatToggleButton:(int)fid frame:(CGRect)frame on:(BOOL)on purple:(BOOL)purple {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = frame;
    b.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    b.opaque = YES;
    b.layer.cornerRadius = 8.0;
    b.layer.borderWidth = 1.0;
    b.tag = fid;
    [b addTarget:self action:@selector(onFlatToggle:) forControlEvents:UIControlEventTouchUpInside];
    [self styleFlatToggleButton:b on:on purple:purple];
    return b;
}

- (void)styleFlatToggleButton:(UIButton *)b on:(BOOL)on purple:(BOOL)purple {
    if (!b) return;
    [b setTitle:(on ? [self L:@"BẬT" en:@"ON"] : [self L:@"TẮT" en:@"OFF"]) forState:UIControlStateNormal];
    if (on) {
        b.backgroundColor = purple ? FTC_Color(FTC_C_PURPLE) : FTC_Color(FTC_C_CRIMSON);
        b.layer.borderColor = purple ? FTC_Color(FTC_C_PURPLE_HI).CGColor : FTC_Color(FTC_C_CRIMSON_HI).CGColor;
        [b setTitleColor:FTC_Color(FTC_C_TEXT) forState:UIControlStateNormal];
    } else {
        b.backgroundColor = FTC_Color(FTC_C_BTN_OFF);
        b.layer.borderColor = FTC_Color(FTC_C_BORDER_HI).CGColor;
        [b setTitleColor:FTC_Color(FTC_C_TEXT2) forState:UIControlStateNormal];
    }
}

- (void)styleForgeModeButton:(UIButton *)b {
    if (!b) return;
    if (self.forgeGreatMode) {
        [b setTitle:[self L:@"Đại thành công 100%" en:@"Great 100%"] forState:UIControlStateNormal];
        b.backgroundColor = FTC_Color(FTC_C_PURPLE);
        b.layer.borderColor = FTC_Color(FTC_C_PURPLE_HI).CGColor;
        [b setTitleColor:FTC_Color(FTC_C_TEXT) forState:UIControlStateNormal];
    } else {
        [b setTitle:[self L:@"Thành công 100%" en:@"Success 100%"] forState:UIControlStateNormal];
        b.backgroundColor = FTC_Color(FTC_C_BTN_BG);
        b.layer.borderColor = FTC_Color(FTC_C_GOLD).CGColor;
        [b setTitleColor:FTC_Color(FTC_C_GOLD) forState:UIControlStateNormal];
    }
}

- (UIButton *)makeFlatMiniBtn:(NSString *)title frame:(CGRect)frame tag:(NSInteger)tag action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = frame;
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [b setTitleColor:FTC_Color(FTC_C_TEXT) forState:UIControlStateNormal];
    b.backgroundColor = FTC_Color(FTC_C_BTN_BG);
    b.opaque = YES;
    b.layer.cornerRadius = 7.0;
    b.layer.borderColor = FTC_Color(FTC_C_BORDER_HI).CGColor;
    b.layer.borderWidth = 1.0;
    b.tag = tag;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)addFlatPillGroupToCard:(UIView *)card fid:(int)fid items:(NSArray<NSString *> *)items
                 selectedIndex:(NSInteger)selIdx frame:(CGRect)frame {
    NSInteger n = (NSInteger)items.count;
    if (n <= 0) return;
    CGFloat gap = 3.0;
    CGFloat btnW = floor((frame.size.width - gap * (n - 1)) / (CGFloat)n);
    NSMutableArray<UIButton *> *arr = [NSMutableArray arrayWithCapacity:n];
    for (NSInteger i = 0; i < n; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(frame.origin.x + i * (btnW + gap), frame.origin.y, btnW, frame.size.height);
        [b setTitle:items[i] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:(n >= 4 ? 10.0 : 10.5)];
        b.titleLabel.adjustsFontSizeToFitWidth = YES;
        b.titleLabel.minimumScaleFactor = 0.75;
        b.opaque = YES;
        b.layer.cornerRadius = 6.0;
        b.layer.borderWidth = 1.0;
        b.tag = fid * 10 + i;
        BOOL sel = (i == selIdx);
        b.backgroundColor = sel ? FTC_Color(FTC_C_CRIMSON) : FTC_Color(FTC_C_BTN_OFF);
        b.layer.borderColor = sel ? FTC_Color(FTC_C_CRIMSON_HI).CGColor : FTC_Color(FTC_C_BORDER_HI).CGColor;
        [b setTitleColor:(sel ? FTC_Color(FTC_C_TEXT) : FTC_Color(FTC_C_TEXT2)) forState:UIControlStateNormal];
        [b addTarget:self action:@selector(onFlatPillTap:) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:b];
        [arr addObject:b];
    }
    self.pillGroupMap[@(fid)] = arr;
}

- (void)updatePillGroup:(int)fid selectedIndex:(NSInteger)selIdx {
    NSArray<UIButton *> *arr = self.pillGroupMap[@(fid)];
    for (NSInteger i = 0; i < (NSInteger)arr.count; i++) {
        UIButton *b = arr[i];
        BOOL sel = (i == selIdx);
        b.backgroundColor = sel ? FTC_Color(FTC_C_CRIMSON) : FTC_Color(FTC_C_BTN_OFF);
        b.layer.borderColor = sel ? FTC_Color(FTC_C_CRIMSON_HI).CGColor : FTC_Color(FTC_C_BORDER_HI).CGColor;
        [b setTitleColor:(sel ? FTC_Color(FTC_C_TEXT) : FTC_Color(FTC_C_TEXT2)) forState:UIControlStateNormal];
    }
}

- (UIButton *)makeSecondaryButtonForFeature:(const FTC_Feature *)f frame:(CGRect)frame {
    UIButton *ex = [UIButton buttonWithType:UIButtonTypeCustom];
    ex.frame = frame;
    NSString *t = (f->fid == 7) ? [self L:@"Giết ngay" en:@"Kill Now"]
                                : [self L:@"Chọn kiếm" en:@"Pick Sword"];
    [ex setTitle:t forState:UIControlStateNormal];
    ex.titleLabel.font = [UIFont boldSystemFontOfSize:10.5];
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

// Fast O(1) in-place refresh (ZERO view tear-down!)
- (void)refreshCardSubtitle:(const FTC_Feature *)f {
    if (!f) return;
    FTCMarqueeLabel *sub = self.subMarqueeMap[@(f->fid)];
    if (!sub) return;
    NSString *status = self.statusText[@(f->fid)];
    BOOL showDesc = [self.descOpen[@(f->fid)] boolValue];
    NSInteger kind = [self.statusKind[@(f->fid)] integerValue];
    UIFont *font = [UIFont systemFontOfSize:10.5];
    if (showDesc || status.length == 0) {
        NSString *desc = [NSString stringWithUTF8String:(self.english ? f->desc_en : f->desc_vi)];
        [sub configureText:desc font:font color:FTC_Color(FTC_C_TEXT2)];
    } else {
        UIColor *col = (kind == 3) ? FTC_Color(FTC_C_PURPLE_HI)
                     : (kind == 1) ? FTC_Color(FTC_C_OK)
                     : (kind == 2) ? FTC_Color(FTC_C_ERR)
                                   : FTC_Color(FTC_C_TEXT2);
        [sub configureText:status font:font color:col];
    }
}

- (void)updateCardInPlace:(int)fid {
    const FTC_Feature *f = FTC_FeatureById(fid);
    if (!f) return;
    BOOL on = [self.switchOn[@(fid)] boolValue];
    BOOL isPurple = (fid == 4 && self.forgeGreatMode);
    UIView *card = self.cardMap[@(fid)];
    if (card) {
        card.backgroundColor = (on && isPurple) ? FTC_Color(FTC_C_CARD_PURP)
                             : on               ? FTC_Color(FTC_C_CARD_ON)
                                                : FTC_Color(FTC_C_CARD);
        card.layer.borderColor = (on && isPurple) ? FTC_Color(FTC_C_PURPLE).CGColor
                               : on               ? FTC_Color(FTC_C_CRIMSON).CGColor
                               : isPurple         ? FTC_Color(FTC_C_PURPLE).CGColor
                                                  : FTC_Color(FTC_C_BORDER).CGColor;
    }
    [self styleFlatToggleButton:self.toggleBtnMap[@(fid)] on:on purple:isPurple];
    if (fid == 4) {
        [self styleForgeModeButton:self.forgeModeBtnMap[@(4)]];
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
    return [NSString stringWithUTF8String:FTC_CallResultMessageLang(r, self.english)];
}

- (NSString *)messageForPatch:(FTC_PatchResult)r {
    return [NSString stringWithUTF8String:FTC_PatchResultMessageLang(r, self.english)];
}

- (UIViewController *)topViewController {
    UIViewController *vc = self.window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

#pragma mark - #4 Great Success Keep-Alive (only runs while #4 Great mode is ON)

- (void)syncGreatForgeTimer {
    BOOL need = ([self.switchOn[@(4)] boolValue] && self.forgeGreatMode);
    if (need && !self.greatForgeTimer) {
        self.greatForgeTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                               repeats:YES
                                                                 block:^(NSTimer *t) {
            FTC_KeepGreatForgeAlive();
        }];
    } else if (!need && self.greatForgeTimer) {
        [self.greatForgeTimer invalidate];
        self.greatForgeTimer = nil;
    }
}

#pragma mark - Persistence & Staggered Non-Blocking Startup Restore

- (void)loadSavedPreferences {
    @try {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        self.maximized = [ud boolForKey:kPrefMaximized];
        self.english = [ud boolForKey:kPrefLangEn];
        self.forgeGreatMode = [ud boolForKey:kPrefForgeGreat];
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
        self.modeIndex[@(43)] = @(self.english ? 1 : 0);
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

        // 1. FPS badge (instant)
        if ([saved[@"40"] boolValue]) {
            self.switchOn[@(40)] = @(YES);
            [self setStatus:40 text:[self L:@"Đã bật (góc trên trái)" en:@"Enabled (top-left)"] kind:1];
            [self setFpsBadgeVisible:YES];
        }

        // 2. Boost Max FPS (#41) or Quality (#32)
        if ([saved[@"41"] boolValue]) {
            [queue addObject:^{
                CheatMenuView *s = weakSelf;
                if (!s) return;
                if (FTC_SetAntiLag(true) == FTC_CALL_OK) {
                    s.switchOn[@(41)] = @(YES);
                    [s setStatus:41 text:[s L:@"Đã khôi phục" en:@"Restored"] kind:1];
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
                        [s setStatus:32 text:[s L:@"Đã khôi phục" en:@"Restored"] kind:1];
                        [s updateCardInPlace:32];
                    }
                }];
            }
        }

        // 3. Speed Hack (#42)
        if ([ud objectForKey:kPrefSpeed]) {
            NSInteger spIdx = [ud integerForKey:kPrefSpeed];
            if (spIdx > 0 && spIdx <= 3) {
                [queue addObject:^{
                    CheatMenuView *s = weakSelf;
                    if (!s) return;
                    if (FTC_SetTimeScale(kSpeedValues[spIdx]) == FTC_CALL_OK) {
                        s.modeIndex[@(42)] = @(spIdx);
                        [s setStatus:42 text:[NSString stringWithFormat:@"%.1fx", kSpeedValues[spIdx]] kind:1];
                        [s updateCardInPlace:42];
                    }
                }];
            }
        }

        // 4. #4 Forge Always Win (100% IL2CPP — no JIT needed!)
        if ([saved[@"4"] boolValue]) {
            [queue addObject:^{
                CheatMenuView *s = weakSelf;
                if (!s) return;
                int mode = s.forgeGreatMode ? 2 : 1;
                if (FTC_SetForgeWinMode(mode) == FTC_CALL_OK) {
                    s.switchOn[@(4)] = @(YES);
                    [s setStatus:4
                            text:(mode == 2 ? [s L:@"Đại thành công 100%" en:@"Great Success 100%"]
                                            : [s L:@"Thành công 100%" en:@"Success 100%"])
                            kind:(mode == 2 ? 3 : 1)];
                    [s syncGreatForgeTimer];
                    [s updateCardInPlace:4];
                }
            }];
        }

        // 5. #7 Dragon God Mode (deterministic IL2CPP)
        if ([saved[@"7"] boolValue]) {
            [queue addObject:^{
                CheatMenuView *s = weakSelf;
                if (!s) return;
                if (FTC_SetDragonGodMode(true) == FTC_CALL_OK) {
                    s.switchOn[@(7)] = @(YES);
                    [s setStatus:7 text:[s L:@"Đã khôi phục" en:@"Restored"] kind:1];
                    [s updateCardInPlace:7];
                }
            }];
        }

        // 6. Runtime PATCH switches (staggered 80ms apart, csops-protected so NEVER crashes!)
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
                        [s setStatus:fid text:[s L:@"Đã khôi phục" en:@"Restored"] kind:1];
                    } else if (fid == 19 && FTC_SetDragonGodMode(true) == FTC_CALL_OK) {
                        s.switchOn[@(19)] = @(YES);
                        [s setStatus:19 text:[s L:@"Đã bật (chế độ không cần JIT)" en:@"Enabled (No-JIT mode)"] kind:1];
                    } else {
                        s.switchOn[@(fid)] = @(NO);
                        [s setStatus:fid text:[s messageForPatch:r] kind:2];
                    }
                    [s updateCardInPlace:fid];
                }];
            } else if (f->fid == 33) {
                [self.pendingDevToggleFids addObject:@(33)];
            }
        }

        for (NSUInteger idx = 0; idx < queue.count; idx++) {
            dispatch_block_t task = queue[idx];
            int64_t delayNs = (int64_t)(idx * 80 * NSEC_PER_MSEC);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delayNs),
                           dispatch_get_main_queue(), task);
        }

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
                if (fid == 33 && FTC_ToggleMerchantShelfSlot() == FTC_CALL_OK) {
                    self.switchOn[@(33)] = @(YES);
                    [self setStatus:33 text:[self L:@"Đã khôi phục" en:@"Restored"] kind:1];
                    [self updateCardInPlace:33];
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
            self.switchOn[@(f->fid)] = @(NO);
            [self setStatus:f->fid text:nil kind:0];
        }
        FTC_SetForgeWinMode(0);
        FTC_SetDragonGodMode(false);
        FTC_SetAntiLag(false);
        FTC_SetTimeScale(1.0f);
        [self syncGreatForgeTimer];
        [self setFpsBadgeVisible:NO];
        self.modeIndex[@(42)] = @(0);
        self.forgeGreatMode = NO;

        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud removeObjectForKey:kPrefSwitches];
        [ud removeObjectForKey:kPrefForgeGreat];
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

// #4: Switch between Mode 1 (Thành công 100%) and Mode 2 (Đại thành công 100% — tím)
- (void)onToggleForgeMode {
    @try {
        self.forgeGreatMode = !self.forgeGreatMode;
        [[NSUserDefaults standardUserDefaults] setBool:self.forgeGreatMode forKey:kPrefForgeGreat];
        BOOL isOn = [self.switchOn[@(4)] boolValue];
        if (isOn) {
            int mode = self.forgeGreatMode ? 2 : 1;
            FTC_CallResult cr = FTC_SetForgeWinMode(mode);
            if (cr == FTC_CALL_OK) {
                [self setStatus:4
                           text:(mode == 2 ? [self L:@"Đại thành công 100%" en:@"Great Success 100%"]
                                           : [self L:@"Thành công 100%" en:@"Success 100%"])
                           kind:(mode == 2 ? 3 : 1)];
            } else {
                [self setStatus:4 text:[self messageForCall:cr] kind:2];
            }
        } else {
            [self setStatus:4
                       text:(self.forgeGreatMode ? [self L:@"Chế độ: Đại thành công 100% (chưa bật)" en:@"Mode: Great 100% (OFF)"]
                                                 : [self L:@"Chế độ: Thành công 100% (chưa bật)" en:@"Mode: Success 100% (OFF)"])
                       kind:(self.forgeGreatMode ? 3 : 0)];
        }
        [self syncGreatForgeTimer];
        [self updateCardInPlace:4];
    } @catch (...) {}
}

- (void)onFlatToggle:(UIButton *)sender {
    @try {
        int fid = (int)sender.tag;
        BOOL wantOn = ![self.switchOn[@(fid)] boolValue];
        const FTC_Feature *f = FTC_FeatureById(fid);
        if (!f) return;

        // #4: 2-Mode Forge Always Win (100% IL2CPP — no JIT required)
        if (fid == 4) {
            int mode = wantOn ? (self.forgeGreatMode ? 2 : 1) : 0;
            FTC_CallResult cr = FTC_SetForgeWinMode(mode);
            if (cr == FTC_CALL_OK) {
                self.switchOn[@(4)] = @(wantOn);
                [self saveSwitchState:4 on:wantOn];
                if (wantOn) {
                    [self setStatus:4
                               text:(mode == 2 ? [self L:@"Đại thành công 100%" en:@"Great Success 100%"]
                                               : [self L:@"Thành công 100%" en:@"Success 100%"])
                               kind:(mode == 2 ? 3 : 1)];
                } else {
                    [self setStatus:4 text:[self L:@"Đã tắt (tỉ lệ gốc)" en:@"Disabled (normal odds)"] kind:0];
                }
                [self syncGreatForgeTimer];
            } else {
                [self setStatus:4 text:[self messageForCall:cr] kind:2];
            }
            [self updateCardInPlace:4];
            return;
        }

        // #40: Top-left FPS badge
        if (fid == 40) {
            self.switchOn[@(40)] = @(wantOn);
            [self saveSwitchState:40 on:wantOn];
            [self setStatus:40
                       text:(wantOn ? [self L:@"Đã bật (góc trên trái)" en:@"Enabled (top-left)"]
                                    : [self L:@"Đã tắt" en:@"Disabled"])
                       kind:(wantOn ? 1 : 0)];
            [self setFpsBadgeVisible:wantOn];
            [self updateCardInPlace:40];
            return;
        }

        // #7: Dragon God Mode (deterministic IL2CPP — no JIT needed)
        if (fid == 7) {
            FTC_CallResult cr = FTC_SetDragonGodMode(wantOn);
            if (cr == FTC_CALL_OK) {
                self.switchOn[@(7)] = @(wantOn);
                [self saveSwitchState:7 on:wantOn];
                [self setStatus:7 text:(wantOn ? [self L:@"Đã bật" en:@"Enabled"] : [self L:@"Đã tắt" en:@"Disabled"]) kind:(wantOn ? 1 : 0)];
            } else {
                [self setStatus:7 text:[self messageForCall:cr] kind:2];
            }
            [self updateCardInPlace:7];
            return;
        }

        // #33 & #41
        if (fid == 33 || fid == 41) {
            FTC_CallResult cr = (fid == 33) ? FTC_ToggleMerchantShelfSlot() : FTC_SetAntiLag(wantOn);
            if (cr == FTC_CALL_OK) {
                self.switchOn[@(fid)] = @(wantOn);
                [self saveSwitchState:fid on:wantOn];
                [self setStatus:fid text:(wantOn ? [self L:@"Đã bật" en:@"Enabled"] : [self L:@"Đã tắt" en:@"Disabled"]) kind:(wantOn ? 1 : 0)];
            } else {
                [self setStatus:fid text:[self messageForCall:cr] kind:2];
            }
            [self updateCardInPlace:fid];
            return;
        }

        // #10 Fever: always fills Fever bar via IL2CPP even when JIT is off!
        if (fid == 10 && wantOn) {
            FTC_CallResult fcr = FTC_FillFever();
            FTC_PatchResult pr = FTC_PatchApplyFeature(10);
            if (pr == FTC_PATCH_OK) {
                self.switchOn[@(10)] = @(YES);
                [self saveSwitchState:10 on:YES];
                [self setStatus:10 text:[self L:@"Đã bật & nạp đầy Fever" en:@"Enabled & Fever Filled"] kind:1];
            } else if (fcr == FTC_CALL_OK) {
                // Filled via IL2CPP without crashing; inform that infinite lock needs JIT
                self.switchOn[@(10)] = @(NO);
                [self setStatus:10 text:[self L:@"Đã nạp đầy Fever (khóa vô hạn cần JIT)" en:@"Fever filled (infinite lock needs JIT)"] kind:1];
            } else {
                [self setStatus:10 text:[self messageForPatch:pr] kind:2];
            }
            [self updateCardInPlace:10];
            return;
        }

        // #19 Dragon Invulnerable: tries patch first, falls back to IL2CPP GodMode if no JIT!
        if (fid == 19) {
            FTC_PatchResult pr = wantOn ? FTC_PatchApplyFeature(19) : FTC_PatchRemoveFeature(19);
            if (pr == FTC_PATCH_OK) {
                self.switchOn[@(19)] = @(wantOn);
                [self saveSwitchState:19 on:wantOn];
                [self setStatus:19 text:(wantOn ? [self L:@"Đã bật" en:@"Enabled"] : [self L:@"Đã tắt" en:@"Disabled"]) kind:(wantOn ? 1 : 0)];
            } else if (pr == FTC_PATCH_ERR_NO_JIT && FTC_SetDragonGodMode(wantOn) == FTC_CALL_OK) {
                self.switchOn[@(19)] = @(wantOn);
                [self saveSwitchState:19 on:wantOn];
                [self setStatus:19
                           text:(wantOn ? [self L:@"Đã bật (không cần JIT)" en:@"Enabled (No-JIT)"]
                                        : [self L:@"Đã tắt" en:@"Disabled"])
                           kind:(wantOn ? 1 : 0)];
            } else {
                [self setStatus:19 text:[self messageForPatch:pr] kind:2];
            }
            [self updateCardInPlace:19];
            return;
        }

        // Standard runtime __TEXT patches (protected by csops CS_DEBUGGED check -> NEVER crashes)
        if (f->kind == FTC_KIND_PATCH) {
            FTC_PatchResult r = wantOn ? FTC_PatchApplyFeature(fid) : FTC_PatchRemoveFeature(fid);
            if (r == FTC_PATCH_OK) {
                self.switchOn[@(fid)] = @(wantOn);
                [self saveSwitchState:fid on:wantOn];
                [self setStatus:fid text:(wantOn ? [self L:@"Đã bật" en:@"Enabled"] : [self L:@"Đã tắt" en:@"Disabled"]) kind:(wantOn ? 1 : 0)];
            } else {
                [self setStatus:fid text:[self messageForPatch:r] kind:2];
            }
            [self updateCardInPlace:fid];
        }
    } @catch (...) {}
}

- (void)onOneshot:(UIButton *)sender {
    @try {
        int fid = (int)sender.tag;
        if (fid == 27) {
            UIViewController *root = [self topViewController];
            if (!root) {
                [self setStatus:27 text:[self L:@"Không mở được hộp thoại xác nhận" en:@"Cannot present alert"] kind:2];
                [self updateCardInPlace:27];
                return;
            }
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:[self L:@"Chơi lại từ đầu?" en:@"Reset Run?"]
                                 message:[self L:@"Lượt chơi hiện tại sẽ bị xóa về ngày 1." en:@"Current run progress will be lost."]
                          preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:[self L:@"Hủy" en:@"Cancel"]
                                                      style:UIAlertActionStyleCancel handler:nil]];
            __weak typeof(self) weakSelf = self;
            [alert addAction:[UIAlertAction actionWithTitle:[self L:@"Đặt lại" en:@"Reset"]
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
                   text:(cr == FTC_CALL_OK) ? [self L:@"Đã chạy thành công" en:@"Executed"] : [self messageForCall:cr]
                   kind:(cr == FTC_CALL_OK) ? 1 : 2];
        [self updateCardInPlace:fid];
    } @catch (...) {}
}

- (void)onSecondary:(UIButton *)sender {
    @try {
        int fid = (int)sender.tag;
        FTC_CallResult cr = FTC_CALL_ERR_UNAVAILABLE;
        if (fid == 7) cr = FTC_KillDragon();
        else if (fid == 24) cr = FTC_OpenSwordPicker();
        [self setStatus:fid
                   text:(cr == FTC_CALL_OK) ? [self L:@"Đã chạy thành công" en:@"Executed"] : [self messageForCall:cr]
                   kind:(cr == FTC_CALL_OK) ? 1 : 2];
        [self updateCardInPlace:fid];
    } @catch (...) {}
}

- (void)onFlatPillTap:(UIButton *)sender {
    @try {
        int fid = (int)(sender.tag / 10);
        NSInteger idx = sender.tag % 10;

        // #43: Language switcher (Tiếng Việt / English) — translates ENTIRE UI immediately!
        if (fid == 43) {
            BOOL wantEn = (idx == 1);
            if (wantEn == self.english) return;
            self.english = wantEn;
            self.modeIndex[@(43)] = @(idx);
            [[NSUserDefaults standardUserDefaults] setBool:wantEn forKey:kPrefLangEn];
            // Clear stale localized status strings so descriptions/new language appear cleanly
            [self.statusText removeAllObjects];
            [self.statusKind removeAllObjects];
            [self updateActiveCountBadge];
            [self updateTabAppearance];
            [self buildActiveTabCards];
            return;
        }

        // #12: Ticket type picker
        if (fid == 12) {
            self.modeIndex[@(12)] = @(idx);
            [self updatePillGroup:12 selectedIndex:idx];
            return;
        }

        // #28: Quick step day (-1 / +1)
        if (fid == 28) {
            FTC_CallResult cr = (idx == 0) ? FTC_SkipDay() : FTC_NextDay();
            [self setStatus:28
                       text:(cr == FTC_CALL_OK)
                            ? (idx == 0 ? [self L:@"Đã lùi 1 ngày" en:@"Stepped -1 day"]
                                        : [self L:@"Đã tiến 1 ngày" en:@"Stepped +1 day"])
                            : [self messageForCall:cr]
                       kind:(cr == FTC_CALL_OK) ? 1 : 2];
            [self updateCardInPlace:28];
            return;
        }

        // #32: Graphics quality tier
        if (fid == 32) {
            FTC_CallResult cr = FTC_SetQualityTier((int)idx);
            if (cr == FTC_CALL_OK) {
                self.modeIndex[@(32)] = @(idx);
                [[NSUserDefaults standardUserDefaults] setInteger:idx forKey:kPrefQuality];
                [self updatePillGroup:32 selectedIndex:idx];
                [self setStatus:32 text:[self L:@"Đã đổi mức đồ họa" en:@"Quality updated"] kind:1];
            } else {
                [self setStatus:32 text:[self messageForCall:cr] kind:2];
            }
            [self updateCardInPlace:32];
            return;
        }

        // #42: Speed Hack (1x / 1.5x / 2x / 3x)
        if (fid == 42) {
            if (idx < 0 || idx > 3) idx = 0;
            FTC_CallResult cr = FTC_SetTimeScale(kSpeedValues[idx]);
            if (cr == FTC_CALL_OK) {
                self.modeIndex[@(42)] = @(idx);
                [[NSUserDefaults standardUserDefaults] setInteger:idx forKey:kPrefSpeed];
                [self updatePillGroup:42 selectedIndex:idx];
                [self setStatus:42
                           text:[NSString stringWithFormat:[self L:@"Tốc độ %.1fx" en:@"Speed %.1fx"], kSpeedValues[idx]]
                           kind:(idx > 0 ? 1 : 0)];
            } else {
                [self setStatus:42 text:[self messageForCall:cr] kind:2];
            }
            [self updateCardInPlace:42];
        }
    } @catch (...) {}
}

- (void)onTicketPlus:(UIButton *)sender {
    @try {
        int outcome = (int)[self.modeIndex[@(12)] integerValue] + 1;
        FTC_CallResult cr = FTC_AddRunTickets(outcome, 1);
        [self setStatus:12
                   text:(cr == FTC_CALL_OK) ? [self L:@"Đã cộng +1 vé" en:@"Added +1 ticket"] : [self messageForCall:cr]
                   kind:(cr == FTC_CALL_OK) ? 1 : 2];
        [self updateCardInPlace:12];
    } @catch (...) {}
}

- (void)onStepDelta:(UIButton *)sender {
    @try {
        int fid = (int)(sender.tag / 10);
        BOOL isPlus = ((sender.tag % 10) == 1);
        NSInteger cur = [self.stepValue[@(fid)] integerValue];
        NSInteger step = (fid == 6) ? 10 : 1;
        NSInteger minV = (fid == 9) ? 1 : 0;
        NSInteger maxV = (fid == 6) ? 999 : 24;
        NSInteger next = cur + (isPlus ? step : -step);
        if (next < minV) next = minV;
        if (next > maxV) next = maxV;
        self.stepValue[@(fid)] = @(next);
        UILabel *val = self.stepValMap[@(fid)];
        if (val) val.text = [NSString stringWithFormat:@"%ld", (long)next];
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
                   text:(cr == FTC_CALL_OK)
                        ? [NSString stringWithFormat:[self L:@"Đã áp dụng (%ld)" en:@"Applied (%ld)"], (long)v]
                        : [self messageForCall:cr]
                   kind:(cr == FTC_CALL_OK) ? 1 : 2];
        [self updateCardInPlace:fid];
    } @catch (...) {}
}

#pragma mark - Top-Left FPS Counter (Ultra-Lightweight)

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
    [self.greatForgeTimer invalidate];
    self.greatForgeTimer = nil;
}

@end
