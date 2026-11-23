// CheatMenuView.mm — ForgeTax Red-Orange-Black Fire UI (16:9 Zero-Lag + 3D Switches).
//
// Features & Guarantees:
//   - Clean Red-Orange-Black volcanic fire palette with 3-color fire-gradient
//     title (Red -> Orange -> Gold).
//   - Welcome Popup on every launch & foreground return with official vector logos
//     (Discord, GitHub, TikTok), live JIT status + colored step-by-step guide,
//     and MoMo QR Donate modal with working "Save QR to Photos" button.
//   - Strict 1-item-per-row full-width rounded cards (no 2-col orphan boxes),
//     SF Symbol icon tile on every tab & cheat row, custom 3D tactile toggle
//     switches (FTCSwitch3D), FTCScrollView instant touch-cancel scrolling,
//     and zero-offscreen dual-edge fade marquee text (FTCMarqueeLabel).
//   - #4 Forge Mode: 3 instant 100% modes (1. Hold [Green], 2. Success [Blue],
//     3. Great [Purple]) via sub-panel picker — 100% IL2CPP, 0 JIT needed.
//   - #6 Anvil Sword Grade: direct keyboard number input (0..999).
//   - #10 Infinite Fever Auto-Refill: auto-refills Fever bar immediately when
//     Fever expires — 0 lag, 0 JIT needed.
//   - #39 Sword Value: x10 / x20 / x30 / x40 selector + 3D toggle.
//   - #44 Remove Tickets: live game TicketDeck sub-panel with X button per type.
//   - JIT-locked features show red feature-specific message, gentle shake + haptic,
//     and 1.5s anti-spam lock — 0% crash risk.
#import "CheatMenuView.h"
#import "FeatureCatalog.h"
#import "PatchEngine.h"
#import "GameBridge.h"
#import "LogoImageData.h"
#import "DonateQrData.h"

#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <string.h>

// ---- Red / Orange / Black Fire Palette (100% solid opaques for 0 GPU blend lag) ----
#define FTC_C_PANEL      0x110908
#define FTC_C_HEADER     0x1A0D0A
#define FTC_C_SIDEBAR    0x150B09
#define FTC_C_TAB_ON     0x2D130D
#define FTC_C_CARD       0x1C100D
#define FTC_C_CARD_ON    0x2E140D
#define FTC_C_BTN_BG     0x2A1611
#define FTC_C_BTN_OFF    0x24130F
#define FTC_C_BORDER     0x3D1E16
#define FTC_C_BORDER_HI  0x6B2C1B
#define FTC_C_RED        0xE82820
#define FTC_C_RED_HI     0xFF473E
#define FTC_C_ORANGE     0xFF7A1A
#define FTC_C_GOLD       0xFFD166
#define FTC_C_TEXT       0xFFF3EC
#define FTC_C_TEXT2      0xBBA39A
#define FTC_C_OK         0x22C55E
#define FTC_C_BLUE       0x0EA5E9
#define FTC_C_PURPLE     0x9B30FF
#define FTC_C_PURPLE_HI  0xD4A5FF
#define FTC_C_ERR        0xFF4D4F
#define FTC_C_FPS_BG     0x120A08
#define FTC_C_FPS_TXT    0x7DFF8A
#define FTC_C_DISCORD    0x5865F2
#define FTC_C_TIKTOK_HI  0xFE2C55
#define FTC_C_MOMO       0xA50064
#define FTC_C_MOMO_HI    0xE83E8C

static UIColor *FTC_Color(uint32_t hex) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0 alpha:1.0];
}

static const CGFloat kLogoSize    = 52.0;
static const CGFloat kLogoGap     = 10.0;
static const CGFloat kMargin      = 8.0;
static const CGFloat kHeaderH     = 38.0;
static const CGFloat kSidebarW    = 118.0;
static const CGFloat kCompactMaxW = 556.0;
static const CGFloat kCompactMaxH = 330.0;

// Persistence keys
static NSString * const kPrefSwitches   = @"FTC_v4_switches";
static NSString * const kPrefForgeMode  = @"FTC_v4_forgeMode";  // 0=none, 1=Hold, 2=Success, 3=Great
static NSString * const kPrefSwordMult  = @"FTC_v4_swordMult";  // 0=x10, 1=x20, 2=x30, 3=x40
static NSString * const kPrefQuality    = @"FTC_v4_quality";
static NSString * const kPrefSpeed      = @"FTC_v4_speed";
static NSString * const kPrefLangEn     = @"FTC_v4_langEn";
static NSString * const kPrefLogoX      = @"FTC_v4_logoX";
static NSString * const kPrefLogoY      = @"FTC_v4_logoY";
static NSString * const kPrefMaximized  = @"FTC_v4_maximized";
static NSString * const kPrefTab        = @"FTC_v4_tab";

typedef struct {
    const char *cid;
    const char *sf_symbol;
    const char *vi;
    const char *en;
} FTCTab;

static const FTCTab kTabs[] = {
    {"forge",   "flame.fill",             "Rèn",         "Forge"},
    {"res",     "dollarsign.circle.fill", "Tài nguyên",  "Resources"},
    {"relic",   "sparkles",               "Di vật",      "Relics"},
    {"shop",    "bag.fill",               "Thương nhân", "Merchant"},
    {"dragon",  "bolt.shield.fill",       "Rồng",        "Dragon"},
    {"day",     "calendar",               "Ngày & Chơi", "Day & Play"},
    {"ads",     "play.slash.fill",        "Quảng cáo",   "Ads"},
    {"setting", "gearshape.fill",         "Cài đặt",     "Settings"},
};
static const NSInteger kTabCount = (NSInteger)(sizeof(kTabs) / sizeof(kTabs[0]));
static const float kSpeedValues[] = { 1.0f, 1.5f, 2.0f, 3.0f };
static const int kSwordMultValues[] = { 10, 20, 30, 40 };

#pragma mark - FTCScrollView (100% Instant Scroll Over Any Control)

@interface FTCScrollView : UIScrollView
@end

@implementation FTCScrollView
- (BOOL)touchesShouldCancelInContentView:(UIView *)view {
    return YES;
}
@end

#pragma mark - FTCSwitch3D (Tactile 3D Sliding Toggle Switch, Zero Shadow Lag)

@interface FTCSwitch3D : UIControl
@property (nonatomic, assign, getter=isOn) BOOL on;
@property (nonatomic, strong) UIColor *onTrackColor;
@property (nonatomic, strong) UIView *trackView;
@property (nonatomic, strong) UIView *innerRim;
@property (nonatomic, strong) UIView *thumbView;
@property (nonatomic, strong) CAGradientLayer *thumbGrad;
- (void)setOn:(BOOL)on animated:(BOOL)animated;
- (void)applyAccentColor:(UIColor *)color;
@end

@implementation FTCSwitch3D

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.clipsToBounds = NO;
    _onTrackColor = FTC_Color(FTC_C_ORANGE);

    CGFloat w = frame.size.width;
    CGFloat h = frame.size.height;

    _trackView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    _trackView.userInteractionEnabled = NO;
    _trackView.backgroundColor = FTC_Color(0x281714);
    _trackView.opaque = YES;
    _trackView.layer.cornerRadius = h * 0.5;
    _trackView.layer.borderWidth = 1.2;
    _trackView.layer.borderColor = FTC_Color(0x522A20).CGColor;
    [self addSubview:_trackView];

    // Subtle 3D inset bevel highlight at bottom edge of track
    _innerRim = [[UIView alloc] initWithFrame:CGRectMake(2, 2, w - 4, h - 4)];
    _innerRim.userInteractionEnabled = NO;
    _innerRim.backgroundColor = [UIColor clearColor];
    _innerRim.layer.cornerRadius = (h - 4) * 0.5;
    _innerRim.layer.borderWidth = 0.8;
    _innerRim.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12].CGColor;
    [_trackView addSubview:_innerRim];

    // Raised 3D metallic circular thumb (vertical specular gradient, 0 heavy blur)
    CGFloat d = h - 6.0;
    _thumbView = [[UIView alloc] initWithFrame:CGRectMake(3.0, 3.0, d, d)];
    _thumbView.userInteractionEnabled = NO;
    _thumbView.layer.cornerRadius = d * 0.5;
    _thumbView.layer.masksToBounds = YES;
    _thumbView.layer.borderWidth = 1.0;
    _thumbView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.75].CGColor;

    CAGradientLayer *g = [CAGradientLayer layer];
    g.frame = _thumbView.bounds;
    g.colors = @[(id)FTC_Color(0xFFFFFF).CGColor, (id)FTC_Color(0xCFC2BC).CGColor];
    g.startPoint = CGPointMake(0.5, 0.0);
    g.endPoint = CGPointMake(0.5, 1.0);
    [_thumbView.layer addSublayer:g];
    _thumbGrad = g;

    [self addSubview:_thumbView];
    return self;
}

- (void)applyAccentColor:(UIColor *)color {
    self.onTrackColor = color ?: FTC_Color(FTC_C_ORANGE);
    [self updateVisualsAnimated:NO];
}

- (void)setOn:(BOOL)on {
    [self setOn:on animated:NO];
}

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    _on = on;
    [self updateVisualsAnimated:animated];
}

- (void)updateVisualsAnimated:(BOOL)animated {
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat d = h - 6.0;
    CGFloat targetX = _on ? (w - d - 3.0) : 3.0;
    UIColor *bg = _on ? self.onTrackColor : FTC_Color(0x281714);
    CGColorRef bd = _on ? [[UIColor whiteColor] colorWithAlphaComponent:0.45].CGColor
                        : FTC_Color(0x522A20).CGColor;

    void (^apply)(void) = ^{
        self.trackView.backgroundColor = bg;
        self.trackView.layer.borderColor = bd;
        self.thumbView.frame = CGRectMake(targetX, 3.0, d, d);
    };
    if (animated) {
        [UIView animateWithDuration:0.16 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:apply completion:nil];
    } else {
        apply();
    }
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [super endTrackingWithTouch:touch withEvent:event];
    if (touch && CGRectContainsPoint(CGRectInset(self.bounds, -10, -10), [touch locationInView:self])) {
        [self sendActionsForControlEvents:UIControlEventValueChanged];
    }
}

@end

#pragma mark - FTCMarqueeLabel (Zero-Offscreen Dual-Edge Fade + GPU Glide)

@interface FTCMarqueeLabel : UIView
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) CAGradientLayer *leftFade;
@property (nonatomic, strong) CAGradientLayer *rightFade;
@property (nonatomic, copy) NSString *currentText;
@property (nonatomic, assign) CGFloat lastWidth;
@property (nonatomic, assign) BOOL isOverflowing;
- (void)configureText:(NSString *)text font:(UIFont *)font color:(UIColor *)color bgColor:(UIColor *)bgColor;
- (void)updateEdgeFadeBgColor:(UIColor *)bgColor;
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

- (void)updateEdgeFadeBgColor:(UIColor *)bgColor {
    if (!self.isOverflowing || !bgColor) return;
    UIColor *clearBg = [bgColor colorWithAlphaComponent:0.0];
    if (self.leftFade)  self.leftFade.colors  = @[(id)bgColor.CGColor, (id)clearBg.CGColor];
    if (self.rightFade) self.rightFade.colors = @[(id)clearBg.CGColor, (id)bgColor.CGColor];
}

- (void)configureText:(NSString *)text font:(UIFont *)font color:(UIColor *)color bgColor:(UIColor *)bgColor {
    NSString *safeText = text ?: @"";
    self.label.font = font;
    self.label.textColor = color;
    CGFloat viewW = self.bounds.size.width;
    CGFloat viewH = self.bounds.size.height;
    if ([self.currentText isEqualToString:safeText] && fabs(self.lastWidth - viewW) < 1.0) {
        [self updateEdgeFadeBgColor:bgColor];
        return;
    }
    self.currentText = safeText;
    self.lastWidth = viewW;
    self.label.text = safeText;
    [self.label.layer removeAllAnimations];
    self.label.layer.transform = CATransform3DIdentity;

    CGFloat textW = ceil([safeText sizeWithAttributes:@{NSFontAttributeName: font}].width);
    if (textW <= viewW || viewW < 24.0) {
        self.isOverflowing = NO;
        self.label.frame = CGRectMake(0, 0, viewW, viewH);
        self.leftFade.hidden = YES;
        self.rightFade.hidden = YES;
        return;
    }

    self.isOverflowing = YES;
    CGFloat edgePad = 8.0;
    CGFloat fadeW = 12.0;
    self.label.frame = CGRectMake(edgePad, 0, textW + edgePad, viewH);

    if (!self.leftFade) {
        CAGradientLayer *lf = [CAGradientLayer layer];
        lf.startPoint = CGPointMake(0.0, 0.5);
        lf.endPoint = CGPointMake(1.0, 0.5);
        [self.layer addSublayer:lf];
        self.leftFade = lf;
    }
    if (!self.rightFade) {
        CAGradientLayer *rf = [CAGradientLayer layer];
        rf.startPoint = CGPointMake(0.0, 0.5);
        rf.endPoint = CGPointMake(1.0, 0.5);
        [self.layer addSublayer:rf];
        self.rightFade = rf;
    }
    self.leftFade.frame = CGRectMake(0, 0, fadeW, viewH);
    self.rightFade.frame = CGRectMake(viewW - fadeW, 0, fadeW, viewH);
    self.leftFade.hidden = NO;
    self.rightFade.hidden = NO;
    [self updateEdgeFadeBgColor:bgColor];

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

#pragma mark - Vector Brand Icons (Discord / GitHub / TikTok)

static UIView *FTC_MakeDiscordLogo(CGFloat size) {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, size, size)];
    v.userInteractionEnabled = NO;
    // Official Discord Clyde silhouette (normalized 0..24)
    CGFloat s = size / 24.0;
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(19.3*s, 5.3*s)];
    [p addCurveToPoint:CGPointMake(15.2*s, 4.0*s) controlPoint1:CGPointMake(18.0*s, 4.7*s) controlPoint2:CGPointMake(16.6*s, 4.3*s)];
    [p addLineToPoint:CGPointMake(14.7*s, 5.1*s)];
    [p addCurveToPoint:CGPointMake(9.3*s, 5.1*s) controlPoint1:CGPointMake(12.9*s, 4.8*s) controlPoint2:CGPointMake(11.1*s, 4.8*s)];
    [p addLineToPoint:CGPointMake(8.8*s, 4.0*s)];
    [p addCurveToPoint:CGPointMake(4.7*s, 5.3*s) controlPoint1:CGPointMake(7.4*s, 4.3*s) controlPoint2:CGPointMake(6.0*s, 4.7*s)];
    [p addCurveToPoint:CGPointMake(2.0*s, 17.5*s) controlPoint1:CGPointMake(2.1*s, 9.2*s) controlPoint2:CGPointMake(1.4*s, 13.4*s)];
    [p addCurveToPoint:CGPointMake(7.0*s, 20.0*s) controlPoint1:CGPointMake(3.6*s, 18.7*s) controlPoint2:CGPointMake(5.3*s, 19.5*s)];
    [p addLineToPoint:CGPointMake(8.1*s, 18.2*s)];
    [p addCurveToPoint:CGPointMake(6.3*s, 17.3*s) controlPoint1:CGPointMake(7.5*s, 18.0*s) controlPoint2:CGPointMake(6.9*s, 17.7*s)];
    [p addCurveToPoint:CGPointMake(17.7*s, 17.3*s) controlPoint1:CGPointMake(10.0*s, 19.0*s) controlPoint2:CGPointMake(14.0*s, 19.0*s)];
    [p addCurveToPoint:CGPointMake(15.9*s, 18.2*s) controlPoint1:CGPointMake(17.1*s, 17.7*s) controlPoint2:CGPointMake(16.5*s, 18.0*s)];
    [p addLineToPoint:CGPointMake(17.0*s, 20.0*s)];
    [p addCurveToPoint:CGPointMake(22.0*s, 17.5*s) controlPoint1:CGPointMake(18.7*s, 19.5*s) controlPoint2:CGPointMake(20.4*s, 18.7*s)];
    [p addCurveToPoint:CGPointMake(19.3*s, 5.3*s) controlPoint1:CGPointMake(22.7*s, 12.7*s) controlPoint2:CGPointMake(21.4*s, 8.7*s)];
    [p closePath];
    CAShapeLayer *body = [CAShapeLayer layer];
    body.path = p.CGPath;
    body.fillColor = FTC_Color(0xFFFFFF).CGColor;
    [v.layer addSublayer:body];

    UIBezierPath *eyes = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(7.4*s, 10.7*s, 2.7*s, 3.0*s)];
    [eyes appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(13.9*s, 10.7*s, 2.7*s, 3.0*s)]];
    CAShapeLayer *el = [CAShapeLayer layer];
    el.path = eyes.CGPath;
    el.fillColor = FTC_Color(FTC_C_DISCORD).CGColor;
    [v.layer addSublayer:el];
    return v;
}

