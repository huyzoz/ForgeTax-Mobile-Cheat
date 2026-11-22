// CheatMenuView.mm — see header. Colours are the mockup's CSS tokens.
// Flame path is copied verbatim from the mockup's logo SVG
// (viewBox 0 0 24 24):
//   M12 2c.9 2.8-2.1 4.3-2.1 6.9 0 1.4.9 2.4 2.1 2.4s2.1-1 2.1-2.4
//   c1.9 1.4 2.9 3.3 2.9 5.2A5 5 0 0 1 7 14.1C7 10 10 5.9 12 2z
// Font is the system font (San Francisco) — no bundled fonts.
#import "CheatMenuView.h"
#import "FeatureCatalog.h"
#import "PatchEngine.h"
#import "GameBridge.h"

#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <string.h>

// ---- Mockup design tokens ----
#define FTC_C_BG      0x171009
#define FTC_C_SURFACE 0x241A10
#define FTC_C_SURF2   0x2C2013
#define FTC_C_SURF3   0x3A2A1A
#define FTC_C_BORDER  0x4A341C
#define FTC_C_BORDER2 0x5A4020
#define FTC_C_TEXT    0xF3E9D2
#define FTC_C_TEXT2   0xCBB894
#define FTC_C_TEXT3   0xA89880
#define FTC_C_GOLD    0xF7D774
#define FTC_C_GOLD2   0xF2B63D
#define FTC_C_GOLD3   0xFFB347
#define FTC_C_ACCENT  0xFF7A1A
#define FTC_C_ACCENT2 0xE85D04
#define FTC_C_ACCENT3 0xFF8A1E
#define FTC_C_ONACC   0x1A1208
#define FTC_C_FPS     0x7DFF8A

static UIColor *FTC_Color(uint32_t hex) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0 alpha:1.0];
}

static const CGFloat kLogoSize = 56.0;
static const CGFloat kPanelWidth = 360.0;
static const CGFloat kPanelMaxHeight = 560.0;
static const CGFloat kMargin = 8.0;

typedef struct { const char *cid; const char *name; } FTCCategory;
static const FTCCategory kCategories[] = {
    {"forge", "Ren"}, {"res", "Tai nguyen"}, {"relic", "Di vat"},
    {"shop", "Thuong nhan"}, {"dragon", "Rong"}, {"day", "Ngay & Choi"},
    {"ads", "Quang cao"},
};
static const size_t kCategoryCount = sizeof(kCategories) / sizeof(kCategories[0]);

@interface CheatMenuView ()
@property (nonatomic, strong) UIButton *logoButton;
@property (nonatomic, strong) UILabel *fpsBadge;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, strong) UILabel *dayPillValue;
@property (nonatomic, assign) BOOL menuOpen;
@property (nonatomic, assign) CGPoint dragStart;
@property (nonatomic, assign) CGPoint dragOrigin;
@property (nonatomic, assign) BOOL dragMoved;
@property (nonatomic, strong) CADisplayLink *fpsLink;
@property (nonatomic, assign) NSInteger fpsFrames;
@property (nonatomic, assign) NSTimeInterval fpsLastUpdate;
// Per-feature UI state. All features default OFF at launch.
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *switchOn;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *stepValue;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *modeIndex;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *statusText;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *catOpen;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *descOpen;
@property (nonatomic, assign) BOOL engineOpen;
@property (nonatomic, assign) BOOL settingOpen;
@property (nonatomic, assign) NSInteger currentDay;
@end

@implementation CheatMenuView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = YES;
    _switchOn = [NSMutableDictionary dictionary];
    _stepValue = [NSMutableDictionary dictionary];
    _modeIndex = [NSMutableDictionary dictionary];
    _statusText = [NSMutableDictionary dictionary];
    _catOpen = [NSMutableDictionary dictionary];
    _descOpen = [NSMutableDictionary dictionary];
    _engineOpen = YES;    // mockup default: CHEAT ENGINE open
    _settingOpen = NO;     // mockup default: SETTING closed
    _currentDay = 12;      // mockup pill default
    for (size_t i = 0; i < kFTC_FeatureCount; i++) {
        const FTC_Feature *f = &kFTC_Features[i];
        if (f->kind == FTC_KIND_STEP) {
            // Defaults from the mockup: grade 0, day 1, tickets 0.
            _stepValue[@(f->fid)] = (f->fid == 9) ? @(1) : @(0);
        }
        if (f->kind == FTC_KIND_MODE) {
            _modeIndex[@(f->fid)] = @(0);
        }
    }
    [self buildLogo];
    [self buildPanel];
    return self;
}

// Only the logo and the panel take touches; taps elsewhere pass through
// to the game underneath.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.menuOpen) {
        if (CGRectContainsPoint(self.logoButton.frame, point)) return [super hitTest:point withEvent:event];
        return nil;
    }
    if (CGRectContainsPoint(self.logoButton.frame, point) ||
        CGRectContainsPoint(self.panel.frame, point)) {
        return [super hitTest:point withEvent:event];
    }
    return nil;
}

