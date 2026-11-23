// CheatMenuView.h — floating cutout demon logo overlay + 16:9 zero-lag cheat panel
// + launch welcome popup with Discord/GitHub/TikTok links and MoMo QR donate modal.
#import <UIKit/UIKit.h>

@interface CheatMenuView : UIView
// Attach to a window. Safe to call repeatedly; re-parents if needed.
- (void)attachToWindow:(UIWindow *)window;
// Show the launch welcome popup when entering/returning to the game.
- (void)onAppEnteredForeground;
@end
