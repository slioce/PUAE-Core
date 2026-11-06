// Amiga games draw their own mouse pointer and read the mouse as motion only, so the Mac cursor can't sit
// on top of it: it shows up as a second pointer that drifts away. OpenEmu's game view (OEGameLayerView,
// in OpenEmuKit) reports the mouse only as positions clamped to the game screen, and those also stop
// changing when the cursor is pinned at an edge of the display.
//
// This system plugin is loaded into the OpenEmu process too, so for the game view of an Amiga game it
//  - hides the Mac cursor over the view with a transparent cursor rect. AppKit brings the arrow back
//    outside the view and over the HUD, which is a child window;
//  - sends the real mouse deltas (NSEvent deltaX/deltaY, which keep coming at the edges of the display)
//    before OpenEmu's own event, as an OEEvent of type OEAmigaMouseDeltaEventType whose location holds
//    the delta in game-screen pixels. OEAmigaSystemResponder hands it to the core, which then ignores
//    the absolute positions. Older cores ignore the deltas and keep using the positions.
// The game views of other systems take the original code path.

#import <Cocoa/Cocoa.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/log.h>
@import OpenEmuSystem;

#import "OEAmigaPointer.h"

static NSString *const AmigaSystemIdentifier = @"openemu.system.amiga";

void OEAmigaPointerDelta(OEAmigaPointerRemainder *remainder, CGFloat dx, CGFloat dy, CGSize viewSize,
                         CGSize gameSize, int *outX, int *outY)
{
    *outX = *outY = 0;
    if (!(viewSize.width > 0 && viewSize.height > 0 && gameSize.width > 0 && gameSize.height > 0))
        return;
    CGFloat pointsPerPixel = MIN(viewSize.width / gameSize.width, viewSize.height / gameSize.height);
    remainder->x += dx / pointsPerPixel;
    remainder->y += dy / pointsPerPixel;
    *outX = (int)trunc(remainder->x);
    *outY = (int)trunc(remainder->y);
    remainder->x -= *outX;
    remainder->y -= *outY;
}

#pragma mark - Game views

// Per game view: whether it shows an Amiga game (decided once), and the sub-pixel motion not yet sent.
@interface OEAmigaPointerState : NSObject
@property (nonatomic) BOOL amiga;
@property (nonatomic) OEAmigaPointerRemainder remainder;
@end

@implementation OEAmigaPointerState
@end

static char state_key;

// OpenEmu's GameViewController (@objc OEGameViewController) is the next responder of the game view's
// superview, and the game view's delegate.
static NSViewController *game_view_controller(NSView *view)
{
    Class controllerClass = objc_getClass("OEGameViewController");
    for (NSResponder *responder = view.nextResponder; responder; responder = responder.nextResponder)
        if ([responder isKindOfClass:controllerClass])
            return (NSViewController *)responder;
    return nil;
}

// The state of an Amiga game view, nil for any other view. A view whose game can't be told yet (no
// controller, or no document because the game is closing) isn't cached.
static OEAmigaPointerState *amiga_state(NSView *view, BOOL *decidedNow)
{
    OEAmigaPointerState *state = objc_getAssociatedObject(view, &state_key);
    if (!state) {
        NSViewController *controller = game_view_controller(view);
        // systemIdentifier force-unwraps the controller's weak document, so check it first.
        if (!controller || ![controller valueForKey:@"document"])
            return nil;
        state = [OEAmigaPointerState new];
        state.amiga = [[controller valueForKey:@"systemIdentifier"] isEqual:AmigaSystemIdentifier];
        objc_setAssociatedObject(view, &state_key, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (decidedNow)
            *decidedNow = YES;
    }
    return state.amiga ? state : nil;
}

BOOL OEAmigaPointerHidesCursorInView(NSView *view)
{
    return amiga_state(view, NULL) != nil;
}

static NSCursor *blank_cursor(void)
{
    static NSCursor *cursor;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:16
                                                                           pixelsHigh:16 bitsPerSample:8
                                                                      samplesPerPixel:4 hasAlpha:YES
                                                                             isPlanar:NO
                                                                       colorSpaceName:NSDeviceRGBColorSpace
                                                                          bytesPerRow:0 bitsPerPixel:0];
        memset(bitmap.bitmapData, 0, (size_t)bitmap.bytesPerRow * (size_t)bitmap.pixelsHigh);
        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
        [image addRepresentation:bitmap];
        cursor = [[NSCursor alloc] initWithImage:image hotSpot:NSZeroPoint];
    });
    return cursor;
}