#pragma mark - Logo (flame, mockup SVG path)

- (void)buildLogo {
    UIButton *logo = [UIButton buttonWithType:UIButtonTypeCustom];
    logo.frame = CGRectMake(0, 0, kLogoSize, kLogoSize);
    logo.layer.cornerRadius = kLogoSize / 2.0;
    logo.layer.borderWidth = 2.0;
    logo.layer.borderColor = FTC_Color(FTC_C_GOLD3).CGColor;
    logo.layer.masksToBounds = NO;
    logo.layer.shadowColor = FTC_Color(FTC_C_ACCENT).CGColor;
    logo.layer.shadowOpacity = 0.45;
    logo.layer.shadowRadius = 11.0;
    logo.layer.shadowOffset = CGSizeZero;
    logo.accessibilityLabel = @"Mo / dong menu cheat";

    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.frame = logo.bounds;
    grad.cornerRadius = kLogoSize / 2.0;
    grad.colors = @[(id)FTC_Color(FTC_C_ACCENT3).CGColor, (id)FTC_Color(FTC_C_ACCENT2).CGColor];
    grad.startPoint = CGPointMake(0.5, 0.0);
    grad.endPoint = CGPointMake(0.5, 1.0);
    [logo.layer insertSublayer:grad atIndex:0];

    // Flame, verbatim from the mockup SVG (24x24 viewBox, drawn at 28pt).
    UIBezierPath *flame = [UIBezierPath bezierPath];
    CGFloat s = 28.0 / 24.0;
    [flame moveToPoint:CGPointMake(12 * s, 2 * s)];
    [flame addCurveToPoint:CGPointMake(9.9 * s, 8.9 * s)
             controlPoint1:CGPointMake(12.9 * s, 4.8 * s)
             controlPoint2:CGPointMake(9.9 * s, 6.3 * s)];
    [flame addCurveToPoint:CGPointMake(12 * s, 11.3 * s)
             controlPoint1:CGPointMake(9.9 * s, 10.3 * s)
             controlPoint2:CGPointMake(10.8 * s, 11.3 * s)];
    [flame addCurveToPoint:CGPointMake(14.1 * s, 8.9 * s)
             controlPoint1:CGPointMake(13.2 * s, 11.3 * s)
             controlPoint2:CGPointMake(14.1 * s, 10.3 * s)];
    [flame addCurveToPoint:CGPointMake(17 * s, 14.1 * s)
             controlPoint1:CGPointMake(16 * s, 10.3 * s)
             controlPoint2:CGPointMake(17 * s, 12.2 * s)];
    [flame addArcWithCenter:CGPointMake(12 * s, 14.1 * s) radius:5 * s
                 startAngle:0 endAngle:M_PI clockwise:YES];
    [flame addCurveToPoint:CGPointMake(12 * s, 2 * s)
             controlPoint1:CGPointMake(7 * s, 12 * s)
             controlPoint2:CGPointMake(10 * s, 5.9 * s)];
    [flame closePath];
    CAShapeLayer *flameLayer = [CAShapeLayer layer];
    flameLayer.path = flame.CGPath;
    flameLayer.fillColor = FTC_Color(FTC_C_ONACC).CGColor;
    flameLayer.frame = CGRectMake((kLogoSize - 28) / 2.0, (kLogoSize - 28) / 2.0, 28, 28);
    [logo.layer addSublayer:flameLayer];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(onLogoPan:)];
    [logo addGestureRecognizer:pan];
    [self addSubview:logo];
    self.logoButton = logo;

    UILabel *fps = [[UILabel alloc] initWithFrame:CGRectZero];
    fps.text = @"-- FPS";
    fps.font = [UIFont boldSystemFontOfSize:12];
    fps.textColor = FTC_Color(FTC_C_FPS);
    fps.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.72];
    fps.layer.borderColor = [FTC_Color(FTC_C_GOLD2) colorWithAlphaComponent:0.4].CGColor;
    fps.layer.borderWidth = 1.0;
    fps.layer.cornerRadius = 8.0;
    fps.layer.masksToBounds = YES;
    fps.textAlignment = NSTextAlignmentCenter;
    fps.hidden = YES;
    [self addSubview:fps];
    self.fpsBadge = fps;
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
            if (fabs(dx) + fabs(dy) > 10) self.dragMoved = YES;
            if (self.dragMoved) {
                CGPoint origin = CGPointMake(self.dragOrigin.x + dx, self.dragOrigin.y + dy);
                origin.x = MAX(kMargin, MIN(origin.x, self.bounds.size.width - kLogoSize - kMargin));
                origin.y = MAX(kMargin, MIN(origin.y, self.bounds.size.height - kLogoSize - kMargin));
                self.logoButton.frame = CGRectMake(origin.x, origin.y, kLogoSize, kLogoSize);
                [self layoutPanel];
            }
        } else if (pan.state == UIGestureRecognizerStateEnded ||
                   pan.state == UIGestureRecognizerStateCancelled) {
            if (!self.dragMoved) {
                [self setMenuOpen:!self.menuOpen];
            }
            [self layoutPanel];
        }
    } @catch (...) { /* drag must never crash the game */ }
}

