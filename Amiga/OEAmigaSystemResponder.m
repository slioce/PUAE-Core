#import "OEAmigaSystemResponder.h"

@implementation OEAmigaSystemResponder
@dynamic client;

+ (Protocol *)gameSystemResponderClientProtocol
{
    return @protocol(OEAmigaSystemResponderClient);
}

// The keyboard is the Amiga's: every key goes to the core, after super has handled any bindings.
- (void)HIDKeyDown:(OEHIDEvent *)theEvent
{
    [super HIDKeyDown:theEvent];
    [self.client keyDown:theEvent.keycode];
}

- (void)HIDKeyUp:(OEHIDEvent *)theEvent
{
    [super HIDKeyUp:theEvent];
    [self.client keyUp:theEvent.keycode];
}

- (void)pressEmulatorKey:(OESystemKey *)aKey
{
    [self.client didPushAmigaButton:(OEAmigaButton)aKey.key forPlayer:aKey.player];
}

- (void)releaseEmulatorKey:(OESystemKey *)aKey
{
    [self.client didReleaseAmigaButton:(OEAmigaButton)aKey.key forPlayer:aKey.player];
}

- (void)mouseMovedAtPoint:(OEIntPoint)aPoint
{
    [self.client mouseMovedAtPoint:aPoint];
}

// Also sent repeatedly while dragging (OESystemResponder handleMouseEvent:), carrying the new position.
- (void)mouseDownAtPoint:(OEIntPoint)aPoint
{
    [self.client leftMouseDownAtPoint:aPoint];
}

- (void)mouseUpAtPoint
{
    [self.client leftMouseUp];
}

- (void)rightMouseDownAtPoint:(OEIntPoint)aPoint
{
    [self.client rightMouseDownAtPoint:aPoint];
}

- (void)rightMouseUpAtPoint
{
    [self.client rightMouseUp];
}

@end