static UIView *FTC_MakeGitHubLogo(CGFloat size) {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, size, size)];
    v.userInteractionEnabled = NO;
    CGFloat s = size / 24.0;
    // Crisp Octocat head + ears + shoulders silhouette
    UIBezierPath *p = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(2*s, 2*s, 20*s, 20*s)];
    CAShapeLayer *outer = [CAShapeLayer layer];
    outer.path = p.CGPath;
    outer.fillColor = FTC_Color(0xF1F5F9).CGColor;
    [v.layer addSublayer:outer];

    UIBezierPath *cat = [UIBezierPath bezierPath];
    [cat moveToPoint:CGPointMake(9.5*s, 21.2*s)];
    [cat addLineToPoint:CGPointMake(9.5*s, 18.3*s)];
    [cat addCurveToPoint:CGPointMake(6.2*s, 17.5*s) controlPoint1:CGPointMake(7.2*s, 18.8*s) controlPoint2:CGPointMake(6.7*s, 17.5*s)];
    [cat addCurveToPoint:CGPointMake(8.5*s, 16.5*s) controlPoint1:CGPointMake(5.5*s, 16.5*s) controlPoint2:CGPointMake(7.5*s, 16.5*s)];
    [cat addCurveToPoint:CGPointMake(6.2*s, 11.4*s) controlPoint1:CGPointMake(6.6*s, 15.8*s) controlPoint2:CGPointMake(6.2*s, 13.8*s)];
    [cat addCurveToPoint:CGPointMake(7.2*s, 7.2*s) controlPoint1:CGPointMake(6.2*s, 9.7*s) controlPoint2:CGPointMake(6.7*s, 8.2*s)];
    [cat addLineToPoint:CGPointMake(9.6*s, 8.5*s)];
    [cat addCurveToPoint:CGPointMake(14.4*s, 8.5*s) controlPoint1:CGPointMake(11.1*s, 8.1*s) controlPoint2:CGPointMake(12.9*s, 8.1*s)];
    [cat addLineToPoint:CGPointMake(16.8*s, 7.2*s)];
    [cat addCurveToPoint:CGPointMake(17.8*s, 11.4*s) controlPoint1:CGPointMake(17.3*s, 8.2*s) controlPoint2:CGPointMake(17.8*s, 9.7*s)];
    [cat addCurveToPoint:CGPointMake(14.5*s, 16.6*s) controlPoint1:CGPointMake(17.8*s, 13.8*s) controlPoint2:CGPointMake(17.0*s, 16.0*s)];
    [cat addLineToPoint:CGPointMake(14.5*s, 21.2*s)];
    [cat closePath];
    CAShapeLayer *cl = [CAShapeLayer layer];
    cl.path = cat.CGPath;
    cl.fillColor = FTC_Color(0x161B22).CGColor;
    [v.layer addSublayer:cl];
    return v;
}

static UIBezierPath *FTC_TikTokPath(CGFloat s) {
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(14.6*s, 3.0*s)];
    [p addLineToPoint:CGPointMake(14.6*s, 14.5*s)];
    [p addArcWithCenter:CGPointMake(11.2*s, 14.8*s) radius:3.4*s startAngle:0 endAngle:M_PI*1.55 clockwise:YES];
    [p addLineToPoint:CGPointMake(11.2*s, 13.3*s)];
    [p addArcWithCenter:CGPointMake(11.2*s, 14.8*s) radius:1.5*s startAngle:M_PI*1.55 endAngle:0 clockwise:NO];
    [p addLineToPoint:CGPointMake(12.7*s, 3.0*s)];
    [p closePath];
    UIBezierPath *flag = [UIBezierPath bezierPath];
    [flag moveToPoint:CGPointMake(14.4*s, 3.0*s)];
    [flag addCurveToPoint:CGPointMake(19.2*s, 7.4*s) controlPoint1:CGPointMake(14.7*s, 5.4*s) controlPoint2:CGPointMake(16.8*s, 7.2*s)];
    [flag addLineToPoint:CGPointMake(19.2*s, 9.6*s)];
    [flag addCurveToPoint:CGPointMake(14.4*s, 6.8*s) controlPoint1:CGPointMake(17.3*s, 9.5*s) controlPoint2:CGPointMake(15.6*s, 8.6*s)];
    [flag closePath];
    [p appendPath:flag];
    return p;
}

static UIView *FTC_MakeTikTokLogo(CGFloat size) {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, size, size)];
    v.userInteractionEnabled = NO;
    CGFloat s = size / 24.0;
    CGPathRef gp = FTC_TikTokPath(s).CGPath;
    CAShapeLayer *cyan = [CAShapeLayer layer];
    cyan.path = gp;
    cyan.fillColor = FTC_Color(0x25F4EE).CGColor;
    cyan.position = CGPointMake(-1.2, -0.8);
    [v.layer addSublayer:cyan];

    CAShapeLayer *pink = [CAShapeLayer layer];
    pink.path = gp;
    pink.fillColor = FTC_Color(0xFE2C55).CGColor;
    pink.position = CGPointMake(1.2, 0.8);
    [v.layer addSublayer:pink];

    CAShapeLayer *white = [CAShapeLayer layer];
    white.path = gp;
    white.fillColor = FTC_Color(0xFFFFFF).CGColor;
    [v.layer addSublayer:white];
    return v;
}

#pragma mark - CheatMenuView

@interface CheatMenuView () <UITextFieldDelegate>
@property (nonatomic, strong) UIButton *logoButton;
@property (nonatomic, strong) UILabel *fpsBadge;

@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIView *headerBar;
@property (nonatomic, strong) UIView *headerAccent;
@property (nonatomic, strong) UIView *headerTitleWrap;
@property (nonatomic, strong) UILabel *activeCountBadge;
@property (nonatomic, strong) UIButton *minimizeButton;
@property (nonatomic, strong) UIButton *expandButton;
@property (nonatomic, strong) UIView *sidebar;
@property (nonatomic, strong) UIView *sidebarDivider;
@property (nonatomic, strong) NSMutableArray<UIButton *> *tabButtons;
@property (nonatomic, strong) NSMutableArray<UIView *> *tabIndicators;
@property (nonatomic, strong) FTCScrollView *scrollView;

// In-place references for active tab cards
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UIView *> *cardMap;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, FTCMarqueeLabel *> *titleMarqueeMap;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, FTCMarqueeLabel *> *subMarqueeMap;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, FTCSwitch3D *> *switchMap;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UIButton *> *forgeModeBtnMap;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UILabel *> *stepValMap;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSArray<UIButton *> *> *pillGroupMap;
@property (nonatomic, strong) UITextField *gradeTextField;

// Sub-panels (Forge 3-Mode picker / Ticket Cut Deck / Welcome + QR + JIT Guide)
@property (nonatomic, strong) UIView *subModalOverlay;
@property (nonatomic, strong) NSMutableArray<UILabel *> *ticketCountLabels;
@property (nonatomic, strong) NSMutableArray<UIButton *> *ticketCutButtons;
@property (nonatomic, strong) UILabel *ticketModalStatus;

@property (nonatomic, strong) UIView *welcomeOverlay;
@property (nonatomic, strong) UIView *welcomeCard;
@property (nonatomic, strong) UIView *welcomeMainBox;
@property (nonatomic, strong) UIView *welcomeQrBox;
@property (nonatomic, strong) UIView *welcomeJitGuideBox;
@property (nonatomic, strong) UIButton *saveQrButton;
@property (nonatomic, assign) BOOL launchWelcomeShown;
@property (nonatomic, assign) BOOL returningFromExternalLink;

// Window & mode state
@property (nonatomic, assign) BOOL menuOpen;
@property (nonatomic, assign) BOOL maximized;
@property (nonatomic, assign) BOOL english;
@property (nonatomic, assign) NSInteger forgeModeSelected; // 0=none, 1=Hold(Green), 2=Success(Blue), 3=Great(Purple)
@property (nonatomic, assign) NSInteger swordMultIndex;    // 0=x10, 1=x20, 2=x30, 3=x40
@property (nonatomic, assign) NSInteger selectedTab;
@property (nonatomic, assign) BOOL logoPositioned;
@property (nonatomic, assign) BOOL isDraggingLogo;
@property (nonatomic, assign) CGPoint dragStart;
@property (nonatomic, assign) CGPoint dragStartCenter;
@property (nonatomic, assign) CGSize lastLayoutSize;
@property (nonatomic, assign) CGFloat lastScrollWidth;

// Lightweight timers (exist ONLY when their feature is ON)
@property (nonatomic, strong) CADisplayLink *fpsLink;
@property (nonatomic, assign) NSInteger fpsFrames;
@property (nonatomic, assign) CFTimeInterval fpsLastUpdate;
@property (nonatomic, assign) NSInteger lastDisplayedFps;
@property (nonatomic, strong) NSTimer *forgeKeepAliveTimer;
@property (nonatomic, strong) NSTimer *autoFeverTimer;

// Feature state + anti-spam cooldown timestamps
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *switchOn;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *stepValue;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *modeIndex;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *statusText;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *statusKind; // 0=neutral,1=ok,2=err,3=purple,4=blue
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *descOpen;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *jitLockUntil;

@property (nonatomic, assign) BOOL restoreScheduled;
@property (nonatomic, assign) NSInteger pendingDevRestoreTries;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *pendingDevToggleFids;
@end

@implementation CheatMenuView

- (NSString *)L:(NSString *)vi en:(NSString *)en {
    return self.english ? en : vi;
}

- (UIImage *)sfIcon:(NSString *)name size:(CGFloat)pt color:(UIColor *)color {
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:pt weight:UIImageSymbolWeightSemibold];
    UIImage *img = [UIImage systemImageNamed:name withConfiguration:cfg];
    if (!img) return nil;
    return [img imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
}

// 3-Color Fire Gradient Label (Red -> Orange -> Gold), rendered statically once.
- (UIView *)makeFireGradientTitle:(NSString *)text font:(UIFont *)font frame:(CGRect)frame {
    UIView *wrap = [[UIView alloc] initWithFrame:frame];
    wrap.userInteractionEnabled = NO;
    wrap.backgroundColor = [UIColor clearColor];

    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.frame = wrap.bounds;
    grad.colors = @[
        (id)FTC_Color(0xFF2E2E).CGColor,
        (id)FTC_Color(0xFF7A1A).CGColor,
        (id)FTC_Color(0xFFD166).CGColor,
    ];
    grad.startPoint = CGPointMake(0.0, 0.5);
    grad.endPoint = CGPointMake(1.0, 0.5);
    [wrap.layer addSublayer:grad];

    UILabel *maskLbl = [[UILabel alloc] initWithFrame:wrap.bounds];
    maskLbl.text = text;
    maskLbl.font = font;
    maskLbl.textAlignment = (frame.size.width > 180.0) ? NSTextAlignmentCenter : NSTextAlignmentLeft;
    maskLbl.textColor = [UIColor blackColor];
    wrap.maskView = maskLbl;
    return wrap;
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
    _jitLockUntil = [NSMutableDictionary dictionary];

    _cardMap = [NSMutableDictionary dictionary];
    _titleMarqueeMap = [NSMutableDictionary dictionary];
    _subMarqueeMap = [NSMutableDictionary dictionary];
    _switchMap = [NSMutableDictionary dictionary];
    _forgeModeBtnMap = [NSMutableDictionary dictionary];
    _stepValMap = [NSMutableDictionary dictionary];
    _pillGroupMap = [NSMutableDictionary dictionary];
    _tabButtons = [NSMutableArray array];
    _tabIndicators = [NSMutableArray array];
    _pendingDevToggleFids = [NSMutableArray array];

    _menuOpen = NO;
    _maximized = NO;
    _english = NO;
    _forgeModeSelected = 0;
    _swordMultIndex = 0;
    _selectedTab = 0;
    _logoPositioned = NO;
    _isDraggingLogo = NO;
    _lastDisplayedFps = -1;
    _restoreScheduled = NO;

    for (size_t i = 0; i < kFTC_FeatureCount; i++) {
        const FTC_Feature *f = &kFTC_Features[i];
        if (f->kind == FTC_KIND_STEP) _stepValue[@(f->fid)] = (f->fid == 9) ? @(1) : @(0);
        if (f->kind == FTC_KIND_MODE) _modeIndex[@(f->fid)] = @(0);
    }

    [self loadSavedPreferences];
    [self buildLogo];
    [self buildPanel];
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.welcomeOverlay) return [super hitTest:point withEvent:event];
    if (self.subModalOverlay) return [super hitTest:point withEvent:event];
    if (CGRectContainsPoint(self.logoButton.frame, point)) return [super hitTest:point withEvent:event];
    if (_menuOpen && CGRectContainsPoint(self.panel.frame, point)) return [super hitTest:point withEvent:event];
    return nil;
}

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
        if (tap.state == UIGestureRecognizerStateEnded) [self setMenuOpen:!_menuOpen];
    } @catch (...) {}
}

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

#pragma mark - 16:9 Red-Orange-Black Fire Panel Chrome