#pragma mark - Panel

- (void)buildPanel {
    UIView *panel = [[UIView alloc] initWithFrame:CGRectZero];
    panel.backgroundColor = FTC_Color(FTC_C_SURFACE);
    panel.layer.cornerRadius = 18.0;
    panel.layer.borderColor = FTC_Color(FTC_C_BORDER).CGColor;
    panel.layer.borderWidth = 1.0;
    panel.layer.shadowColor = [UIColor blackColor].CGColor;
    panel.layer.shadowOpacity = 0.7;
    panel.layer.shadowRadius = 24.0;
    panel.layer.shadowOffset = CGSizeMake(0, 8);
    panel.hidden = YES;
    [self addSubview:panel];
    self.panel = panel;

    // Header: FORGE TAXX + 3 pills (mockup hero).
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.text = @"FORGE TAXX";
    title.font = [UIFont boldSystemFontOfSize:28];
    title.textColor = FTC_Color(FTC_C_GOLD);
    title.textAlignment = NSTextAlignmentCenter;
    title.tag = 1001;
    [panel addSubview:title];

    NSArray *pills = @[@{@"v": @"9.999E+99", @"l": @"Vang"},
                       @{@"v": @"Grade 999", @"l": @"Gioi han kiem"},
                       @{@"v": @"Ngay 12", @"l": @"Trong 24 ngay"}];
    for (NSInteger i = 0; i < 3; i++) {
        UIView *pill = [[UIView alloc] initWithFrame:CGRectZero];
        pill.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.38];
        pill.layer.borderColor = [FTC_Color(FTC_C_GOLD2) colorWithAlphaComponent:0.4].CGColor;
        pill.layer.borderWidth = 1.0;
        pill.layer.cornerRadius = 12.0;
        pill.tag = 2000 + i;
        UILabel *v = [[UILabel alloc] initWithFrame:CGRectZero];
        v.text = pills[i][@"v"];
        v.font = [UIFont boldSystemFontOfSize:13];
        v.textColor = FTC_Color(FTC_C_GOLD);
        v.textAlignment = NSTextAlignmentCenter;
        v.tag = 2100 + i;
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
        l.text = pills[i][@"l"];
        l.font = [UIFont systemFontOfSize:11];
        l.textColor = FTC_Color(FTC_C_TEXT2);
        l.textAlignment = NSTextAlignmentCenter;
        l.tag = 2200 + i;
        [pill addSubview:v];
        [pill addSubview:l];
        [panel addSubview:pill];
        if (i == 2) self.dayPillValue = v;
    }

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scroll.showsVerticalScrollIndicator = YES;
    [panel addSubview:scroll];
    self.scrollView = scroll;

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.alignment = UIStackViewAlignmentFill;
    stack.distribution = UIStackViewDistributionFill;
    [scroll addSubview:stack];
    self.stackView = stack;
}

- (void)attachToWindow:(UIWindow *)window {
    @try {
        if (!window) return;
        self.frame = window.bounds;
        if (self.superview != window) [window addSubview:self];
        // Initial position: top-right (mockup default).
        if (self.logoButton.frame.origin.x == 0 && self.logoButton.frame.origin.y == 0) {
            self.logoButton.frame = CGRectMake(window.bounds.size.width - kLogoSize - 16, 16,
                                               kLogoSize, kLogoSize);
        }
        [self rebuildContent];
        [self layoutPanel];
    } @catch (...) {}
}

- (void)layoutSubviews {
    [super layoutSubviews];
    @try {
        // Keep the logo inside the window after rotation / resize.
        CGRect f = self.logoButton.frame;
        f.origin.x = MAX(kMargin, MIN(f.origin.x, self.bounds.size.width - kLogoSize - kMargin));
        f.origin.y = MAX(kMargin, MIN(f.origin.y, self.bounds.size.height - kLogoSize - kMargin));
        self.logoButton.frame = f;
        [self layoutPanel];
    } @catch (...) {}
}

