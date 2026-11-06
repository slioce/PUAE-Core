// The Amiga system's contract with its core, modelled on OEC64SystemResponderClient.h.
// Shared with PUAE.oecoreplugin (Core/PUAEGameCore.h includes it via -IAmiga).

#import <Foundation/Foundation.h>

@protocol OESystemResponderClient;

typedef enum
{
    OEAmigaJoystickUp,
    OEAmigaJoystickDown,
    OEAmigaJoystickLeft,
    OEAmigaJoystickRight,
    OEAmigaButtonFire,
    OEAmigaButtonFire2,
    OEAmigaButtonCount
} OEAmigaButton;

@protocol OEAmigaSystemResponderClient <OESystemResponderClient, NSObject>
// Points are absolute positions inside the game screen; the core turns them into Amiga mouse motion.
- (oneway void)mouseMovedAtPoint:(OEIntPoint)point;
- (oneway void)leftMouseDownAtPoint:(OEIntPoint)point;
- (oneway void)leftMouseUp;
- (oneway void)rightMouseDownAtPoint:(OEIntPoint)point;
- (oneway void)rightMouseUp;
// keyCode is a USB HID usage (keyboard page 0x07).
- (oneway void)keyDown:(NSUInteger)keyCode;
- (oneway void)keyUp:(NSUInteger)keyCode;
- (oneway void)didPushAmigaButton:(OEAmigaButton)button forPlayer:(NSUInteger)player;
- (oneway void)didReleaseAmigaButton:(OEAmigaButton)button forPlayer:(NSUInteger)player;
@optional
// A real mouse delta in game-screen pixels (the space of the points above), from Amiga/OEAmigaPointer.m.
// Optional because a newer system plugin may run with an older core, which keeps using the points.
- (oneway void)mouseMovedByX:(int)dx y:(int)dy;
@end