- (void)buildPanel {
    UIView *panel = [[UIView alloc] initWithFrame:CGRectZero];
    panel.backgroundColor = FTC_Color(FTC_C_PANEL);
    panel.opaque = YES;
    panel.layer.cornerRadius = 14.0;
    panel.layer.borderColor = FTC_Color(FTC_C_BORDER_HI).CGColor;
    panel.layer.borderWidth = 1.5;
    panel.layer.masksToBounds = NO; // zero offscreen mask pass around UIScrollView!
    panel.hidden = YES;
    [self addSubview:panel];
    self.panel = panel;

    UIView *header = [[UIView alloc] initWithFrame:CGRectZero];
    header.backgroundColor = FTC_Color(FTC_C_HEADER);
    header.opaque = YES;
    header.layer.cornerRadius = 12.0;
    header.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    [panel addSubview:header];
    self.headerBar = header;

    // Fire Red->Orange gradient underline
    UIView *accent = [[UIView alloc] initWithFrame:CGRectZero];
    accent.backgroundColor = FTC_Color(FTC_C_ORANGE);
    accent.opaque = YES;
    [header addSubview:accent];
    self.headerAccent = accent;

    UIView *titleWrap = [self makeFireGradientTitle:@"FORGE TAXX"
                                               font:[UIFont boldSystemFontOfSize:15.5]
                                              frame:CGRectMake(12, 8, 114, 20)];
    [header addSubview:titleWrap];
    self.headerTitleWrap = titleWrap;

    UILabel *badge = [[UILabel alloc] initWithFrame:CGRectZero];
    badge.font = [UIFont boldSystemFontOfSize:10.5];
    badge.textColor = FTC_Color(FTC_C_ORANGE);
    badge.backgroundColor = FTC_Color(FTC_C_TAB_ON);
    badge.opaque = YES;
    badge.textAlignment = NSTextAlignmentCenter;
    badge.layer.cornerRadius = 7.0;
    badge.layer.masksToBounds = YES;
    [header addSubview:badge];
    self.activeCountBadge = badge;

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
        tb.titleLabel.font = [UIFont boldSystemFontOfSize:11.0];
        tb.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        tb.opaque = YES;
        tb.layer.cornerRadius = 7.0;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        tb.contentEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 4);
        tb.titleEdgeInsets = UIEdgeInsetsMake(0, 5, 0, 0);
#pragma clang diagnostic pop
        [tb addTarget:self action:@selector(onSelectTab:) forControlEvents:UIControlEventTouchUpInside];

        UIView *ind = [[UIView alloc] initWithFrame:CGRectMake(0, 4, 3, 18)];
        ind.backgroundColor = FTC_Color(FTC_C_ORANGE);
        ind.opaque = YES;
        ind.hidden = YES;
        [tb addSubview:ind];

        [sidebar addSubview:tb];
        [self.tabButtons addObject:tb];
        [self.tabIndicators addObject:ind];
    }

    FTCScrollView *scroll = [[FTCScrollView alloc] initWithFrame:CGRectZero];
    scroll.backgroundColor = FTC_Color(FTC_C_PANEL);
    scroll.opaque = YES;
    scroll.clipsToBounds = YES;
    scroll.showsVerticalScrollIndicator = YES;
    scroll.alwaysBounceVertical = YES;
    scroll.canCancelContentTouches = YES;
    scroll.delaysContentTouches = NO;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [panel addSubview:scroll];
    self.scrollView = scroll;

    [self updateTabAppearance];
    [self updateActiveCountBadge];
    [self updateExpandButtonGlyph];
}

#pragma mark - Attach & Layout

- (void)attachToWindow:(UIWindow *)window {
    @try {
        if (!window) return;
        self.frame = window.bounds;
        if (self.superview != window) [window addSubview:self];
        if (window.subviews.lastObject != self) [window bringSubviewToFront:self];
        [self ensureLogoPositioned];
        [self layoutFpsBadge];
        if (_menuOpen) [self layoutPanel];
        if (self.welcomeOverlay) [self layoutWelcomeOverlay];
        [self scheduleStaggeredRestoreIfNeeded];
        if (!self.launchWelcomeShown) {
            self.launchWelcomeShown = YES;
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [weakSelf showWelcomePopup];
            });
        }
    } @catch (...) {}
}

- (void)onAppEnteredForeground {
    @try {
        if (self.returningFromExternalLink) {
            self.returningFromExternalLink = NO;
            return;
        }
        if (!self.welcomeOverlay && self.superview) {
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [weakSelf showWelcomePopup];
            });
        }
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

- (void)layoutFpsBadge {
    @try {
        if (self.bounds.size.width < 100 || self.bounds.size.height < 100) return;
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
            if (self.welcomeOverlay) [self layoutWelcomeOverlay];
            if (self.subModalOverlay) self.subModalOverlay.frame = self.bounds;
        }
    } @catch (...) {}
}

- (void)layoutPanel {
    @try {
        CGFloat bw = self.bounds.size.width;
        CGFloat bh = self.bounds.size.height;
        if (bw < 100 || bh < 100) return;

        UIEdgeInsets safe = [self ftcSafeInsets];
        CGFloat safeLeft = safe.left, safeRight = bw - safe.right;
        CGFloat safeTop = safe.top, safeBottom = bh - safe.bottom;
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
                pw = maxSideW; ph = availH; y = safeTop;
            } else {
                pw = MIN(kCompactMaxW, maxSideW);
                ph = MIN(kCompactMaxH, availH);
                y = MAX(safeTop, MIN(logo.origin.y, safeBottom - ph));
            }
            x = putLeft ? (logo.origin.x - kLogoGap - pw) : (logo.origin.x + kLogoSize + kLogoGap);
        } else {
            BOOL putBelow = (spaceBelow >= spaceAbove);
            CGFloat maxVertH = MAX(180.0, putBelow ? spaceBelow : spaceAbove);
            CGFloat availW = MAX(260.0, safeRight - safeLeft);
            pw = self.maximized ? availW : MIN(kCompactMaxW, availW);
            ph = self.maximized ? maxVertH : MIN(kCompactMaxH, maxVertH);
            x = safeLeft + (availW - pw) * 0.5;
            y = putBelow ? (logo.origin.y + kLogoSize + kLogoGap) : (logo.origin.y - kLogoGap - ph);
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
        self.activeCountBadge.frame = CGRectMake(128, (kHeaderH - 20) * 0.5, 62, 20);

        CGFloat btnW = 30.0, btnH = 26.0, btnY = (kHeaderH - btnH) * 0.5;
        CGFloat hW = W - inset * 2.0;
        self.minimizeButton.frame = CGRectMake(hW - 8 - btnW, btnY, btnW, btnH);
        self.expandButton.frame = CGRectMake(hW - 8 - btnW - 6 - btnW, btnY, btnW, btnH);

        CGFloat bodyY = inset + kHeaderH;
        CGFloat bodyH = MAX(80.0, H - bodyY - inset - 4.0);
        CGFloat sideW = (W < 390.0) ? 98.0 : kSidebarW;
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
        if (!open) {
            [self endEditing:YES];
            [self dismissSubModal];
        } else {
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

#pragma mark - Tabs & Strict 1-Item-Per-Row Full-Width Cards

- (void)onSelectTab:(UIButton *)sender {
    NSInteger idx = sender.tag;
    if (idx < 0 || idx >= kTabCount) return;
    [self endEditing:YES];
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
        UIColor *col = active ? FTC_Color(FTC_C_GOLD)
                              : (onCount > 0 ? FTC_Color(FTC_C_ORANGE) : FTC_Color(FTC_C_TEXT2));
        [tb setTitle:label forState:UIControlStateNormal];
        [tb setTitleColor:col forState:UIControlStateNormal];
        UIImage *ico = [self sfIcon:[NSString stringWithUTF8String:kTabs[i].sf_symbol] size:11.5 color:col];
        [tb setImage:ico forState:UIControlStateNormal];
        tb.backgroundColor = active ? FTC_Color(FTC_C_TAB_ON) : FTC_Color(FTC_C_SIDEBAR);
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

// STRICT 1-ITEM-PER-ROW FULL-WIDTH LAYOUT (zero 2-col splitting, zero orphan cards!)
- (void)buildActiveTabCards {
    @try {
        for (UIView *sub in [self.scrollView.subviews copy]) [sub removeFromSuperview];
        [self.cardMap removeAllObjects];
        [self.titleMarqueeMap removeAllObjects];
        [self.subMarqueeMap removeAllObjects];
        [self.switchMap removeAllObjects];
        [self.forgeModeBtnMap removeAllObjects];
        [self.stepValMap removeAllObjects];
        [self.pillGroupMap removeAllObjects];
        self.gradeTextField = nil;

        CGFloat W = self.scrollView.bounds.size.width;
        if (W < 120.0) return;

        const char *cid = kTabs[self.selectedTab].cid;
        CGFloat pad = 7.0;
        CGFloat gap = 6.0;
        CGFloat cardW = W - pad * 2.0;
        CGFloat curY = pad;

        for (size_t i = 0; i < kFTC_FeatureCount; i++) {
            const FTC_Feature *f = &kFTC_Features[i];
            if (strcmp(f->category, cid) != 0) continue;
            CGFloat cardH = (f->fid == 12) ? 68.0 : 56.0;
            UIView *card = [self makeCardForFeature:f frame:CGRectMake(pad, curY, cardW, cardH)];
            [self.scrollView addSubview:card];
            curY += cardH + gap;
        }

        if (strcmp(cid, "setting") == 0) {
            CGFloat halfW = floor((cardW - gap) * 0.5);
            UIButton *infoBtn = [UIButton buttonWithType:UIButtonTypeCustom];
            infoBtn.frame = CGRectMake(pad, curY + 2.0, halfW, 34.0);
            [infoBtn setTitle:[self L:@"Cộng đồng & Ủng hộ (QR)" en:@"Community & Donate (QR)"]
                     forState:UIControlStateNormal];
            infoBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
            [infoBtn setTitleColor:FTC_Color(FTC_C_TEXT) forState:UIControlStateNormal];
            infoBtn.backgroundColor = FTC_Color(FTC_C_MOMO);
            infoBtn.opaque = YES;
            infoBtn.layer.cornerRadius = 9.0;
            infoBtn.layer.borderColor = FTC_Color(FTC_C_MOMO_HI).CGColor;
            infoBtn.layer.borderWidth = 1.0;
            [infoBtn addTarget:self action:@selector(showWelcomePopup) forControlEvents:UIControlEventTouchUpInside];
            [self.scrollView addSubview:infoBtn];

            UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeCustom];
            resetBtn.frame = CGRectMake(pad + halfW + gap, curY + 2.0, halfW, 34.0);
            [resetBtn setTitle:[self L:@"Tắt hết & Xóa lưu" en:@"Reset All & Clear"]
                      forState:UIControlStateNormal];
            resetBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
            [resetBtn setTitleColor:FTC_Color(FTC_C_RED_HI) forState:UIControlStateNormal];
            resetBtn.backgroundColor = FTC_Color(FTC_C_TAB_ON);
            resetBtn.opaque = YES;
            resetBtn.layer.cornerRadius = 9.0;
            resetBtn.layer.borderColor = FTC_Color(FTC_C_RED).CGColor;
            resetBtn.layer.borderWidth = 1.0;
            [resetBtn addTarget:self action:@selector(onResetAllCheats) forControlEvents:UIControlEventTouchUpInside];
            [self.scrollView addSubview:resetBtn];
            curY += 42.0;
        }

        self.scrollView.contentSize = CGSizeMake(W, MAX(curY + 6.0, self.scrollView.bounds.size.height + 1.0));
    } @catch (...) {}
}

- (UIColor *)accentColorForForgeMode:(NSInteger)mode {
    if (mode == 1) return FTC_Color(FTC_C_OK);     // 1. Giữ nguyên -> Green
    if (mode == 2) return FTC_Color(FTC_C_BLUE);   // 2. Thành công -> Blue
    if (mode == 3) return FTC_Color(FTC_C_PURPLE); // 3. Đại thành công -> Purple
    return FTC_Color(FTC_C_TEXT2);
}

- (UIColor *)cardBgForFeature:(int)fid on:(BOOL)on {
    if (!on) return FTC_Color(FTC_C_CARD);
    if (fid == 4) {
        if (self.forgeModeSelected == 1) return FTC_Color(0x0E2317);
        if (self.forgeModeSelected == 2) return FTC_Color(0x0D1E2E);
        if (self.forgeModeSelected == 3) return FTC_Color(0x231136);
    }
    return FTC_Color(FTC_C_CARD_ON);
}

- (UIColor *)cardBorderForFeature:(int)fid on:(BOOL)on {
    if (fid == 4 && on && self.forgeModeSelected >= 1) {
        return [self accentColorForForgeMode:self.forgeModeSelected];
    }
    return on ? FTC_Color(FTC_C_ORANGE) : FTC_Color(FTC_C_BORDER);
}

- (UIView *)makeCardForFeature:(const FTC_Feature *)f frame:(CGRect)frame {
    CGFloat W = frame.size.width;
    CGFloat H = frame.size.height;
    BOOL on = [self.switchOn[@(f->fid)] boolValue];
    UIColor *bg = [self cardBgForFeature:f->fid on:on];
    UIColor *bd = [self cardBorderForFeature:f->fid on:on];

    UIView *card = [[UIView alloc] initWithFrame:frame];
    card.opaque = YES;
    card.backgroundColor = bg;
    card.layer.borderColor = bd.CGColor;
    card.layer.borderWidth = 1.0;
    card.layer.cornerRadius = 11.0;
    self.cardMap[@(f->fid)] = card;

    // Left SF Symbol Icon Tile (UI/UX Pro Max visual hierarchy)
    UIView *iconTile = [[UIView alloc] initWithFrame:CGRectMake(8, floor((H - 32.0) * 0.5), 32, 32)];
    iconTile.backgroundColor = FTC_Color(0x271511);
    iconTile.opaque = YES;
    iconTile.layer.cornerRadius = 8.0;
    iconTile.layer.borderColor = FTC_Color(FTC_C_BORDER_HI).CGColor;
    iconTile.layer.borderWidth = 0.8;
    iconTile.userInteractionEnabled = NO;
    UIColor *icoCol = (f->fid == 4 && self.forgeModeSelected >= 1)
                    ? [self accentColorForForgeMode:self.forgeModeSelected]
                    : (on ? FTC_Color(FTC_C_GOLD) : FTC_Color(FTC_C_ORANGE));
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(6, 6, 20, 20)];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.image = [self sfIcon:[NSString stringWithUTF8String:f->sf_symbol] size:15.0 color:icoCol];
    iv.tag = 777;
    [iconTile addSubview:iv];
    iconTile.tag = 776;
    [card addSubview:iconTile];

    // Right control area width
    BOOL hasSecondary = (f->fid == 7 || f->fid == 24);
    CGFloat ctrlAreaW = 58.0;
    if (f->fid == 4) ctrlAreaW = 144.0;
    else if (f->fid == 6) ctrlAreaW = 128.0;
    else if (f->fid == 39) ctrlAreaW = 204.0;
    else if (f->fid == 44) ctrlAreaW = 94.0;
    else if (f->kind == FTC_KIND_STEP) ctrlAreaW = 178.0;
    else if (f->kind == FTC_KIND_MODE) ctrlAreaW = (f->fid == 42) ? 168.0 : 154.0;
    else if (hasSecondary) ctrlAreaW = 132.0;

    CGFloat textX = 48.0;
    CGFloat textW = MAX(60.0, W - textX - ctrlAreaW - 10.0);

    FTCMarqueeLabel *titleM = [[FTCMarqueeLabel alloc] initWithFrame:CGRectMake(textX, 8, textW, 18)];
    NSString *titleStr = [NSString stringWithUTF8String:(self.english ? f->name_en : f->name_vi)];
    [titleM configureText:titleStr font:[UIFont boldSystemFontOfSize:12.5] color:FTC_Color(FTC_C_TEXT) bgColor:bg];
    [card addSubview:titleM];
    self.titleMarqueeMap[@(f->fid)] = titleM;

    FTCMarqueeLabel *subM = [[FTCMarqueeLabel alloc] initWithFrame:CGRectMake(textX, 29, textW, 18)];
    [card addSubview:subM];
    self.subMarqueeMap[@(f->fid)] = subM;
    [self refreshCardSubtitle:f];

    UIButton *textTap = [UIButton buttonWithType:UIButtonTypeCustom];
    textTap.frame = CGRectMake(textX - 4, 2, textW + 8, H - 4);
    textTap.backgroundColor = [UIColor clearColor];
    textTap.tag = f->fid;
    [textTap addTarget:self action:@selector(onToggleDesc:) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:textTap];

    // ---- Right-side Controls ----
    if (f->fid == 4) {
        // #4: [ Đổi mode ▾ ] + 3D Switch
        FTCSwitch3D *sw = [self make3DSwitch:4 frame:CGRectMake(W - 56.0, floor((H - 26.0) * 0.5), 48.0, 26.0)
                                          on:on accent:(self.forgeModeSelected >= 1 ? [self accentColorForForgeMode:self.forgeModeSelected] : FTC_Color(FTC_C_ORANGE))];
        [card addSubview:sw];
        self.switchMap[@(4)] = sw;

        UIButton *modeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        modeBtn.frame = CGRectMake(W - 56.0 - 86.0, floor((H - 28.0) * 0.5), 80.0, 28.0);
        modeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        modeBtn.opaque = YES;
        modeBtn.layer.cornerRadius = 8.0;
        modeBtn.layer.borderWidth = 1.0;
        [modeBtn addTarget:self action:@selector(onOpenForgeModePicker) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:modeBtn];
        self.forgeModeBtnMap[@(4)] = modeBtn;
        [self styleForgeModeButton:modeBtn];
    } else if (f->fid == 6) {
        // #6: Direct Keyboard Input (0..999) + [ Đặt ]
        UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(W - 126.0, floor((H - 28.0) * 0.5), 64.0, 28.0)];
        tf.keyboardType = UIKeyboardTypeNumberPad;
        tf.text = [NSString stringWithFormat:@"%ld", (long)[self.stepValue[@(6)] integerValue]];
        tf.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightBold];
        tf.textColor = FTC_Color(FTC_C_GOLD);
        tf.backgroundColor = FTC_Color(FTC_C_PANEL);
        tf.textAlignment = NSTextAlignmentCenter;
        tf.layer.cornerRadius = 7.0;
        tf.layer.borderColor = FTC_Color(FTC_C_BORDER_HI).CGColor;
        tf.layer.borderWidth = 1.0;
        tf.delegate = self;
        [tf addTarget:self action:@selector(onGradeTextChanged:) forControlEvents:UIControlEventEditingChanged];
        [card addSubview:tf];
        self.gradeTextField = tf;

        UIButton *apply = [UIButton buttonWithType:UIButtonTypeCustom];
        apply.frame = CGRectMake(W - 56.0, floor((H - 28.0) * 0.5), 48.0, 28.0);
        [apply setTitle:[self L:@"Đặt" en:@"Set"] forState:UIControlStateNormal];
        apply.titleLabel.font = [UIFont boldSystemFontOfSize:11.5];
        [apply setTitleColor:FTC_Color(FTC_C_TEXT) forState:UIControlStateNormal];
        apply.backgroundColor = FTC_Color(FTC_C_RED);
        apply.opaque = YES;
        apply.layer.cornerRadius = 8.0;
        apply.tag = 6;
        [apply addTarget:self action:@selector(onStepApply:) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:apply];
    } else if (f->fid == 39) {
        // #39: [x10 | x20 | x30 | x40] + 3D Switch
        FTCSwitch3D *sw = [self make3DSwitch:39 frame:CGRectMake(W - 56.0, floor((H - 26.0) * 0.5), 48.0, 26.0)
                                          on:on accent:FTC_Color(FTC_C_ORANGE)];
        [card addSubview:sw];
        self.switchMap[@(39)] = sw;

        [self addFlatPillGroupToCard:card fid:39 items:@[@"x10", @"x20", @"x30", @"x40"]
                       selectedIndex:self.swordMultIndex
                               frame:CGRectMake(W - 56.0 - 144.0, floor((H - 28.0) * 0.5), 138.0, 28.0)];
    } else if (f->fid == 44) {
        // #44: Remove Tickets -> [ Mở mode ▾ ] sub-panel
        UIButton *openBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        openBtn.frame = CGRectMake(W - 92.0, floor((H - 28.0) * 0.5), 84.0, 28.0);
        [openBtn setTitle:[self L:@"Mở bảng ▾" en:@"Tickets ▾"] forState:UIControlStateNormal];
        openBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11.5];
        [openBtn setTitleColor:FTC_Color(FTC_C_GOLD) forState:UIControlStateNormal];
        openBtn.backgroundColor = FTC_Color(FTC_C_BTN_BG);
        openBtn.opaque = YES;
        openBtn.layer.cornerRadius = 8.0;
        openBtn.layer.borderColor = FTC_Color(FTC_C_ORANGE).CGColor;
        openBtn.layer.borderWidth = 1.0;
        [openBtn addTarget:self action:@selector(onOpenTicketCutModal) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:openBtn];
    } else if (f->kind == FTC_KIND_PATCH || f->kind == FTC_KIND_DEV_TOGGLE) {
        FTCSwitch3D *sw = [self make3DSwitch:f->fid frame:CGRectMake(W - 56.0, floor((H - 26.0) * 0.5), 48.0, 26.0)
                                          on:on accent:FTC_Color(FTC_C_ORANGE)];
        [card addSubview:sw];
        self.switchMap[@(f->fid)] = sw;

        if (hasSecondary) {
            UIButton *ex = [self makeSecondaryButtonForFeature:f
                                                         frame:CGRectMake(W - 56.0 - 74.0, floor((H - 28.0) * 0.5), 68.0, 28.0)];
            [card addSubview:ex];
        }
    } else if (f->kind == FTC_KIND_ONESHOT) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(W - 60.0, floor((H - 28.0) * 0.5), 52.0, 28.0);
        [b setTitle:[self L:@"Chạy" en:@"Run"] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:11.5];
        [b setTitleColor:FTC_Color(FTC_C_TEXT) forState:UIControlStateNormal];
        b.backgroundColor = FTC_Color(FTC_C_RED);
        b.opaque = YES;
        b.layer.cornerRadius = 8.0;
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
        CGFloat totalW = 148.0;
        NSInteger selIdx = [self.modeIndex[@(f->fid)] integerValue];
        if (f->fid == 28) {
            items = @[ [self L:@"-1 ngày" en:@"-1 Day"], [self L:@"+1 ngày" en:@"+1 Day"] ];
            selIdx = -1;
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
                                   frame:CGRectMake(W - 176.0, 6.0, 168.0, 25.0)];

            UIButton *plus = [UIButton buttonWithType:UIButtonTypeCustom];
            plus.frame = CGRectMake(W - 84.0, 37.0, 76.0, 24.0);
            [plus setTitle:[self L:@"+1 vé" en:@"+1 Ticket"] forState:UIControlStateNormal];
            plus.titleLabel.font = [UIFont boldSystemFontOfSize:11];
            [plus setTitleColor:FTC_Color(FTC_C_TEXT) forState:UIControlStateNormal];
            plus.backgroundColor = FTC_Color(FTC_C_RED);
            plus.opaque = YES;
            plus.layer.cornerRadius = 7.0;
            plus.tag = 12;
            [plus addTarget:self action:@selector(onTicketPlus:) forControlEvents:UIControlEventTouchUpInside];
            [card addSubview:plus];
        } else {
            // #9 Jump To Day: [ - ] [ day ] [ + ] [ Nhảy ]
            CGFloat sx = W - 176.0, sy = floor((H - 28.0) * 0.5);
            NSInteger v = [self.stepValue[@(f->fid)] integerValue];
            [card addSubview:[self makeFlatMiniBtn:@"−" frame:CGRectMake(sx, sy, 32, 28)
                                               tag:(f->fid * 10 + 0) action:@selector(onStepDelta:)]];
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

            [card addSubview:[self makeFlatMiniBtn:@"+" frame:CGRectMake(sx + 78, sy, 32, 28)
                                               tag:(f->fid * 10 + 1) action:@selector(onStepDelta:)]];
            UIButton *apply = [UIButton buttonWithType:UIButtonTypeCustom];
            apply.frame = CGRectMake(sx + 114, sy, 54, 28);
            [apply setTitle:[self L:@"Nhảy" en:@"Jump"] forState:UIControlStateNormal];
            apply.titleLabel.font = [UIFont boldSystemFontOfSize:11.5];
            [apply setTitleColor:FTC_Color(FTC_C_TEXT) forState:UIControlStateNormal];
            apply.backgroundColor = FTC_Color(FTC_C_RED);
            apply.opaque = YES;
            apply.layer.cornerRadius = 7.0;
            apply.tag = f->fid;
            [apply addTarget:self action:@selector(onStepApply:) forControlEvents:UIControlEventTouchUpInside];
            [card addSubview:apply];
        }
    }
    return card;
}