- (void)layoutPanel {
    @try {
        CGFloat pw = MIN(kPanelWidth, self.bounds.size.width - 16);
        CGFloat ph = MIN(kPanelMaxHeight, MAX(160, self.bounds.size.height - kLogoSize - 40));
        CGRect logo = self.logoButton.frame;
        BOOL below = (self.bounds.size.height - logo.origin.y - kLogoSize - 8) >= (ph + 8);
        CGFloat y = below ? (logo.origin.y + kLogoSize + 8)
                          : (logo.origin.y - 8 - ph);
        CGFloat x = MAX(kMargin, MIN(logo.origin.x + kLogoSize - pw,
                                     self.bounds.size.width - pw - kMargin));
        self.panel.frame = CGRectMake(x, y, pw, ph);

        // Header layout inside the panel.
        UILabel *title = (UILabel *)[self.panel viewWithTag:1001];
        title.frame = CGRectMake(0, 10, pw, 30);
        CGFloat pillW = (pw - 32 - 16) / 3.0;
        for (NSInteger i = 0; i < 3; i++) {
            UIView *pill = [self.panel viewWithTag:2000 + i];
            pill.frame = CGRectMake(16 + i * (pillW + 8), 46, pillW, 44);
            UILabel *v = (UILabel *)[pill viewWithTag:2100 + i];
            UILabel *l = (UILabel *)[pill viewWithTag:2200 + i];
            v.frame = CGRectMake(0, 5, pillW, 17);
            l.frame = CGRectMake(0, 23, pillW, 15);
        }
        self.scrollView.frame = CGRectMake(0, 98, pw, ph - 98 - 8);
        self.stackView.frame = CGRectMake(10, 0, pw - 20, self.stackView.frame.size.height);
        self.scrollView.contentSize = CGSizeMake(pw - 20, self.stackView.frame.size.height);

        // FPS badge sits right of the logo.
        self.fpsBadge.frame = CGRectMake(logo.origin.x + kLogoSize + 8, logo.origin.y + 14, 64, 26);
    } @catch (...) {}
}

- (void)setMenuOpen:(BOOL)open {
    self.menuOpen = open;
    self.panel.hidden = !open;
    self.logoButton.layer.borderColor = open ? FTC_Color(FTC_C_GOLD).CGColor
                                             : FTC_Color(FTC_C_GOLD3).CGColor;
    if (open) {
        [self rebuildContent];
        [self layoutPanel];
    }
}

#pragma mark - Content building (only on interaction)

- (UIButton *)sectionHeaderWithTitle:(NSString *)title count:(NSString *)count
                                open:(BOOL)open action:(SEL)action tag:(NSInteger)tag {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:[NSString stringWithFormat:@"%@   %@  %@", open ? @"▾" : @"▸", title, count]
       forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [b setTitleColor:FTC_Color(FTC_C_GOLD) forState:UIControlStateNormal];
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    b.contentEdgeInsets = UIEdgeInsetsMake(10, 12, 10, 12);
    b.backgroundColor = [FTC_Color(FTC_C_ACCENT) colorWithAlphaComponent:0.12];
    b.layer.cornerRadius = 12;
    b.tag = tag;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    // UIStackView sizes arranged views from constraints/intrinsic size;
    // give headers an explicit height so they never collapse to zero.
    [b.heightAnchor constraintEqualToConstant:52].active = YES;
    return b;
}

- (void)rebuildContent {
    @try {
        for (UIView *v in self.stackView.arrangedSubviews) {
            [self.stackView removeArrangedSubview:v];
            [v removeFromSuperview];
        }
        // CHEAT ENGINE group (37 features: all except setting's 2).
        NSInteger engineCount = 0;
        for (size_t i = 0; i < kFTC_FeatureCount; i++) {
            if (strcmp(kFTC_Features[i].category, "setting") != 0) engineCount++;
        }
        UIButton *engHead = [self sectionHeaderWithTitle:@"CHEAT ENGINE"
                                                    count:[NSString stringWithFormat:@"%ld tinh nang", (long)engineCount]
                                                     open:self.engineOpen
                                                   action:@selector(onToggleEngine) tag:1];
        [self.stackView addArrangedSubview:engHead];
        if (self.engineOpen) {
            for (size_t c = 0; c < kCategoryCount; c++) {
                [self addCategoryAtIndex:c];
            }
        }
        // SETTING group (2 features: #32, #40).
        UIButton *setHead = [self sectionHeaderWithTitle:@"SETTING" count:@"2 muc"
                                                    open:self.settingOpen
                                                  action:@selector(onToggleSetting) tag:2];
        [self.stackView addArrangedSubview:setHead];
        if (self.settingOpen) {
            for (size_t i = 0; i < kFTC_FeatureCount; i++) {
                if (strcmp(kFTC_Features[i].category, "setting") == 0) {
                    [self.stackView addArrangedSubview:[self rowForFeature:&kFTC_Features[i]]];
                }
            }
        }
        // Measure the stack height for the scroll view.
        [self.stackView layoutIfNeeded];
        CGFloat h = 0;
        for (UIView *v in self.stackView.arrangedSubviews) h += v.frame.size.height + 10;
        CGRect f = self.stackView.frame;
        f.size.height = h;
        self.stackView.frame = f;
        self.scrollView.contentSize = CGSizeMake(self.stackView.frame.size.width, h);
    } @catch (...) {}
}