static void send_delta(NSView *view, NSEvent *event, OEAmigaPointerState *state)
{
    NSViewController *controller = game_view_controller(view);
    SEL receive = @selector(gameView:didReceiveMouseEvent:);
    if (![controller respondsToSelector:receive])
        return;

    // defaultScreenSize is the aspect-corrected game screen, the same size OEGameLayerView maps onto.
    CGSize gameSize = [[controller valueForKey:@"defaultScreenSize"] sizeValue];
    OEAmigaPointerRemainder remainder = state.remainder;
    int dx, dy;
    OEAmigaPointerDelta(&remainder, event.deltaX, event.deltaY, view.frame.size, gameSize, &dx, &dy);
    state.remainder = remainder;
    if (!dx && !dy)
        return;

    NSEvent *carrier = [NSEvent otherEventWithType:OEAmigaMouseDeltaEventType location:NSZeroPoint
                                     modifierFlags:0 timestamp:event.timestamp
                                      windowNumber:event.windowNumber context:nil subtype:0 data1:0 data2:0];
    OEEvent *delta = [[OEEvent alloc] initWithMouseEvent:carrier withLocationInGameView:(OEIntPoint){ dx, dy }];
    ((void (*)(id, SEL, id, id))objc_msgSend)(controller, receive, view, delta);
}

#pragma mark - Hooks

typedef void (*event_imp)(id, SEL, NSEvent *);
typedef void (*plain_imp)(id, SEL);

// OEGameLayerView's motion handlers; OpenEmu's own handler runs after the delta is sent.
static struct {
    const char *name;
    SEL selector;
    event_imp original;
} motion_methods[] = {
    { .name = "mouseMoved:" },
    { .name = "mouseDragged:" },
    { .name = "rightMouseDragged:" },
    { .name = "otherMouseDragged:" },
};

static plain_imp original_reset_cursor_rects;

static void motion_hook(NSView *self, SEL _cmd, NSEvent *event)
{
    BOOL decidedNow = NO;
    OEAmigaPointerState *state = amiga_state(self, &decidedNow);
    if (state) {
        // The view's cursor rects may have been set before its game could be told apart.
        if (decidedNow)
            [self.window invalidateCursorRectsForView:self];
        send_delta(self, event, state);
    }
    for (size_t i = 0; i < sizeof motion_methods / sizeof motion_methods[0]; i++)
        if (sel_isEqual(motion_methods[i].selector, _cmd)) {
            motion_methods[i].original(self, _cmd, event);
            return;
        }
}

static void reset_cursor_rects_hook(NSView *self, SEL _cmd)
{
    original_reset_cursor_rects(self, _cmd);
    if (OEAmigaPointerHidesCursorInView(self))
        [self addCursorRect:self.visibleRect cursor:blank_cursor()];
}

// Points the class's own method at hook and returns the previous implementation. When the class only
// inherits the method, the hook is added to the class, and the inherited implementation stays reachable.
static IMP hook_method(Class cls, SEL selector, IMP hook)
{
    Method method = class_getInstanceMethod(cls, selector);
    if (!method)
        return NULL;
    IMP previous = method_getImplementation(method);
    if (class_addMethod(cls, selector, hook, method_getTypeEncoding(method)))
        return previous;
    return method_setImplementation(method, hook);
}

@interface OEAmigaPointer : NSObject
@end

@implementation OEAmigaPointer

+ (void)load
{
    os_log_t log = os_log_create("org.openemu.Amiga", "pointer");
    Class gameView = objc_getClass("_TtC10OpenEmuKit15OEGameLayerView");
    if (!gameView || !objc_getClass("OEGameViewController")) {
        // Expected in OpenEmuHelperApp, which has no game window; only the app shows the cursor.
        os_log_debug(log, "OEGameLayerView or OEGameViewController not found, pointer fix not installed");
        return;
    }

    for (size_t i = 0; i < sizeof motion_methods / sizeof motion_methods[0]; i++) {
        motion_methods[i].selector = sel_registerName(motion_methods[i].name);
        if (!class_getInstanceMethod(gameView, motion_methods[i].selector)) {
            os_log_error(log, "OEGameLayerView has no %{public}s, pointer fix not installed", motion_methods[i].name);
            return;
        }
    }
    for (size_t i = 0; i < sizeof motion_methods / sizeof motion_methods[0]; i++)
        motion_methods[i].original = (event_imp)hook_method(gameView, motion_methods[i].selector, (IMP)motion_hook);
    original_reset_cursor_rects = (plain_imp)hook_method(gameView, @selector(resetCursorRects),
                                                         (IMP)reset_cursor_rects_hook);

    os_log(log, "Pointer fix installed: the Mac cursor hides over Amiga games, which get real mouse deltas");
}

@end