- (FTCSwitch3D *)make3DSwitch:(int)fid frame:(CGRect)frame on:(BOOL)on accent:(UIColor *)accent {
    FTCSwitch3D *sw = [[FTCSwitch3D alloc] initWithFrame:frame];
    sw.tag = fid;
    [sw applyAccentColor:accent];
    [sw setOn:on animated:NO];
    [sw addTarget:self action:@selector(on3DSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    return sw;
}

- (void)styleForgeModeButton:(UIButton *)b {
    if (!b) return;
    [b setTitle:[self L:@"Đổi mode ▾" en:@"Mode ▾"] forState:UIControlStateNormal];
    BOOL on = [self.switchOn[@(4)] boolValue];
    if (on && self.forgeModeSelected >= 1) {
        UIColor *ac = [self accentColorForForgeMode:self.forgeModeSelected];
        b.backgroundColor = FTC_Color(0x211514);
        b.layer.borderColor = ac.CGColor;
        [b setTitleColor:ac forState:UIControlStateNormal];
    } else {
        b.backgroundColor = FTC_Color(FTC_C_BTN_BG);
        b.layer.borderColor = FTC_Color(FTC_C_BORDER_HI).CGColor;
        [b setTitleColor:FTC_Color(FTC_C_TEXT2) forState:UIControlStateNormal];
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
        b.titleLabel.minimumScaleFactor = 0.72;
        b.opaque = YES;
        b.layer.cornerRadius = 6.0;
        b.layer.borderWidth = 1.0;
        b.tag = fid * 10 + i;
        BOOL sel = (i == selIdx);
        b.backgroundColor = sel ? FTC_Color(FTC_C_RED) : FTC_Color(FTC_C_BTN_OFF);
        b.layer.borderColor = sel ? FTC_Color(FTC_C_ORANGE).CGColor : FTC_Color(FTC_C_BORDER_HI).CGColor;
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
        b.backgroundColor = sel ? FTC_Color(FTC_C_RED) : FTC_Color(FTC_C_BTN_OFF);
        b.layer.borderColor = sel ? FTC_Color(FTC_C_ORANGE).CGColor : FTC_Color(FTC_C_BORDER_HI).CGColor;
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

#pragma mark - In-Place O(1) Card Updates & JIT Shake/Anti-Spam

- (void)refreshCardSubtitle:(const FTC_Feature *)f {
    if (!f) return;
    FTCMarqueeLabel *sub = self.subMarqueeMap[@(f->fid)];
    if (!sub) return;
    UIView *card = self.cardMap[@(f->fid)];
    UIColor *bg = card ? card.backgroundColor : FTC_Color(FTC_C_CARD);
    NSString *status = self.statusText[@(f->fid)];
    BOOL showDesc = [self.descOpen[@(f->fid)] boolValue];
    NSInteger kind = [self.statusKind[@(f->fid)] integerValue];
    UIFont *font = [UIFont systemFontOfSize:10.5];
    if (showDesc || status.length == 0) {
        NSString *desc = [NSString stringWithUTF8String:(self.english ? f->desc_en : f->desc_vi)];
        [sub configureText:desc font:font color:FTC_Color(FTC_C_TEXT2) bgColor:bg];
    } else {
        UIColor *col = (kind == 4) ? FTC_Color(FTC_C_BLUE)
                     : (kind == 3) ? FTC_Color(FTC_C_PURPLE_HI)
                     : (kind == 1) ? FTC_Color(FTC_C_OK)
                     : (kind == 2) ? FTC_Color(FTC_C_ERR)
                                   : FTC_Color(FTC_C_TEXT2);
        [sub configureText:status font:font color:col bgColor:bg];
    }
}

- (void)updateCardInPlace:(int)fid {
    const FTC_Feature *f = FTC_FeatureById(fid);
    if (!f) return;
    BOOL on = [self.switchOn[@(fid)] boolValue];
    UIColor *bg = [self cardBgForFeature:fid on:on];
    UIColor *bd = [self cardBorderForFeature:fid on:on];
    UIView *card = self.cardMap[@(fid)];
    if (card) {
        card.backgroundColor = bg;
        card.layer.borderColor = bd.CGColor;
        FTCMarqueeLabel *tm = self.titleMarqueeMap[@(fid)];
        if (tm) [tm updateEdgeFadeBgColor:bg];
        UIView *tile = [card viewWithTag:776];
        UIImageView *iv = (UIImageView *)[tile viewWithTag:777];
        if (iv) {
            UIColor *icoCol = (fid == 4 && self.forgeModeSelected >= 1)
                            ? [self accentColorForForgeMode:self.forgeModeSelected]
                            : (on ? FTC_Color(FTC_C_GOLD) : FTC_Color(FTC_C_ORANGE));
            iv.image = [self sfIcon:[NSString stringWithUTF8String:f->sf_symbol] size:15.0 color:icoCol];
        }
    }
    FTCSwitch3D *sw = self.switchMap[@(fid)];
    if (sw) {
        if (fid == 4 && self.forgeModeSelected >= 1) {
            [sw applyAccentColor:[self accentColorForForgeMode:self.forgeModeSelected]];
        }
        [sw setOn:on animated:YES];
    }
    if (fid == 4) [self styleForgeModeButton:self.forgeModeBtnMap[@(4)]];
    [self refreshCardSubtitle:f];
    [self updateActiveCountBadge];
    [self updateTabAppearance];
}

// Gentle horizontal shake + light haptic + 1.5s anti-spam lock when JIT is missing
- (void)triggerJitLockedFeedbackForFeature:(int)fid {
    const FTC_Feature *f = FTC_FeatureById(fid);
    NSString *fname = f ? [NSString stringWithUTF8String:(self.english ? f->name_en : f->name_vi)] : @"";
    NSString *msg = self.english
        ? [NSString stringWithFormat:@"%@ requires opening with \"Open with JIT\"", fname]
        : [NSString stringWithFormat:@"%@ cần mở game bằng \"Open with JIT\"", fname];
    [self setStatus:fid text:msg kind:2];
    [self updateCardInPlace:fid];

    // Anti-spam lock for 1.5s
    self.jitLockUntil[@(fid)] = @(CACurrentMediaTime() + 1.5);

    // Light haptic nudge
    @try {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [gen impactOccurred];
    } @catch (...) {}

    // Crisp horizontal shake on the switch (GPU-only)
    UIView *target = self.switchMap[@(fid)] ?: self.cardMap[@(fid)];
    if (target) {
        CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
        shake.values = @[@(0), @(-6), @(6), @(-4), @(4), @(-2), @(0)];
        shake.duration = 0.26;
        [target.layer addAnimation:shake forKey:@"ftcJitShake"];
    }
}

- (BOOL)isFeatureSpamLocked:(int)fid {
    NSNumber *until = self.jitLockUntil[@(fid)];
    if (!until) return NO;
    return (CACurrentMediaTime() < [until doubleValue]);
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

#pragma mark - Sub-Modals (#4 Forge 3-Mode Picker & #44 Ticket Cut Deck)

- (void)dismissSubModal {
    if (self.subModalOverlay) {
        [self.subModalOverlay removeFromSuperview];
        self.subModalOverlay = nil;
        self.ticketCountLabels = nil;
        self.ticketCutButtons = nil;
        self.ticketModalStatus = nil;
    }
}

- (void)onOpenForgeModePicker {
    @try {
        [self dismissSubModal];
        UIView *ov = [[UIView alloc] initWithFrame:self.bounds];
        ov.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
        UIButton *bgDismiss = [UIButton buttonWithType:UIButtonTypeCustom];
        bgDismiss.frame = ov.bounds;
        [bgDismiss addTarget:self action:@selector(dismissSubModal) forControlEvents:UIControlEventTouchUpInside];
        [ov addSubview:bgDismiss];

        CGFloat mw = 300.0, mh = 216.0;
        UIView *box = [[UIView alloc] initWithFrame:CGRectMake(floor((self.bounds.size.width - mw)*0.5),
                                                               floor((self.bounds.size.height - mh)*0.5),
                                                               mw, mh)];
        box.backgroundColor = FTC_Color(FTC_C_HEADER);
        box.opaque = YES;
        box.layer.cornerRadius = 14.0;
        box.layer.borderColor = FTC_Color(FTC_C_ORANGE).CGColor;
        box.layer.borderWidth = 1.4;
        [ov addSubview:box];

        UILabel *hdr = [[UILabel alloc] initWithFrame:CGRectMake(14, 10, mw - 50, 22)];
        hdr.text = [self L:@"Chọn chế độ rèn kiếm (100%)" en:@"Select Forge Mode (100%)"];
        hdr.font = [UIFont boldSystemFontOfSize:13.5];
        hdr.textColor = FTC_Color(FTC_C_GOLD);
        [box addSubview:hdr];

        UIButton *xBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        xBtn.frame = CGRectMake(mw - 34, 8, 26, 26);
        [xBtn setTitle:@"✕" forState:UIControlStateNormal];
        xBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [xBtn setTitleColor:FTC_Color(FTC_C_TEXT2) forState:UIControlStateNormal];
        [xBtn addTarget:self action:@selector(dismissSubModal) forControlEvents:UIControlEventTouchUpInside];
        [box addSubview:xBtn];

        NSArray<NSDictionary *> *modes = @[
            @{@"m": @(1), @"vi": @"1. GIỮ NGUYÊN (100%)",     @"en": @"1. HOLD (100%)",          @"col": @(FTC_C_OK),     @"bg": @(0x0F2618)},
            @{@"m": @(2), @"vi": @"2. THÀNH CÔNG (100%)",     @"en": @"2. SUCCESS (100%)",       @"col": @(FTC_C_BLUE),   @"bg": @(0x0E2033)},
            @{@"m": @(3), @"vi": @"3. ĐẠI THÀNH CÔNG (100%)", @"en": @"3. GREAT SUCCESS (100%)", @"col": @(FTC_C_PURPLE), @"bg": @(0x241138)},
        ];
        for (NSInteger i = 0; i < 3; i++) {
            NSDictionary *d = modes[i];
            NSInteger m = [d[@"m"] integerValue];
            BOOL sel = ([self.switchOn[@(4)] boolValue] && self.forgeModeSelected == m);
            UIButton *mb = [UIButton buttonWithType:UIButtonTypeCustom];
            mb.frame = CGRectMake(14, 44 + i * 52, mw - 28, 44);
            [mb setTitle:[self L:d[@"vi"] en:d[@"en"]] forState:UIControlStateNormal];
            mb.titleLabel.font = [UIFont boldSystemFontOfSize:13];
            UIColor *mc = FTC_Color([d[@"col"] unsignedIntValue]);
            [mb setTitleColor:mc forState:UIControlStateNormal];
            mb.backgroundColor = sel ? FTC_Color([d[@"bg"] unsignedIntValue]) : FTC_Color(FTC_C_CARD);
            mb.opaque = YES;
            mb.layer.cornerRadius = 10.0;
            mb.layer.borderColor = mc.CGColor;
            mb.layer.borderWidth = sel ? 2.0 : 1.0;
            mb.tag = m;
            [mb addTarget:self action:@selector(onPickForgeMode:) forControlEvents:UIControlEventTouchUpInside];
            [box addSubview:mb];
        }

        [self addSubview:ov];
        self.subModalOverlay = ov;
    } @catch (...) {}
}

- (void)onPickForgeMode:(UIButton *)sender {
    @try {
        NSInteger mode = sender.tag; // 1=Hold(Green), 2=Success(Blue), 3=Great(Purple)
        if (mode < 1 || mode > 3) return;
        [self dismissSubModal];

        self.forgeModeSelected = mode;
        [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:kPrefForgeMode];

        // Immediately activate chosen mode at 100% with ZERO delay!
        FTC_CallResult cr = FTC_SetForgeWinMode((int)mode);
        if (cr == FTC_CALL_OK) {
            self.switchOn[@(4)] = @(YES);
            [self saveSwitchState:4 on:YES];
            [self applyForgeModeStatusText:mode];
            [self syncForgeKeepAliveTimer];
        } else {
            self.switchOn[@(4)] = @(NO);
            [self setStatus:4 text:[self messageForCall:cr] kind:2];
        }
        [self updateCardInPlace:4];
    } @catch (...) {}
}

- (void)applyForgeModeStatusText:(NSInteger)mode {
    if (mode == 1) {
        [self setStatus:4 text:[self L:@"Mode 1 • GIỮ NGUYÊN 100%" en:@"Mode 1 • HOLD 100%"] kind:1];
    } else if (mode == 2) {
        [self setStatus:4 text:[self L:@"Mode 2 • THÀNH CÔNG 100%" en:@"Mode 2 • SUCCESS 100%"] kind:4];
    } else if (mode == 3) {
        [self setStatus:4 text:[self L:@"Mode 3 • ĐẠI THÀNH CÔNG 100%" en:@"Mode 3 • GREAT 100%"] kind:3];
    }
}

// #44: Live Ticket Deck Sub-Panel (shows all 5 game ticket types + X cut button per type)
- (void)onOpenTicketCutModal {
    @try {
        [self dismissSubModal];
        UIView *ov = [[UIView alloc] initWithFrame:self.bounds];
        ov.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
        UIButton *bgDismiss = [UIButton buttonWithType:UIButtonTypeCustom];
        bgDismiss.frame = ov.bounds;
        [bgDismiss addTarget:self action:@selector(dismissSubModal) forControlEvents:UIControlEventTouchUpInside];
        [ov addSubview:bgDismiss];

        CGFloat mw = MIN(360.0, self.bounds.size.width - 28.0);
        CGFloat mh = MIN(306.0, self.bounds.size.height - 20.0);
        UIView *box = [[UIView alloc] initWithFrame:CGRectMake(floor((self.bounds.size.width - mw)*0.5),
                                                               floor((self.bounds.size.height - mh)*0.5),
                                                               mw, mh)];
        box.backgroundColor = FTC_Color(FTC_C_HEADER);
        box.opaque = YES;
        box.layer.cornerRadius = 14.0;
        box.layer.borderColor = FTC_Color(FTC_C_ORANGE).CGColor;
        box.layer.borderWidth = 1.4;
        [ov addSubview:box];

        UILabel *hdr = [[UILabel alloc] initWithFrame:CGRectMake(14, 10, mw - 50, 20)];
        hdr.text = [self L:@"Bảng Bỏ Vé (Bấm X để trừ 1 vé)" en:@"Ticket Deck (Tap X to Cut -1)"];
        hdr.font = [UIFont boldSystemFontOfSize:13];
        hdr.textColor = FTC_Color(FTC_C_GOLD);
        [box addSubview:hdr];

        UIButton *xClose = [UIButton buttonWithType:UIButtonTypeCustom];
        xClose.frame = CGRectMake(mw - 34, 7, 26, 26);
        [xClose setTitle:@"✕" forState:UIControlStateNormal];
        xClose.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [xClose setTitleColor:FTC_Color(FTC_C_TEXT2) forState:UIControlStateNormal];
        [xClose addTarget:self action:@selector(dismissSubModal) forControlEvents:UIControlEventTouchUpInside];
        [box addSubview:xClose];

        UILabel *st = [[UILabel alloc] initWithFrame:CGRectMake(14, 31, mw - 28, 16)];
        st.font = [UIFont systemFontOfSize:10.5];
        st.textColor = FTC_Color(FTC_C_TEXT2);
        [box addSubview:st];
        self.ticketModalStatus = st;

        self.ticketCountLabels = [NSMutableArray array];
        self.ticketCutButtons = [NSMutableArray array];

        NSArray<NSDictionary *> *rows = @[
            @{@"vi": @"Vé Gãy",            @"en": @"Break Tickets",   @"col": @(FTC_C_RED_HI)},
            @{@"vi": @"Vé Hư hại",         @"en": @"Damage Tickets",  @"col": @(FTC_C_ORANGE)},
            @{@"vi": @"Phiếu Giữ nguyên",  @"en": @"Hold Tickets",    @"col": @(FTC_C_OK)},
            @{@"vi": @"Phiếu Thành công",  @"en": @"Success Tickets", @"col": @(FTC_C_BLUE)},
            @{@"vi": @"Phiếu Đại thành công", @"en": @"Great Tickets", @"col": @(FTC_C_PURPLE_HI)},
        ];
        CGFloat rowH = floor((mh - 60.0) / 5.0) - 5.0;
        rowH = MAX(36.0, MIN(44.0, rowH));
        for (NSInteger i = 0; i < 5; i++) {
            NSDictionary *r = rows[i];
            UIView *rv = [[UIView alloc] initWithFrame:CGRectMake(12, 52 + i * (rowH + 5), mw - 24, rowH)];
            rv.backgroundColor = FTC_Color(FTC_C_CARD);
            rv.opaque = YES;
            rv.layer.cornerRadius = 9.0;
            rv.layer.borderColor = FTC_Color(FTC_C_BORDER).CGColor;
            rv.layer.borderWidth = 1.0;

            UILabel *nameL = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, rv.bounds.size.width - 134, rowH)];
            nameL.text = [self L:r[@"vi"] en:r[@"en"]];
            nameL.font = [UIFont boldSystemFontOfSize:12];
            nameL.textColor = FTC_Color([r[@"col"] unsignedIntValue]);
            [rv addSubview:nameL];

            UILabel *cntL = [[UILabel alloc] initWithFrame:CGRectMake(rv.bounds.size.width - 122, 0, 74, rowH)];
            cntL.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightBold];
            cntL.textColor = FTC_Color(FTC_C_TEXT);
            cntL.textAlignment = NSTextAlignmentRight;
            [rv addSubview:cntL];
            [self.ticketCountLabels addObject:cntL];

            UIButton *cutBtn = [UIButton buttonWithType:UIButtonTypeCustom];
            cutBtn.frame = CGRectMake(rv.bounds.size.width - 40, floor((rowH - 28)*0.5), 32, 28);
            [cutBtn setTitle:@"✕" forState:UIControlStateNormal];
            cutBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
            [cutBtn setTitleColor:FTC_Color(FTC_C_TEXT) forState:UIControlStateNormal];
            cutBtn.backgroundColor = FTC_Color(FTC_C_RED);
            cutBtn.opaque = YES;
            cutBtn.layer.cornerRadius = 7.0;
            cutBtn.tag = i;
            [cutBtn addTarget:self action:@selector(onCutTicketTap:) forControlEvents:UIControlEventTouchUpInside];
            [rv addSubview:cutBtn];
            [self.ticketCutButtons addObject:cutBtn];

            [box addSubview:rv];
        }

        [self addSubview:ov];
        self.subModalOverlay = ov;
        [self refreshTicketCutModal];
    } @catch (...) {}
}

- (void)refreshTicketCutModal {
    int counts[5] = { 9, 2, 5, 12, 2 };
    int cuts[5]   = { 0, 0, 0, 0, 0 };
    FTC_CallResult cr = FTC_GetTicketDeckCounts(counts, cuts);
    if (cr == FTC_CALL_OK) {
        self.ticketModalStatus.text = [self L:@"Số phiếu trực tiếp trong ván hiện tại (tự cập nhật)"
                                           en:@"Live ticket counts in current run"];
        self.ticketModalStatus.textColor = FTC_Color(FTC_C_OK);
    } else {
        self.ticketModalStatus.text = [self L:@"Đang hiện số mặc định — hãy vào màn chơi để trừ vé"
                                           en:@"Showing defaults — enter gameplay to cut tickets"];
        self.ticketModalStatus.textColor = FTC_Color(FTC_C_ORANGE);
    }
    for (NSInteger i = 0; i < 5 && i < (NSInteger)self.ticketCountLabels.count; i++) {
        UILabel *lbl = self.ticketCountLabels[i];
        lbl.text = (cuts[i] > 0)
            ? [NSString stringWithFormat:@"%d  (-%d)", counts[i], cuts[i]]
            : [NSString stringWithFormat:@"%d", counts[i]];
        UIButton *btn = self.ticketCutButtons[i];
        // Note: game clamps Break (index 0) minimum to 1; others go down to 0.
        int floorMin = (i == 0) ? 1 : 0;
        BOOL canCut = (cr == FTC_CALL_OK && counts[i] > floorMin);
        btn.enabled = canCut;
        btn.backgroundColor = canCut ? FTC_Color(FTC_C_RED) : FTC_Color(FTC_C_BTN_OFF);
        [btn setTitleColor:(canCut ? FTC_Color(FTC_C_TEXT) : FTC_Color(FTC_C_TEXT2)) forState:UIControlStateNormal];
    }
}

- (void)onCutTicketTap:(UIButton *)sender {
    @try {
        int outcome = (int)sender.tag;
        FTC_CallResult cr = FTC_CutTicket(outcome);
        if (cr != FTC_CALL_OK) {
            self.ticketModalStatus.text = [self messageForCall:cr];
            self.ticketModalStatus.textColor = FTC_Color(FTC_C_ERR);
        }
        [self refreshTicketCutModal];
    } @catch (...) {}
}

#pragma mark - Timers (#4 Forge Keep-Alive & #10 Auto-Fever Refill)

- (void)syncForgeKeepAliveTimer {
    BOOL need = ([self.switchOn[@(4)] boolValue] && self.forgeModeSelected >= 1);
    if (need && !self.forgeKeepAliveTimer) {
        __weak typeof(self) weakSelf = self;
        self.forgeKeepAliveTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                                   repeats:YES
                                                                     block:^(NSTimer *t) {
            CheatMenuView *s = weakSelf;
            if (!s) { [t invalidate]; return; }
            FTC_KeepForgeModeAlive((int)s.forgeModeSelected);
        }];
    } else if (!need && self.forgeKeepAliveTimer) {
        [self.forgeKeepAliveTimer invalidate];
        self.forgeKeepAliveTimer = nil;
    }
}

- (void)syncAutoFeverTimer {
    BOOL need = [self.switchOn[@(10)] boolValue];
    if (need && !self.autoFeverTimer) {
        self.autoFeverTimer = [NSTimer scheduledTimerWithTimeInterval:0.35
                                                              repeats:YES
                                                                block:^(NSTimer *t) {
            FTC_TickAutoFever();
        }];
    } else if (!need && self.autoFeverTimer) {
        [self.autoFeverTimer invalidate];
        self.autoFeverTimer = nil;
    }
}

#pragma mark - Persistence & Staggered Non-Blocking Startup Restore

- (void)loadSavedPreferences {
    @try {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        self.maximized = [ud boolForKey:kPrefMaximized];
        self.english = [ud boolForKey:kPrefLangEn];
        self.forgeModeSelected = [ud integerForKey:kPrefForgeMode];
        if (self.forgeModeSelected < 0 || self.forgeModeSelected > 3) self.forgeModeSelected = 0;
        self.swordMultIndex = [ud integerForKey:kPrefSwordMult];
        if (self.swordMultIndex < 0 || self.swordMultIndex > 3) self.swordMultIndex = 0;
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

        if ([saved[@"40"] boolValue]) {
            self.switchOn[@(40)] = @(YES);
            [self setStatus:40 text:[self L:@"Đã bật (góc trên trái)" en:@"Enabled (top-left)"] kind:1];
            [self setFpsBadgeVisible:YES];
        }
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
        if ([saved[@"4"] boolValue] && self.forgeModeSelected >= 1) {
            [queue addObject:^{
                CheatMenuView *s = weakSelf;
                if (!s) return;
                if (FTC_SetForgeWinMode((int)s.forgeModeSelected) == FTC_CALL_OK) {
                    s.switchOn[@(4)] = @(YES);
                    [s applyForgeModeStatusText:s.forgeModeSelected];
                    [s syncForgeKeepAliveTimer];
                    [s updateCardInPlace:4];
                }
            }];
        }
        if ([saved[@"10"] boolValue]) {
            [queue addObject:^{
                CheatMenuView *s = weakSelf;
                if (!s) return;
                s.switchOn[@(10)] = @(YES);
                FTC_FillFever();
                [s syncAutoFeverTimer];
                [s setStatus:10 text:[s L:@"Tự nạp đầy Nhập Thần đang bật" en:@"Auto-Refill Fever active"] kind:1];
                [s updateCardInPlace:10];
            }];
        }
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
        if ([saved[@"39"] boolValue]) {
            [queue addObject:^{
                CheatMenuView *s = weakSelf;
                if (!s) return;
                int mult = kSwordMultValues[s.swordMultIndex];
                if (FTC_PatchSwordValueMultiplier(mult) == FTC_PATCH_OK ||
                    FTC_SetSwordValueMultiplierLive((double)mult) == FTC_CALL_OK) {
                    s.switchOn[@(39)] = @(YES);
                    [s setStatus:39 text:[NSString stringWithFormat:@"×%d", mult] kind:1];
                    [s updateCardInPlace:39];
                }
            }];
        }

        for (size_t i = 0; i < kFTC_FeatureCount; i++) {
            const FTC_Feature *f = &kFTC_Features[i];
            if (f->fid == 39) continue;
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
                        [s setStatus:19 text:[s L:@"Đã bật (không cần JIT)" en:@"Enabled (No-JIT)"] kind:1];
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
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(idx * 80 * NSEC_PER_MSEC)),
                           dispatch_get_main_queue(), queue[idx]);
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
                if ([num intValue] == 33 && FTC_ToggleMerchantShelfSlot() == FTC_CALL_OK) {
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
                           dispatch_get_main_queue(), ^{ [weakSelf tryRestorePendingDevToggles]; });
        }
    } @catch (...) {}
}