- (void)addCategoryAtIndex:(size_t)idx {
    FTCCategory cat = kCategories[idx];
    NSInteger count = 0;
    for (size_t i = 0; i < kFTC_FeatureCount; i++) {
        if (strcmp(kFTC_Features[i].category, cat.cid) == 0) count++;
    }
    NSString *key = [NSString stringWithUTF8String:cat.cid];
    BOOL open = [self.catOpen[key] boolValue]; // mockup default: closed
    UIButton *head = [UIButton buttonWithType:UIButtonTypeCustom];
    [head setTitle:[NSString stringWithFormat:@"%@ %@  %ld muc", open ? @"▾" : @"▸",
                    [NSString stringWithUTF8String:cat.name], (long)count]
          forState:UIControlStateNormal];
    head.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [head setTitleColor:FTC_Color(FTC_C_GOLD) forState:UIControlStateNormal];
    head.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    head.contentEdgeInsets = UIEdgeInsetsMake(8, 10, 8, 10);
    head.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.28];
    head.layer.cornerRadius = 12;
    head.tag = 100 + (NSInteger)idx;
    [head.heightAnchor constraintEqualToConstant:44].active = YES;
    [head addTarget:self action:@selector(onToggleCategory:) forControlEvents:UIControlEventTouchUpInside];
    [self.stackView addArrangedSubview:head];
    if (!open) return;
    for (size_t i = 0; i < kFTC_FeatureCount; i++) {
        if (strcmp(kFTC_Features[i].category, cat.cid) == 0) {
            [self.stackView addArrangedSubview:[self rowForFeature:&kFTC_Features[i]]];
        }
    }
}

