// ForgeTaxCheat.mm — dylib entry point.
//
// The constructor runs at launch and does almost nothing: it schedules the
// overlay attach on the main queue. Attaching watches for the game's key
// window (UIWindowDidBecomeKeyNotification) plus a light 1-second retry
// timer that stops itself after 60 tries or as soon as the overlay is
// attached. After attach there are NO background timers and NO per-frame
// work — the only recurring work in the whole dylib is the FPS
// CADisplayLink, which exists only while feature #40 is ON.
//
// Nothing here touches the game binary on disk, writes any file, or calls
// any game function at launch. Every feature defaults OFF.
#import <UIKit/UIKit.h>
#import "CheatMenuView.h"

static CheatMenuView *s_menuView = nil;
static NSTimer *s_attachTimer = nil;
static NSInteger s_attachTries = 0;

static BOOL FTC_IsMainGameWindow(UIWindow *w) {
    if (!w || w.hidden) return NO;
    if (w.windowLevel != UIWindowLevelNormal) return NO;
    if (w.bounds.size.width < 100.0 || w.bounds.size.height < 100.0) return NO;
    NSString *clsName = NSStringFromClass([w class]);
    if ([clsName containsString:@"Alert"] ||
        [clsName containsString:@"Keyboard"] ||
        [clsName containsString:@"TextEffects"] ||
        [clsName containsString:@"StatusBar"]) {
        return NO;
    }
    return YES;
}

static UIWindow *FTC_KeyWindow(void) {
    @try {
        UIApplication *app = [UIApplication sharedApplication];
        if (!app) return nil;

        // iOS 13+ scene-based lookup (ForgeTax uses UIApplicationSceneManifest / UnityScene).
        UIWindow *fallback = nil;
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            BOOL active = (ws.activationState == UISceneActivationStateForegroundActive);
            for (UIWindow *w in ws.windows) {
                if (!FTC_IsMainGameWindow(w)) continue;
                if (active && w.isKeyWindow) return w;
                if (active && !fallback) fallback = w;
                else if (!fallback) fallback = w;
            }
        }
        if (fallback) return fallback;

        // Legacy delegate window fallback.
        if (app.delegate && [app.delegate respondsToSelector:@selector(window)]) {
            UIWindow *dw = app.delegate.window;
            if (FTC_IsMainGameWindow(dw)) return dw;
        }
    } @catch (...) {}
    return nil;
}

static void FTC_AttachIfPossible(UIWindow *preferredWindow) {
    @try {
        UIWindow *window = FTC_IsMainGameWindow(preferredWindow) ? preferredWindow : FTC_KeyWindow();
        if (!window) return;
        if (!s_menuView) {
            s_menuView = [[CheatMenuView alloc] initWithFrame:window.bounds];
        }
        [s_menuView attachToWindow:window];
        if (s_menuView.superview) {
            [s_attachTimer invalidate];
            s_attachTimer = nil;
        }
    } @catch (...) {}
}

static void FTC_OnWindowDidBecomeKey(NSNotification *note) {
    @try {
        UIWindow *window = nil;
        if ([note.object isKindOfClass:[UIWindow class]]) {
            window = (UIWindow *)note.object;
        }
        // Ignore transient windows (e.g. UIAlertController, keyboard, ads)
        // when we are already attached to a live normal game window.
        if (window && !FTC_IsMainGameWindow(window)) {
            return;
        }
        FTC_AttachIfPossible(window);
    } @catch (...) {}
}

__attribute__((constructor))
static void ForgeTaxCheatInit(void) {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                [[NSNotificationCenter defaultCenter]
                    addObserverForName:UIWindowDidBecomeKeyNotification
                                object:nil
                                 queue:[NSOperationQueue mainQueue]
                            usingBlock:^(NSNotification *note) { FTC_OnWindowDidBecomeKey(note); }];
                [[NSNotificationCenter defaultCenter]
                    addObserverForName:UIApplicationWillEnterForegroundNotification
                                object:nil
                                 queue:[NSOperationQueue mainQueue]
                            usingBlock:^(NSNotification *note) {
                    @try {
                        if (s_menuView) [s_menuView onAppEnteredForeground];
                    } @catch (...) {}
                }];
                FTC_AttachIfPossible(nil);
                if (!s_menuView || !s_menuView.superview) {
                    // Light retry: 1s interval, stops on attach or after
                    // 60 tries. No timer survives past attach.
                    s_attachTries = 0;
                    s_attachTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                                     repeats:YES
                                                                       block:^(NSTimer *t) {
                        s_attachTries++;
                        FTC_AttachIfPossible(nil);
                        if ((!s_menuView || !s_menuView.superview) && s_attachTries >= 60) {
                            [t invalidate];
                            s_attachTimer = nil;
                        }
                    }];
                }
            } @catch (...) {}
        });
    }
}