- (void)onResetAllCheats {
    @try {
        for (size_t i = 0; i < kFTC_FeatureCount; i++) {
            const FTC_Feature *f = &kFTC_Features[i];
            if (f->kind == FTC_KIND_PATCH && [self.switchOn[@(f->fid)] boolValue]) {
                if (f->fid == 39) FTC_PatchSwordValueMultiplier(0);
                else FTC_PatchRemoveFeature(f->fid);
            }
            self.switchOn[@(f->fid)] = @(NO);
            [self setStatus:f->fid text:nil kind:0];
        }
        FTC_SetForgeWinMode(0);
        FTC_SetDragonGodMode(false);
        FTC_SetAntiLag(false);
        FTC_SetTimeScale(1.0f);
        FTC_SetSwordValueMultiplierLive(1.0);
        self.forgeModeSelected = 0;
        self.swordMultIndex = 0;
        self.modeIndex[@(42)] = @(0);
        [self syncForgeKeepAliveTimer];
        [self syncAutoFeverTimer];
        [self setFpsBadgeVisible:NO];

        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud removeObjectForKey:kPrefSwitches];
        [ud removeObjectForKey:kPrefForgeMode];
        [ud removeObjectForKey:kPrefSwordMult];
        [ud removeObjectForKey:kPrefQuality];
        [ud removeObjectForKey:kPrefSpeed];

        [self buildActiveTabCards];
        [self updateActiveCountBadge];
        [self updateTabAppearance];
    } @catch (...) {}
}