- (UIView *)rowForFeature:(const FTC_Feature *)f {
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 100, 56)];
    row.backgroundColor = [FTC_Color(FTC_C_TEXT) colorWithAlphaComponent:0.035];
    row.layer.borderColor = [FTC_Color(FTC_C_GOLD2) colorWithAlphaComponent:0.16].CGColor;
    row.layer.borderWidth = 1.0;
    row.layer.cornerRadius = 14.0;
    BOOL on = [self.switchOn[@(f->fid)] boolValue];
    if (on) {
        row.layer.borderColor = [FTC_Color(FTC_C_ACCENT) colorWithAlphaComponent:0.55].CGColor;
        row.backgroundColor = [FTC_Color(FTC_C_ACCENT) colorWithAlphaComponent:0.09];
    }

    UIButton *nameBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    NSString *name = [NSString stringWithUTF8String:f->name];
    [nameBtn setTitle:name forState:UIControlStateNormal];
    nameBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [nameBtn setTitleColor:FTC_Color(FTC_C_TEXT) forState:UIControlStateNormal];
    nameBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    nameBtn.tag = f->fid;
    [nameBtn addTarget:self action:@selector(onToggleDesc:) forControlEvents:UIControlEventTouchUpInside];
    nameBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:nameBtn];

    // Status line (last result / "chua goi duoc"), shown under the name.
    NSString *status = self.statusText[@(f->fid)];
    BOOL descShown = [self.descOpen[@(f->fid)] boolValue];
    CGFloat rowHeight = 56;
    if (descShown || status) {
        rowHeight = 86;
        UILabel *sub = [[UILabel alloc] initWithFrame:CGRectZero];
        sub.numberOfLines = 0;
        sub.font = [UIFont systemFontOfSize:12];
        sub.textColor = FTC_Color(FTC_C_TEXT3);
        NSMutableString *t = [NSMutableString string];
        if (descShown) [t appendString:[NSString stringWithUTF8String:f->desc]];
        if (status) {
            if (t.length) [t appendString:@"\n"];
            [t appendString:status];
        }
        sub.text = t;
        sub.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:sub];
        CGFloat trailing = (f->kind == FTC_KIND_STEP) ? -180 : -110;
        [NSLayoutConstraint activateConstraints:@[
            [sub.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:10],
            [sub.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:trailing],
            [sub.topAnchor constraintEqualToAnchor:nameBtn.bottomAnchor constant:0],
        ]];
    }
    // Explicit height: UIStackView cannot infer a plain UIView's height.
    [row.heightAnchor constraintEqualToConstant:rowHeight].active = YES;

    CGFloat nameTrailing = (f->kind == FTC_KIND_STEP) ? -180 : -110;
    [NSLayoutConstraint activateConstraints:@[
        [nameBtn.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:10],
        [nameBtn.topAnchor constraintEqualToAnchor:row.topAnchor constant:6],
        [nameBtn.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:nameTrailing],
        [nameBtn.heightAnchor constraintEqualToConstant:36],
    ]];

    UIView *control = [self controlForFeature:f];
    control.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:control];
    [NSLayoutConstraint activateConstraints:@[
        [control.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-8],
        [control.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];

    // Secondary one-shot buttons inside combined rows (#4, #7, #24).
    if (f->fid == 4 || f->fid == 7 || f->fid == 24) {
        UIButton *extra = [UIButton buttonWithType:UIButtonTypeSystem];
        NSString *t = (f->fid == 4) ? @"Doi mode" : (f->fid == 7) ? @"Giet ngay" : @"Chon kiem";
        [extra setTitle:t forState:UIControlStateNormal];
        extra.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        [extra setTitleColor:FTC_Color(FTC_C_GOLD2) forState:UIControlStateNormal];
        extra.tag = f->fid;
        [extra addTarget:self action:@selector(onSecondary:) forControlEvents:UIControlEventTouchUpInside];
        extra.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:extra];
        [NSLayoutConstraint activateConstraints:@[
            [extra.trailingAnchor constraintEqualToAnchor:control.leadingAnchor constant:-6],
            [extra.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        ]];
    }
    return row;
}

- (UIView *)controlForFeature:(const FTC_Feature *)f {
    switch (f->kind) {
        case FTC_KIND_PATCH:
        case FTC_KIND_DEV_TOGGLE: {
            UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
            sw.on = [self.switchOn[@(f->fid)] boolValue];
            sw.onTintColor = FTC_Color(FTC_C_ACCENT);
            sw.tag = f->fid;
            [sw addTarget:self action:@selector(onSwitch:) forControlEvents:UIControlEventValueChanged];
            return sw;
        }
        case FTC_KIND_ONESHOT: {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
            [b setTitle:@"Chay" forState:UIControlStateNormal];
            b.titleLabel.font = [UIFont boldSystemFontOfSize:13];
            [b setTitleColor:FTC_Color(FTC_C_ONACC) forState:UIControlStateNormal];
            b.backgroundColor = FTC_Color(FTC_C_ACCENT3);
            b.layer.cornerRadius = 10;
            b.tag = f->fid;
            b.frame = CGRectMake(0, 0, 64, 40);
            [b addTarget:self action:@selector(onOneshot:) forControlEvents:UIControlEventTouchUpInside];
            return b;
        }
        case FTC_KIND_MODE: {
            UISegmentedControl *seg = nil;
            if (f->fid == 28) {
                seg = [[UISegmentedControl alloc] initWithItems:@[@"-1 ngay", @"+1 ngay"]];
            } else if (f->fid == 32) {
                seg = [[UISegmentedControl alloc] initWithItems:@[@"Thap", @"Vua", @"Cao"]];
                seg.selectedSegmentIndex = [self.modeIndex[@(f->fid)] integerValue];
            } else {
                seg = [[UISegmentedControl alloc] initWithItems:@[@"--"]];
            }
            seg.tag = f->fid;
            seg.frame = CGRectMake(0, 0, 150, 32);
            [seg setTitleTextAttributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:12]}
                               forState:UIControlStateNormal];
            [seg addTarget:self action:@selector(onSegment:) forControlEvents:UIControlEventValueChanged];
            return seg;
        }
        case FTC_KIND_STEP: {
            UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 170, 44)];
            if (f->fid == 12) {
                // Ticket kind picker + "+1 ve" button.
                UISegmentedControl *seg = [[UISegmentedControl alloc]
                    initWithItems:@[@"Damage", @"Hold", @"Success", @"Great"]];
                seg.frame = CGRectMake(0, 0, 170, 28);
                seg.selectedSegmentIndex = [self.modeIndex[@(f->fid)] integerValue];
                seg.tag = f->fid;
                [seg setTitleTextAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:10]}
                                   forState:UIControlStateNormal];
                [seg addTarget:self action:@selector(onTicketKind:) forControlEvents:UIControlEventValueChanged];
                [wrap addSubview:seg];
                UIButton *plus = [UIButton buttonWithType:UIButtonTypeSystem];
                [plus setTitle:@"+1 ve" forState:UIControlStateNormal];
                plus.titleLabel.font = [UIFont boldSystemFontOfSize:12];
                [plus setTitleColor:FTC_Color(FTC_C_ONACC) forState:UIControlStateNormal];
                plus.backgroundColor = FTC_Color(FTC_C_ACCENT3);
                plus.layer.cornerRadius = 8;
                plus.frame = CGRectMake(100, 30, 70, 26);
                plus.tag = f->fid;
                [plus addTarget:self action:@selector(onTicketPlus:) forControlEvents:UIControlEventTouchUpInside];
                [wrap addSubview:plus];
                wrap.frame = CGRectMake(0, 0, 170, 58);
                return wrap;
            }
            UIStepper *stepper = [[UIStepper alloc] initWithFrame:CGRectMake(0, 0, 94, 29)];
            stepper.tag = f->fid;
            NSInteger v = [self.stepValue[@(f->fid)] integerValue];
            stepper.value = v;
            if (f->fid == 6) { stepper.minimumValue = 0; stepper.maximumValue = 999; stepper.stepValue = 10; }
            if (f->fid == 9) { stepper.minimumValue = 1; stepper.maximumValue = 24; stepper.stepValue = 1; }
            [stepper addTarget:self action:@selector(onStepper:) forControlEvents:UIControlEventValueChanged];
            [wrap addSubview:stepper];
            UILabel *val = [[UILabel alloc] initWithFrame:CGRectMake(98, 0, 34, 29)];
            val.text = [NSString stringWithFormat:@"%ld", (long)v];
            val.font = [UIFont boldSystemFontOfSize:13];
            val.textColor = FTC_Color(FTC_C_GOLD);
            val.textAlignment = NSTextAlignmentCenter;
            [wrap addSubview:val];
            UIButton *apply = [UIButton buttonWithType:UIButtonTypeSystem];
            [apply setTitle:(f->fid == 9) ? @"Nhay" : @"Ap dung" forState:UIControlStateNormal];
            apply.titleLabel.font = [UIFont boldSystemFontOfSize:12];
            [apply setTitleColor:FTC_Color(FTC_C_ONACC) forState:UIControlStateNormal];
            apply.backgroundColor = FTC_Color(FTC_C_ACCENT3);
            apply.layer.cornerRadius = 8;
            apply.frame = CGRectMake(132, 0, 38, 29);
            apply.tag = f->fid;
            [apply addTarget:self action:@selector(onStepApply:) forControlEvents:UIControlEventTouchUpInside];
            [wrap addSubview:apply];
            return wrap;
        }
    }
    return [[UIView alloc] initWithFrame:CGRectZero];
}

#pragma mark - Section toggles

- (void)onToggleEngine { self.engineOpen = !self.engineOpen; [self rebuildContent]; [self layoutPanel]; }
- (void)onToggleSetting { self.settingOpen = !self.settingOpen; [self rebuildContent]; [self layoutPanel]; }

- (void)onToggleCategory:(UIButton *)sender {
    NSInteger idx = sender.tag - 100;
    if (idx < 0 || idx >= (NSInteger)kCategoryCount) return;
    NSString *key = [NSString stringWithUTF8String:kCategories[idx].cid];
    self.catOpen[key] = @(![self.catOpen[key] boolValue]);
    [self rebuildContent]; [self layoutPanel];
}

- (void)onToggleDesc:(UIButton *)sender {
    NSNumber *key = @(sender.tag);
    self.descOpen[key] = @(![self.descOpen[key] boolValue]);
    [self rebuildContent]; [self layoutPanel];
}

#pragma mark - Feature actions

- (void)setStatus:(int)fid text:(NSString *)text {
    if (text) self.statusText[@(fid)] = text;
    else [self.statusText removeObjectForKey:@(fid)];
}

- (NSString *)messageForCall:(FTC_CallResult)r {
    return [NSString stringWithUTF8String:FTC_CallResultMessage(r)];
}

// Patch toggles (#4, #5, #10-#11, #13-#22, #34-#36, #38-#39) and dev toggles
// (#7 god, #33 shelf, #40 fps) share the switch UI but differ underneath:
// patch toggles write bytes, dev toggles call a flipping dev method once.
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
                [self setStatus:fid text:(wantOn ? @"Da bat" : @"Da tat")];
                if (fid == 10 && wantOn) {
                    // Fill the fever bar once when enabling (patch only
                    // stops expiry; it does not fill).
                    FTC_CallResult cr = FTC_FillFever();
                    if (cr != FTC_CALL_OK) {
                        [self setStatus:fid text:[NSString stringWithFormat:@"Patch bat; %@",
                                                  [self messageForCall:cr]]];
                    }
                }
            } else {
                sender.on = !wantOn; // refuse: leave the switch where it was
                [self setStatus:fid text:[NSString stringWithUTF8String:FTC_PatchResultMessage(r)]];
            }
        } else { // DEV_TOGGLE
            FTC_CallResult cr = FTC_CALL_ERR_UNAVAILABLE;
            if (fid == 7) cr = FTC_ToggleGodMode();
            else if (fid == 33) cr = FTC_ToggleMerchantShelfSlot();
            else if (fid == 40) cr = FTC_ToggleFps();
            if (cr == FTC_CALL_OK) {
                self.switchOn[@(fid)] = @(wantOn);
                [self setStatus:fid text:(wantOn ? @"Da bat" : @"Da tat")];
                if (fid == 40) [self setFpsBadgeVisible:wantOn];
            } else {
                sender.on = !wantOn;
                [self setStatus:fid text:[self messageForCall:cr]];
            }
        }
        [self rebuildContent]; [self layoutPanel];
    } @catch (...) {}
}