#pragma mark - Feature Actions

- (void)onToggleDesc:(UIButton *)sender {
    int fid = (int)sender.tag;
    self.descOpen[@(fid)] = @(![self.descOpen[@(fid)] boolValue]);
    [self refreshCardSubtitle:FTC_FeatureById(fid)];
}

- (void)on3DSwitchChanged:(FTCSwitch3D *)sender {
    @try {
        int fid = (int)sender.tag;
        if ([self isFeatureSpamLocked:fid]) {
            [sender setOn:[self.switchOn[@(fid)] boolValue] animated:YES];
            return;
        }
        BOOL wantOn = ![self.switchOn[@(fid)] boolValue];
        const FTC_Feature *f = FTC_FeatureById(fid);
        if (!f) return;

        // #4: Chế độ rèn kiếm (if no mode picked yet and turning ON -> open picker!)
        if (fid == 4) {
            if (wantOn && self.forgeModeSelected == 0) {
                [sender setOn:NO animated:YES];
                [self onOpenForgeModePicker];
                return;
            }
            int mode = wantOn ? (int)self.forgeModeSelected : 0;
            FTC_CallResult cr = FTC_SetForgeWinMode(mode);
            if (cr == FTC_CALL_OK) {
                self.switchOn[@(4)] = @(wantOn);
                [self saveSwitchState:4 on:wantOn];
                if (wantOn) [self applyForgeModeStatusText:self.forgeModeSelected];
                else [self setStatus:4 text:[self L:@"Đã tắt (tỉ lệ gốc)" en:@"Disabled (normal)"] kind:0];
                [self syncForgeKeepAliveTimer];
            } else {
                [self setStatus:4 text:[self messageForCall:cr] kind:2];
            }
            [self updateCardInPlace:4];
            return;
        }

        // #10: Kích hoạt Nhập Thần vô hạn (0 JIT, instant auto-refill when Fever ends!)
        if (fid == 10) {
            self.switchOn[@(10)] = @(wantOn);
            [self saveSwitchState:10 on:wantOn];
            if (wantOn) {
                FTC_FillFever();
                [self setStatus:10 text:[self L:@"Đang tự động nạp đầy Nhập Thần liên tục" en:@"Auto-refilling Fever continuously"] kind:1];
            } else {
                [self setStatus:10 text:[self L:@"Đã tắt" en:@"Disabled"] kind:0];
            }
            [self syncAutoFeverTimer];
            [self updateCardInPlace:10];
            return;
        }

        // #39: Giá trị của kiếm (x10 / x20 / x30 / x40)
        if (fid == 39) {
            int mult = wantOn ? kSwordMultValues[self.swordMultIndex] : 0;
            FTC_PatchResult pr = FTC_PatchSwordValueMultiplier(mult);
            if (pr == FTC_PATCH_OK) {
                self.switchOn[@(39)] = @(wantOn);
                [self saveSwitchState:39 on:wantOn];
                [self setStatus:39
                           text:(wantOn ? [NSString stringWithFormat:[self L:@"Đang bật ×%d" en:@"Active ×%d"], mult]
                                        : [self L:@"Đã tắt" en:@"Disabled"])
                           kind:(wantOn ? 1 : 0)];
                [self updateCardInPlace:39];
            } else if (pr == FTC_PATCH_ERR_NO_JIT) {
                // Try direct live effects.multiplier fallback when on anvil
                FTC_CallResult cr = FTC_SetSwordValueMultiplierLive(wantOn ? (double)mult : 1.0);
                if (cr == FTC_CALL_OK) {
                    self.switchOn[@(39)] = @(wantOn);
                    [self saveSwitchState:39 on:wantOn];
                    [self setStatus:39
                               text:(wantOn ? [NSString stringWithFormat:[self L:@"Đã nhân ×%d (kiếm trên đe)" en:@"Applied ×%d (anvil sword)"], mult]
                                            : [self L:@"Đã tắt" en:@"Disabled"])
                               kind:(wantOn ? 1 : 0)];
                    [self updateCardInPlace:39];
                } else {
                    [self triggerJitLockedFeedbackForFeature:39];
                }
            } else {
                [self setStatus:39 text:[self messageForPatch:pr] kind:2];
                [self updateCardInPlace:39];
            }
            return;
        }

        // #40: Top-left FPS badge
        if (fid == 40) {
            self.switchOn[@(40)] = @(wantOn);
            [self saveSwitchState:40 on:wantOn];
            [self setStatus:40 text:(wantOn ? [self L:@"Đã bật (góc trên trái)" en:@"Enabled (top-left)"] : [self L:@"Đã tắt" en:@"Disabled"]) kind:(wantOn ? 1 : 0)];
            [self setFpsBadgeVisible:wantOn];
            [self updateCardInPlace:40];
            return;
        }

        // #7: Dragon God Mode
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

        // #19: Dragon Invulnerable (auto-fallback to IL2CPP GodMode if no JIT!)
        if (fid == 19) {
            FTC_PatchResult pr = wantOn ? FTC_PatchApplyFeature(19) : FTC_PatchRemoveFeature(19);
            if (pr == FTC_PATCH_OK) {
                self.switchOn[@(19)] = @(wantOn);
                [self saveSwitchState:19 on:wantOn];
                [self setStatus:19 text:(wantOn ? [self L:@"Đã bật" en:@"Enabled"] : [self L:@"Đã tắt" en:@"Disabled"]) kind:(wantOn ? 1 : 0)];
                [self updateCardInPlace:19];
            } else if (pr == FTC_PATCH_ERR_NO_JIT && FTC_SetDragonGodMode(wantOn) == FTC_CALL_OK) {
                self.switchOn[@(19)] = @(wantOn);
                [self saveSwitchState:19 on:wantOn];
                [self setStatus:19 text:(wantOn ? [self L:@"Đã bật (không cần JIT)" en:@"Enabled (No-JIT)"] : [self L:@"Đã tắt" en:@"Disabled"]) kind:(wantOn ? 1 : 0)];
                [self updateCardInPlace:19];
            } else if (pr == FTC_PATCH_ERR_NO_JIT) {
                [self triggerJitLockedFeedbackForFeature:19];
            } else {
                [self setStatus:19 text:[self messageForPatch:pr] kind:2];
                [self updateCardInPlace:19];
            }
            return;
        }

        // Standard runtime __TEXT patches (with shake + anti-spam lock when JIT missing!)
        if (f->kind == FTC_KIND_PATCH) {
            FTC_PatchResult r = wantOn ? FTC_PatchApplyFeature(fid) : FTC_PatchRemoveFeature(fid);
            if (r == FTC_PATCH_OK) {
                self.switchOn[@(fid)] = @(wantOn);
                [self saveSwitchState:fid on:wantOn];
                [self setStatus:fid text:(wantOn ? [self L:@"Đã bật" en:@"Enabled"] : [self L:@"Đã tắt" en:@"Disabled"]) kind:(wantOn ? 1 : 0)];
                [self updateCardInPlace:fid];
            } else if (r == FTC_PATCH_ERR_NO_JIT) {
                [self triggerJitLockedFeedbackForFeature:fid];
            } else {
                [self setStatus:fid text:[self messageForPatch:r] kind:2];
                [self updateCardInPlace:fid];
            }
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
            [alert addAction:[UIAlertAction actionWithTitle:[self L:@"Hủy" en:@"Cancel"] style:UIAlertActionStyleCancel handler:nil]];
            __weak typeof(self) weakSelf = self;
            [alert addAction:[UIAlertAction actionWithTitle:[self L:@"Đặt lại" en:@"Reset"] style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
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

        // #39: Sword value multiplier selector (x10 / x20 / x30 / x40)
        if (fid == 39) {
            if (idx < 0 || idx > 3) idx = 0;
            self.swordMultIndex = idx;
            [[NSUserDefaults standardUserDefaults] setInteger:idx forKey:kPrefSwordMult];
            [self updatePillGroup:39 selectedIndex:idx];
            if ([self.switchOn[@(39)] boolValue]) {
                int mult = kSwordMultValues[idx];
                if (FTC_PatchSwordValueMultiplier(mult) == FTC_PATCH_OK ||
                    FTC_SetSwordValueMultiplierLive((double)mult) == FTC_CALL_OK) {
                    [self setStatus:39 text:[NSString stringWithFormat:[self L:@"Đang bật ×%d" en:@"Active ×%d"], mult] kind:1];
                }
                [self updateCardInPlace:39];
            }
            return;
        }

        // #43: Language switcher
        if (fid == 43) {
            BOOL wantEn = (idx == 1);
            if (wantEn == self.english) return;
            self.english = wantEn;
            self.modeIndex[@(43)] = @(idx);
            [[NSUserDefaults standardUserDefaults] setBool:wantEn forKey:kPrefLangEn];
            [self.statusText removeAllObjects];
            [self.statusKind removeAllObjects];
            [self updateActiveCountBadge];
            [self updateTabAppearance];
            [self buildActiveTabCards];
            return;
        }

        if (fid == 12) {
            self.modeIndex[@(12)] = @(idx);
            [self updatePillGroup:12 selectedIndex:idx];
            return;
        }

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

// #6 Direct keyboard input clamped live 0..999
- (void)onGradeTextChanged:(UITextField *)tf {
    @try {
        NSString *digits = [[tf.text componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]] componentsJoinedByString:@""];
        NSInteger v = [digits integerValue];
        if (v > 999) v = 999;
        if (v < 0) v = 0;
        self.stepValue[@(6)] = @(v);
        if (digits.length > 0 && ![tf.text isEqualToString:[NSString stringWithFormat:@"%ld", (long)v]]) {
            tf.text = [NSString stringWithFormat:@"%ld", (long)v];
        }
    } @catch (...) {}
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)onStepDelta:(UIButton *)sender {
    @try {
        int fid = (int)(sender.tag / 10);
        BOOL isPlus = ((sender.tag % 10) == 1);
        NSInteger cur = [self.stepValue[@(fid)] integerValue];
        NSInteger next = cur + (isPlus ? 1 : -1);
        if (next < 1) next = 1;
        if (next > 24) next = 24;
        self.stepValue[@(fid)] = @(next);
        UILabel *val = self.stepValMap[@(fid)];
        if (val) val.text = [NSString stringWithFormat:@"%ld", (long)next];
    } @catch (...) {}
}

- (void)onStepApply:(UIButton *)sender {
    @try {
        [self endEditing:YES];
        int fid = (int)sender.tag;
        if (fid == 6 && self.gradeTextField) {
            NSInteger v = [self.gradeTextField.text integerValue];
            if (v < 0) v = 0;
            if (v > 999) v = 999;
            self.stepValue[@(6)] = @(v);
            self.gradeTextField.text = [NSString stringWithFormat:@"%ld", (long)v];
        }
        NSInteger v = [self.stepValue[@(fid)] integerValue];
        FTC_CallResult cr = (fid == 6) ? FTC_SetAnvilGrade((int)v) : FTC_JumpToDay((int)v);
        [self setStatus:fid
                   text:(cr == FTC_CALL_OK)
                        ? [NSString stringWithFormat:[self L:@"Đã áp dụng (%ld)" en:@"Applied (%ld)"], (long)v]
                        : [self messageForCall:cr]
                   kind:(cr == FTC_CALL_OK) ? 1 : 2];
        [self updateCardInPlace:fid];
    } @catch (...) {}
}

#pragma mark - Red-Orange-Black Fire Welcome Popup + JIT Status/Guide + MoMo QR + Save Photo

- (void)showWelcomePopup {
    @try {
        if (self.welcomeOverlay) return;
        if (self.bounds.size.width < 120 || self.bounds.size.height < 120) return;

        BOOL jitOn = FTC_PatchCanModifyCode();

        UIView *overlay = [[UIView alloc] initWithFrame:self.bounds];
        overlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.66];
        overlay.alpha = 0.0;
        [self addSubview:overlay];
        self.welcomeOverlay = overlay;

        UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
        card.backgroundColor = FTC_Color(0x0E0807);
        card.opaque = YES;
        card.layer.cornerRadius = 16.0;
        card.layer.borderColor = FTC_Color(FTC_C_ORANGE).CGColor;
        card.layer.borderWidth = 1.4;
        card.layer.masksToBounds = YES;
        [overlay addSubview:card];
        self.welcomeCard = card;

        // ---- 1. Main Welcome Box ----
        UIView *mainBox = [[UIView alloc] initWithFrame:CGRectZero];
        mainBox.backgroundColor = FTC_Color(0x0E0807);
        mainBox.opaque = YES;
        [card addSubview:mainBox];
        self.welcomeMainBox = mainBox;

        // Top Fire Titlebar
        UIView *tbar = [[UIView alloc] initWithFrame:CGRectZero];
        tbar.backgroundColor = FTC_Color(0x190C09);
        tbar.opaque = YES;
        tbar.tag = 5001;
        [mainBox addSubview:tbar];

        uint32_t dotHex[3] = { 0xFF5F56, 0xFFBD2E, 0x27C93F };
        for (NSInteger d = 0; d < 3; d++) {
            UIButton *dot = [UIButton buttonWithType:UIButtonTypeCustom];
            dot.frame = CGRectMake(12 + d * 16, 10, 10, 10);
            dot.backgroundColor = FTC_Color(dotHex[d]);
            dot.layer.cornerRadius = 5.0;
            if (d == 0) [dot addTarget:self action:@selector(onCloseWelcomePopup) forControlEvents:UIControlEventTouchUpInside];
            [tbar addSubview:dot];
        }

        UILabel *tabChip = [[UILabel alloc] initWithFrame:CGRectMake(68, 5, 160, 20)];
        tabChip.text = @"FORGE TAXX  •  MOD MENU";
        tabChip.font = [UIFont boldSystemFontOfSize:10.0];
        tabChip.textColor = FTC_Color(FTC_C_GOLD);
        tabChip.backgroundColor = FTC_Color(0x2D130D);
        tabChip.opaque = YES;
        tabChip.textAlignment = NSTextAlignmentCenter;
        tabChip.layer.cornerRadius = 6.0;
        tabChip.layer.masksToBounds = YES;
        [tbar addSubview:tabChip];

        UILabel *onlinePill = [[UILabel alloc] initWithFrame:CGRectZero];
        onlinePill.text = @"● ONLINE • OPEN SOURCE";
        onlinePill.font = [UIFont monospacedDigitSystemFontOfSize:9.0 weight:UIFontWeightBold];
        onlinePill.textColor = FTC_Color(0x6EE7B7);
        onlinePill.backgroundColor = FTC_Color(0x0E291C);
        onlinePill.opaque = YES;
        onlinePill.textAlignment = NSTextAlignmentCenter;
        onlinePill.layer.cornerRadius = 9.0;
        onlinePill.layer.masksToBounds = YES;
        onlinePill.tag = 5002;
        [tbar addSubview:onlinePill];

        // 3-Color Fire-Gradient Hero Title ("FORGE TAXX")
        UIView *heroTitle = [self makeFireGradientTitle:@"FORGE TAXX"
                                                   font:[UIFont boldSystemFontOfSize:24.0]
                                                  frame:CGRectMake(0, 0, 260, 28)];
        heroTitle.tag = 5004;
        [mainBox addSubview:heroTitle];

        // Tagline ("Vọc vạch game")
        UILabel *heroSub = [[UILabel alloc] initWithFrame:CGRectZero];
        heroSub.text = [self L:@"Tối ưu trải nghiệm Cheat Game & Vọc vạch game mượt mà, mã nguồn mở minh bạch."
                            en:@"Smooth Game Cheat & Tinkering suite — free & transparent open source."];
        heroSub.font = [UIFont systemFontOfSize:11.0];
        heroSub.textColor = FTC_Color(FTC_C_TEXT2);
        heroSub.textAlignment = NSTextAlignmentCenter;
        heroSub.numberOfLines = 1;
        heroSub.adjustsFontSizeToFitWidth = YES;
        heroSub.minimumScaleFactor = 0.8;
        heroSub.tag = 5005;
        [mainBox addSubview:heroSub];

        // Live JIT Status Strip (Red + Explanation + Guide button OR Green + All Unlocked)
        UIView *jitBar = [[UIView alloc] initWithFrame:CGRectZero];
        jitBar.backgroundColor = jitOn ? FTC_Color(0x0F2618) : FTC_Color(0x2B100E);
        jitBar.opaque = YES;
        jitBar.layer.cornerRadius = 9.0;
        jitBar.layer.borderColor = jitOn ? FTC_Color(FTC_C_OK).CGColor : FTC_Color(FTC_C_RED_HI).CGColor;
        jitBar.layer.borderWidth = 1.0;
        jitBar.tag = 5010;
        [mainBox addSubview:jitBar];

        UILabel *jitBadge = [[UILabel alloc] initWithFrame:CGRectZero];
        jitBadge.text = jitOn ? [self L:@"● ĐÃ MỞ JIT" en:@"● JIT ACTIVE"]
                              : [self L:@"● KHÔNG MỞ BẰNG JIT" en:@"● JIT NOT ENABLED"];
        jitBadge.font = [UIFont boldSystemFontOfSize:10.0];
        jitBadge.textColor = jitOn ? FTC_Color(FTC_C_OK) : FTC_Color(FTC_C_RED_HI);
        jitBadge.tag = 1;
        [jitBar addSubview:jitBadge];

        UILabel *jitDesc = [[UILabel alloc] initWithFrame:CGRectZero];
        jitDesc.text = jitOn
            ? [self L:@"Đã mở khóa toàn bộ tính năng!" en:@"All features unlocked!"]
            : [self L:@"Một vài tính năng sẽ tạm khóa đến khi mở JIT." en:@"Some patches stay locked until JIT is enabled."];
        jitDesc.font = [UIFont systemFontOfSize:10.0];
        jitDesc.textColor = FTC_Color(FTC_C_TEXT);
        jitDesc.adjustsFontSizeToFitWidth = YES;
        jitDesc.minimumScaleFactor = 0.78;
        jitDesc.tag = 2;
        [jitBar addSubview:jitDesc];

        if (!jitOn) {
            UIButton *guideBtn = [UIButton buttonWithType:UIButtonTypeCustom];
            [guideBtn setTitle:[self L:@"Hướng dẫn ▸" en:@"Guide ▸"] forState:UIControlStateNormal];
            guideBtn.titleLabel.font = [UIFont boldSystemFontOfSize:10.5];
            [guideBtn setTitleColor:FTC_Color(FTC_C_GOLD) forState:UIControlStateNormal];
            guideBtn.backgroundColor = FTC_Color(0x3D1710);
            guideBtn.opaque = YES;
            guideBtn.layer.cornerRadius = 6.0;
            guideBtn.layer.borderColor = FTC_Color(FTC_C_ORANGE).CGColor;
            guideBtn.layer.borderWidth = 1.0;
            guideBtn.tag = 3;
            [guideBtn addTarget:self action:@selector(onShowJitGuide) forControlEvents:UIControlEventTouchUpInside];
            [jitBar addSubview:guideBtn];
        }

        // 3 Social Action Cards with Official Drawn Vector Logos (Discord, GitHub, TikTok)
        NSArray<NSDictionary *> *socials = @[
            @{@"title": [self L:@"Tham Gia Discord" en:@"Join Discord"],
              @"sub":   [self L:@"Cộng đồng & hỗ trợ" en:@"Community & support"],
              @"bg":    @(0x1B1733), @"bd": @(FTC_C_DISCORD), @"ac": @(0x9BA9FF), @"tag": @(1)},
            @{@"title": [self L:@"Xem Mã Nguồn" en:@"Source Code"],
              @"sub":   [self L:@"Mã nguồn mở GitHub" en:@"Open source GitHub"],
              @"bg":    @(0x1B1312), @"bd": @(0x7A6864),      @"ac": @(0xF5ECEE), @"tag": @(2)},
            @{@"title": @"TikTok",
              @"sub":   [self L:@"Kênh chính chủ" en:@"Official channel"],
              @"bg":    @(0x241118), @"bd": @(FTC_C_TIKTOK_HI), @"ac": @(0x25F4EE), @"tag": @(3)},
        ];
        for (NSInteger i = 0; i < 3; i++) {
            NSDictionary *s = socials[i];
            UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
            btn.backgroundColor = FTC_Color([s[@"bg"] unsignedIntValue]);
            btn.opaque = YES;
            btn.layer.cornerRadius = 11.0;
            btn.layer.borderColor = FTC_Color([s[@"bd"] unsignedIntValue]).CGColor;
            btn.layer.borderWidth = 1.2;
            btn.tag = 5100 + [s[@"tag"] integerValue];
            [btn addTarget:self action:@selector(onOpenExternalLink:) forControlEvents:UIControlEventTouchUpInside];

            UIView *ico = (i == 0) ? FTC_MakeDiscordLogo(24.0)
                        : (i == 1) ? FTC_MakeGitHubLogo(24.0)
                                   : FTC_MakeTikTokLogo(24.0);
            ico.tag = 3;
            [btn addSubview:ico];

            UILabel *tl = [[UILabel alloc] initWithFrame:CGRectZero];
            tl.text = s[@"title"];
            tl.font = [UIFont boldSystemFontOfSize:11.5];
            tl.textColor = FTC_Color([s[@"ac"] unsignedIntValue]);
            tl.adjustsFontSizeToFitWidth = YES;
            tl.minimumScaleFactor = 0.8;
            tl.userInteractionEnabled = NO;
            tl.tag = 1;
            [btn addSubview:tl];

            UILabel *sl = [[UILabel alloc] initWithFrame:CGRectZero];
            sl.text = s[@"sub"];
            sl.font = [UIFont systemFontOfSize:9.5];
            sl.textColor = FTC_Color(FTC_C_TEXT2);
            sl.userInteractionEnabled = NO;
            sl.tag = 2;
            [btn addSubview:sl];

            [mainBox addSubview:btn];
        }

        // Bottom Row: [ ♥ Ủng hộ (QR MoMo) ] + [ Tiếp tục vào game → ]
        UIButton *donateBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        [donateBtn setTitle:[self L:@"♥  Ủng hộ (QR MoMo)" en:@"♥  Donate (MoMo QR)"] forState:UIControlStateNormal];
        donateBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
        [donateBtn setTitleColor:FTC_Color(0xFFFFFF) forState:UIControlStateNormal];
        donateBtn.backgroundColor = FTC_Color(FTC_C_MOMO);
        donateBtn.opaque = YES;
        donateBtn.layer.cornerRadius = 10.0;
        donateBtn.layer.borderColor = FTC_Color(FTC_C_MOMO_HI).CGColor;
        donateBtn.layer.borderWidth = 1.0;
        donateBtn.tag = 5006;
        [donateBtn addTarget:self action:@selector(onShowDonateQr) forControlEvents:UIControlEventTouchUpInside];
        [mainBox addSubview:donateBtn];

        UIButton *continueBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        [continueBtn setTitle:[self L:@"Tiếp tục vào game  →" en:@"Continue to Game  →"] forState:UIControlStateNormal];
        continueBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12.5];
        [continueBtn setTitleColor:FTC_Color(0xFFFFFF) forState:UIControlStateNormal];
        continueBtn.backgroundColor = FTC_Color(FTC_C_RED);
        continueBtn.opaque = YES;
        continueBtn.layer.cornerRadius = 10.0;
        continueBtn.layer.borderColor = FTC_Color(FTC_C_ORANGE).CGColor;
        continueBtn.layer.borderWidth = 1.0;
        continueBtn.tag = 5007;
        [continueBtn addTarget:self action:@selector(onCloseWelcomePopup) forControlEvents:UIControlEventTouchUpInside];
        [mainBox addSubview:continueBtn];

        // ---- 2. QR Donate View (with "Lưu ảnh QR" button!) ----
        UIView *qrBox = [[UIView alloc] initWithFrame:CGRectZero];
        qrBox.backgroundColor = FTC_Color(0xFFF0F7);
        qrBox.opaque = YES;
        qrBox.hidden = YES;
        [card addSubview:qrBox];
        self.welcomeQrBox = qrBox;

        UIImageView *qrImg = [[UIImageView alloc] initWithFrame:CGRectZero];
        qrImg.contentMode = UIViewContentModeScaleAspectFit;
        qrImg.backgroundColor = FTC_Color(0xFFF0F7);
        qrImg.opaque = YES;
        qrImg.tag = 5201;
        [qrBox addSubview:qrImg];

        UIButton *saveQrBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        [saveQrBtn setTitle:[self L:@"Lưu ảnh QR" en:@"Save QR Image"] forState:UIControlStateNormal];
        [saveQrBtn setImage:[self sfIcon:@"square.and.arrow.down.fill" size:12.0 color:FTC_Color(0xFFFFFF)] forState:UIControlStateNormal];
        saveQrBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11.5];
        [saveQrBtn setTitleColor:FTC_Color(0xFFFFFF) forState:UIControlStateNormal];
        saveQrBtn.backgroundColor = FTC_Color(FTC_C_OK);
        saveQrBtn.opaque = YES;
        saveQrBtn.layer.cornerRadius = 9.0;
        saveQrBtn.tag = 5204;
        [saveQrBtn addTarget:self action:@selector(onSaveQrImage) forControlEvents:UIControlEventTouchUpInside];
        [qrBox addSubview:saveQrBtn];
        self.saveQrButton = saveQrBtn;

        UIButton *backBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        [backBtn setTitle:[self L:@"←  Quay lại" en:@"←  Back"] forState:UIControlStateNormal];
        backBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11.5];
        [backBtn setTitleColor:FTC_Color(0xFFFFFF) forState:UIControlStateNormal];
        backBtn.backgroundColor = FTC_Color(0x2B1410);
        backBtn.opaque = YES;
        backBtn.layer.cornerRadius = 9.0;
        backBtn.tag = 5202;
        [backBtn addTarget:self action:@selector(onBackFromWelcomeSub) forControlEvents:UIControlEventTouchUpInside];
        [qrBox addSubview:backBtn];

        UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        [doneBtn setTitle:[self L:@"Vào game" en:@"Enter Game"] forState:UIControlStateNormal];
        doneBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11.5];
        [doneBtn setTitleColor:FTC_Color(0xFFFFFF) forState:UIControlStateNormal];
        doneBtn.backgroundColor = FTC_Color(FTC_C_MOMO);
        doneBtn.opaque = YES;
        doneBtn.layer.cornerRadius = 9.0;
        doneBtn.tag = 5203;
        [doneBtn addTarget:self action:@selector(onCloseWelcomePopup) forControlEvents:UIControlEventTouchUpInside];
        [qrBox addSubview:doneBtn];

        // ---- 3. Colored Step-by-Step JIT Guide View ----
        UIView *jitBox = [[UIView alloc] initWithFrame:CGRectZero];
        jitBox.backgroundColor = FTC_Color(0x120A09);
        jitBox.opaque = YES;
        jitBox.hidden = YES;
        [card addSubview:jitBox];
        self.welcomeJitGuideBox = jitBox;

        UILabel *gTitle = [[UILabel alloc] initWithFrame:CGRectZero];
        gTitle.text = [self L:@"HƯỚNG DẪN MỞ GAME BẰNG JIT (MỞ KHÓA 100%)"
                           en:@"HOW TO ENABLE JIT (UNLOCK 100% FEATURES)"];
        gTitle.font = [UIFont boldSystemFontOfSize:13.0];
        gTitle.textColor = FTC_Color(FTC_C_GOLD);
        gTitle.tag = 5301;
        [jitBox addSubview:gTitle];

        NSArray<NSDictionary *> *steps = @[
            @{@"step": [self L:@"BƯỚC 1" en:@"STEP 1"], @"ico": @"app.badge.checkmark.fill", @"col": @(FTC_C_ORANGE),
              @"vi": @"Mở TrollStore (hoặc công cụ hỗ trợ JIT như StikDebug / SideJITServer).",
              @"en": @"Open TrollStore (or a JIT enabler tool like StikDebug / SideJITServer)."},
            @{@"step": [self L:@"BƯỚC 2" en:@"STEP 2"], @"ico": @"hand.tap.fill", @"col": @(FTC_C_RED_HI),
              @"vi": @"Nhấn giữ (hoặc chạm) vào biểu tượng game ForgeTaz trong danh sách ứng dụng.",
              @"en": @"Long-press (or tap) the ForgeTaz app in your installed apps list."},
            @{@"step": [self L:@"BƯỚC 3" en:@"STEP 3"], @"ico": @"bolt.fill", @"col": @(FTC_C_GOLD),
              @"vi": @"Chọn \"Open with JIT\" — game sẽ khởi chạy kèm quyền bộ nhớ đầy đủ.",
              @"en": @"Select \"Open with JIT\" — the game will launch with full memory rights."},
            @{@"step": [self L:@"BƯỚC 4" en:@"STEP 4"], @"ico": @"checkmark.seal.fill", @"col": @(FTC_C_OK),
              @"vi": @"Trạng thái sẽ chuyển xanh \"ĐÃ MỞ JIT\" và mở khóa toàn bộ 100% tính năng!",
              @"en": @"Status turns green \"JIT ACTIVE\" and unlocks 100% of all cheat features!"},
        ];
        for (NSInteger i = 0; i < 4; i++) {
            NSDictionary *st = steps[i];
            UIColor *sc = FTC_Color([st[@"col"] unsignedIntValue]);
            UIView *row = [[UIView alloc] initWithFrame:CGRectZero];
            row.backgroundColor = FTC_Color(FTC_C_CARD);
            row.opaque = YES;
            row.layer.cornerRadius = 9.0;
            row.layer.borderColor = sc.CGColor;
            row.layer.borderWidth = 1.0;
            row.tag = 5310 + i;

            UIImageView *siv = [[UIImageView alloc] initWithFrame:CGRectMake(8, 10, 18, 18)];
            siv.image = [self sfIcon:st[@"ico"] size:14.0 color:sc];
            siv.contentMode = UIViewContentModeScaleAspectFit;
            [row addSubview:siv];

            UILabel *sb = [[UILabel alloc] initWithFrame:CGRectMake(30, 9, 54, 20)];
            sb.text = st[@"step"];
            sb.font = [UIFont boldSystemFontOfSize:10.0];
            sb.textColor = sc;
            sb.backgroundColor = FTC_Color(0x28130E);
            sb.opaque = YES;
            sb.textAlignment = NSTextAlignmentCenter;
            sb.layer.cornerRadius = 5.0;
            sb.layer.masksToBounds = YES;
            [row addSubview:sb];

            UILabel *stxt = [[UILabel alloc] initWithFrame:CGRectZero];
            stxt.text = [self L:st[@"vi"] en:st[@"en"]];
            stxt.font = [UIFont systemFontOfSize:11.0];
            stxt.textColor = FTC_Color(FTC_C_TEXT);
            stxt.numberOfLines = 2;
            stxt.tag = 1;
            [row addSubview:stxt];

            [jitBox addSubview:row];
        }

        UIButton *gBack = [UIButton buttonWithType:UIButtonTypeCustom];
        [gBack setTitle:[self L:@"←  Quay lại" en:@"←  Back"] forState:UIControlStateNormal];
        gBack.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
        [gBack setTitleColor:FTC_Color(0xFFFFFF) forState:UIControlStateNormal];
        gBack.backgroundColor = FTC_Color(FTC_C_RED);
        gBack.opaque = YES;
        gBack.layer.cornerRadius = 9.0;
        gBack.tag = 5302;
        [gBack addTarget:self action:@selector(onBackFromWelcomeSub) forControlEvents:UIControlEventTouchUpInside];
        [jitBox addSubview:gBack];

        [self layoutWelcomeOverlay];

        card.transform = CGAffineTransformMakeScale(0.94, 0.94);
        [UIView animateWithDuration:0.20 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            overlay.alpha = 1.0;
            card.transform = CGAffineTransformIdentity;
        } completion:nil];
    } @catch (...) {}
}

- (void)layoutWelcomeOverlay {
    if (!self.welcomeOverlay || !self.welcomeCard) return;
    self.welcomeOverlay.frame = self.bounds;
    UIEdgeInsets safe = [self ftcSafeInsets];
    CGFloat availW = MAX(300.0, self.bounds.size.width - safe.left - safe.right);
    CGFloat availH = MAX(240.0, self.bounds.size.height - safe.top - safe.bottom);

    CGFloat cw = MIN(544.0, availW - 10.0);
    CGFloat ch = MIN(314.0, availH - 6.0);
    CGFloat cx = safe.left + floor((availW - cw) * 0.5);
    CGFloat cy = safe.top + floor((availH - ch) * 0.5);
    self.welcomeCard.frame = CGRectMake(cx, cy, floor(cw), floor(ch));
    self.welcomeMainBox.frame = self.welcomeCard.bounds;
    self.welcomeQrBox.frame = self.welcomeCard.bounds;
    self.welcomeJitGuideBox.frame = self.welcomeCard.bounds;

    CGFloat W = self.welcomeCard.bounds.size.width;
    CGFloat H = self.welcomeCard.bounds.size.height;
    CGFloat padX = 14.0;

    // 1. Main Welcome Layout
    UIView *tbar = [self.welcomeMainBox viewWithTag:5001];
    tbar.frame = CGRectMake(0, 0, W, 30.0);
    [tbar viewWithTag:5002].frame = CGRectMake(W - 150.0, 5.0, 140.0, 20.0);

    UIView *heroTitle = [self.welcomeMainBox viewWithTag:5004];
    heroTitle.frame = CGRectMake(floor((W - 260.0) * 0.5), 36.0, 260.0, 28.0);
    [self.welcomeMainBox viewWithTag:5005].frame = CGRectMake(16.0, 66.0, W - 32.0, 18.0);

    // JIT Status Bar
    UIView *jitBar = [self.welcomeMainBox viewWithTag:5010];
    jitBar.frame = CGRectMake(padX, 90.0, W - padX * 2.0, 34.0);
    CGFloat jW = jitBar.bounds.size.width;
    UIView *guideBtn = [jitBar viewWithTag:3];
    CGFloat guideW = guideBtn ? 84.0 : 0.0;
    [jitBar viewWithTag:1].frame = CGRectMake(10.0, 0, 134.0, 34.0);
    [jitBar viewWithTag:2].frame = CGRectMake(144.0, 0, MAX(60.0, jW - 152.0 - guideW), 34.0);
    if (guideBtn) guideBtn.frame = CGRectMake(jW - guideW - 6.0, 5.0, guideW, 24.0);

    // 3 Social Cards
    CGFloat gap = 8.0;
    CGFloat cardW = floor((W - padX * 2.0 - gap * 2.0) / 3.0);
    CGFloat cardH = 58.0;
    CGFloat cardY = floor(H - 114.0);
    for (NSInteger i = 0; i < 3; i++) {
        UIView *b = [self.welcomeMainBox viewWithTag:5101 + i];
        b.frame = CGRectMake(padX + i * (cardW + gap), cardY, cardW, cardH);
        [b viewWithTag:3].frame = CGRectMake(10, floor((cardH - 24.0)*0.5), 24, 24);
        [b viewWithTag:1].frame = CGRectMake(40, 11, cardW - 46, 18);
        [b viewWithTag:2].frame = CGRectMake(40, 31, cardW - 46, 15);
    }

    // Bottom Buttons
    CGFloat btnY = H - 46.0;
    CGFloat btnW = floor((W - padX * 2.0 - 10.0) * 0.5);
    [self.welcomeMainBox viewWithTag:5006].frame = CGRectMake(padX, btnY, btnW, 34.0);
    [self.welcomeMainBox viewWithTag:5007].frame = CGRectMake(padX + btnW + 10.0, btnY, btnW, 34.0);

    // 2. QR Donate Layout (QR left + 3 buttons right: Save QR, Back, Enter Game)
    CGFloat qrAreaH = H - 16.0;
    CGFloat qrW = MIN(W - 158.0, qrAreaH * 0.94);
    [self.welcomeQrBox viewWithTag:5201].frame = CGRectMake(12.0, 8.0, floor(qrW), floor(qrAreaH));
    CGFloat sideX = 12.0 + floor(qrW) + 12.0;
    CGFloat sideW = MAX(112.0, W - sideX - 12.0);
    CGFloat midY = floor(H * 0.5);
    [self.welcomeQrBox viewWithTag:5204].frame = CGRectMake(sideX, midY - 58.0, sideW, 34.0);
    [self.welcomeQrBox viewWithTag:5202].frame = CGRectMake(sideX, midY - 17.0, sideW, 34.0);
    [self.welcomeQrBox viewWithTag:5203].frame = CGRectMake(sideX, midY + 24.0, sideW, 34.0);

    // 3. JIT Guide Layout
    [self.welcomeJitGuideBox viewWithTag:5301].frame = CGRectMake(14.0, 12.0, W - 28.0, 20.0);
    CGFloat sRowH = floor((H - 86.0) / 4.0) - 5.0;
    sRowH = MAX(36.0, MIN(48.0, sRowH));
    for (NSInteger i = 0; i < 4; i++) {
        UIView *r = [self.welcomeJitGuideBox viewWithTag:5310 + i];
        r.frame = CGRectMake(14.0, 38.0 + i * (sRowH + 5.0), W - 28.0, sRowH);
        [r viewWithTag:1].frame = CGRectMake(92.0, 2.0, r.bounds.size.width - 100.0, sRowH - 4.0);
    }
    [self.welcomeJitGuideBox viewWithTag:5302].frame = CGRectMake(floor((W - 140.0)*0.5), H - 40.0, 140.0, 30.0);
}