- (void)onOneshot:(UIButton *)sender {
    @try {
        int fid = (int)sender.tag;
        if (fid == 27) { // ResetRun destroys the current run — confirm first.
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
            UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
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
        [self setStatus:fid text:(cr == FTC_CALL_OK) ? @"Da chay"
                                                     : [self messageForCall:cr]];
        [self rebuildContent]; [self layoutPanel];
    } @catch (...) {}
}

- (void)onSecondary:(UIButton *)sender {
    @try {
        int fid = (int)sender.tag;
        FTC_CallResult cr = FTC_CALL_ERR_UNAVAILABLE;
        if (fid == 4) {
            // CycleForgeMode rotates the dev forge mode. NOTE: while the #4
            // Guard patch is ON, this has no effect on Guard (always
            // AlwaysSuccess) — see FeatureCatalog.h #4.
            cr = FTC_CycleForgeMode();
            if (cr == FTC_CALL_OK && [self.switchOn[@(4)] boolValue]) {
                [self setStatus:4 text:@"Da goi Doi mode (patch Ren luon thanh cong dang BAT nen Guard van luon AlwaysSuccess)"];
                [self rebuildContent]; [self layoutPanel];
                return;
            }
        }
        else if (fid == 7) cr = FTC_KillDragon();
        else if (fid == 24) cr = FTC_OpenSwordPicker();
        [self setStatus:fid text:(cr == FTC_CALL_OK) ? @"Da chay"
                                                     : [self messageForCall:cr]];
        [self rebuildContent]; [self layoutPanel];
    } @catch (...) {}
}

- (void)onSegment:(UISegmentedControl *)sender {
    @try {
        int fid = (int)sender.tag;
        if (fid == 28) {
            // Each tap is one call: -1 = SkipDay, +1 = NextDay.
            FTC_CallResult cr = (sender.selectedSegmentIndex == 0) ? FTC_SkipDay() : FTC_NextDay();
            [self setStatus:fid text:(cr == FTC_CALL_OK) ? @"Da chay"
                                                         : [self messageForCall:cr]];
            [self rebuildContent]; [self layoutPanel];
            return;
        }
        if (fid == 32) {
            // Thap=0, Vua=1, Cao=2.
            FTC_CallResult cr = FTC_SetQualityTier((int)sender.selectedSegmentIndex);
            if (cr == FTC_CALL_OK) {
                self.modeIndex[@(fid)] = @(sender.selectedSegmentIndex);
                [self setStatus:fid text:@"Da doi"];
            } else {
                [self setStatus:fid text:[self messageForCall:cr]];
            }
            [self rebuildContent]; [self layoutPanel];
        }
    } @catch (...) {}
}

- (void)onTicketKind:(UISegmentedControl *)sender {
    self.modeIndex[@(12)] = @(sender.selectedSegmentIndex);
}

- (void)onTicketPlus:(UIButton *)sender {
    @try {
        // ForgeOutcome: Damage=1, Hold=2, Success=3, GreatSuccess=4.
        int outcome = (int)[self.modeIndex[@(12)] integerValue] + 1;
        FTC_CallResult cr = FTC_AddRunTickets(outcome, 1);
        [self setStatus:12 text:(cr == FTC_CALL_OK) ? @"Da cong 1 ve"
                                                    : [self messageForCall:cr]];
        [self rebuildContent]; [self layoutPanel];
    } @catch (...) {}
}

- (void)onStepper:(UIStepper *)sender {
    self.stepValue[@(sender.tag)] = @((NSInteger)sender.value);
    [self rebuildContent]; [self layoutPanel];
}

- (void)onStepApply:(UIButton *)sender {
    @try {
        int fid = (int)sender.tag;
        NSInteger v = [self.stepValue[@(fid)] integerValue];
        FTC_CallResult cr = FTC_CALL_ERR_UNAVAILABLE;
        if (fid == 6) cr = FTC_SetAnvilGrade((int)v);
        else if (fid == 9) cr = FTC_JumpToDay((int)v);
        if (cr == FTC_CALL_OK) {
            [self setStatus:fid text:@"Da chay"];
            if (fid == 9) {
                self.currentDay = v;
                self.dayPillValue.text = [NSString stringWithFormat:@"Ngay %ld", (long)v];
            }
        } else {
            [self setStatus:fid text:[self messageForCall:cr]];
        }
        [self rebuildContent]; [self layoutPanel];
    } @catch (...) {}
}

#pragma mark - FPS badge (CADisplayLink only while #40 is ON)

- (void)setFpsBadgeVisible:(BOOL)visible {
    @try {
        self.fpsBadge.hidden = !visible;
        if (visible) {
            [self stopFpsLink];
            self.fpsFrames = 0;
            self.fpsLastUpdate = CACurrentMediaTime();
            CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self
                                                               selector:@selector(onFpsTick:)];
            [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
            self.fpsLink = link;
        } else {
            [self stopFpsLink];
            self.fpsBadge.text = @"-- FPS";
        }
    } @catch (...) {}
}

- (void)stopFpsLink {
    [self.fpsLink invalidate];
    self.fpsLink = nil;
}

- (void)onFpsTick:(CADisplayLink *)link {
    self.fpsFrames++;
    NSTimeInterval now = CACurrentMediaTime();
    if (now - self.fpsLastUpdate >= 1.0) {
        NSInteger fps = (NSInteger)lround(self.fpsFrames / (now - self.fpsLastUpdate));
        self.fpsBadge.text = [NSString stringWithFormat:@"%ld FPS", (long)fps];
        self.fpsFrames = 0;
        self.fpsLastUpdate = now;
    }
}

- (void)dealloc {
    [self stopFpsLink];
}

@end