- (void)onOpenExternalLink:(UIButton *)sender {
    @try {
        NSString *urlStr = nil;
        if (sender.tag == 5101) urlStr = @"https://discord.gg/FqZzJJcM4";
        else if (sender.tag == 5102) urlStr = @"https://github.com/duyzoz/ForgeTax-Mobile-Cheat";
        else if (sender.tag == 5103) urlStr = @"https://www.tiktok.com/@duyzoz";
        if (!urlStr) return;
        NSURL *url = [NSURL URLWithString:urlStr];
        if (!url) return;
        self.returningFromExternalLink = YES;
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    } @catch (...) {}
}

- (void)onShowDonateQr {
    @try {
        UIImageView *qrImg = (UIImageView *)[self.welcomeQrBox viewWithTag:5201];
        if (qrImg && !qrImg.image) {
            NSData *qrData = [NSData dataWithBytesNoCopy:(void *)kFTC_DonateQrData
                                                  length:kFTC_DonateQrSize
                                            freeWhenDone:NO];
            qrImg.image = [UIImage imageWithData:qrData];
        }
        [self.saveQrButton setTitle:[self L:@"Lưu ảnh QR" en:@"Save QR Image"] forState:UIControlStateNormal];
        self.saveQrButton.backgroundColor = FTC_Color(FTC_C_OK);
        self.welcomeMainBox.hidden = YES;
        self.welcomeJitGuideBox.hidden = YES;
        self.welcomeQrBox.hidden = NO;
    } @catch (...) {}
}

- (void)onSaveQrImage {
    @try {
        UIImageView *qrImg = (UIImageView *)[self.welcomeQrBox viewWithTag:5201];
        UIImage *img = qrImg.image;
        if (!img) return;
        self.saveQrButton.enabled = NO;
        [self.saveQrButton setTitle:[self L:@"Đang lưu..." en:@"Saving..."] forState:UIControlStateNormal];
        UIImageWriteToSavedPhotosAlbum(img, self, @selector(onQrSaved:didFinishSavingWithError:contextInfo:), NULL);
    } @catch (...) {}
}

- (void)onQrSaved:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            self.saveQrButton.enabled = YES;
            if (!error) {
                [self.saveQrButton setTitle:[self L:@"Đã lưu Ảnh ✓" en:@"Saved ✓"] forState:UIControlStateNormal];
                self.saveQrButton.backgroundColor = FTC_Color(0x16A34A);
            } else {
                [self.saveQrButton setTitle:[self L:@"Cần quyền Ảnh" en:@"Allow Photos"] forState:UIControlStateNormal];
                self.saveQrButton.backgroundColor = FTC_Color(FTC_C_ORANGE);
            }
        } @catch (...) {}
    });
}

- (void)onShowJitGuide {
    self.welcomeMainBox.hidden = YES;
    self.welcomeQrBox.hidden = YES;
    self.welcomeJitGuideBox.hidden = NO;
}

- (void)onBackFromWelcomeSub {
    self.welcomeQrBox.hidden = YES;
    self.welcomeJitGuideBox.hidden = YES;
    self.welcomeMainBox.hidden = NO;
}

- (void)onCloseWelcomePopup {
    @try {
        UIView *ov = self.welcomeOverlay;
        UIView *card = self.welcomeCard;
        if (!ov) return;
        self.welcomeOverlay = nil;
        self.welcomeCard = nil;
        self.welcomeMainBox = nil;
        self.welcomeQrBox = nil;
        self.welcomeJitGuideBox = nil;
        self.saveQrButton = nil;
        [UIView animateWithDuration:0.16 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
            ov.alpha = 0.0;
            card.transform = CGAffineTransformMakeScale(0.95, 0.95);
        } completion:^(BOOL finished) {
            [ov removeFromSuperview];
        }];
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
            CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(onFpsTick:)];
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
    if (self.fpsLastUpdate == 0) { self.fpsLastUpdate = now; self.fpsFrames = 0; return; }
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
    [self.forgeKeepAliveTimer invalidate];
    self.forgeKeepAliveTimer = nil;
    [self.autoFeverTimer invalidate];
    self.autoFeverTimer = nil;
}

@end
