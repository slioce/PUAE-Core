// OEAmigaPointer against stand-ins for OpenEmuKit's OEGameLayerView and OpenEmu's OEGameViewController,
// which carry the real runtime names so the +load hook finds them as it does in the app.

#import <Cocoa/Cocoa.h>
@import OpenEmuSystem;
#include "test.h"
#import "OEAmigaPointer.h"

static NSMutableArray *calls;

@interface _TtC10OpenEmuKit15OEGameLayerView : NSView
@end

@implementation _TtC10OpenEmuKit15OEGameLayerView
- (void)mouseMoved:(NSEvent *)event { [calls addObject:@"stock mouseMoved"]; }
- (void)mouseDragged:(NSEvent *)event { [calls addObject:@"stock mouseDragged"]; }
- (void)rightMouseDragged:(NSEvent *)event { [calls addObject:@"stock rightMouseDragged"]; }
- (void)otherMouseDragged:(NSEvent *)event { [calls addObject:@"stock otherMouseDragged"]; }
@end

@interface OEGameViewController : NSViewController
@property (nonatomic, copy) NSString *systemIdentifier;
@property (nonatomic) CGSize defaultScreenSize;
@property (nonatomic, strong) id document;
@end

@implementation OEGameViewController
{
    NSString *_systemIdentifier;
}

// The real getter force-unwraps the (weak) document.
- (NSString *)systemIdentifier
{
    if (!self.document) {
        fprintf(stderr, "systemIdentifier read without a document (crashes in OpenEmu)\n");
        test_failures++;
    }
    return _systemIdentifier;
}

- (void)setSystemIdentifier:(NSString *)systemIdentifier
{
    _systemIdentifier = [systemIdentifier copy];
}

- (void)gameView:(id)gameView didReceiveMouseEvent:(OEEvent *)event
{
    [calls addObject:[NSString stringWithFormat:@"delta %ld %d,%d", (long)event.type,
                                                event.locationInGameView.x, event.locationInGameView.y]];
}
@end

static NSString *delta_call(int x, int y)
{
    return [NSString stringWithFormat:@"delta %ld %d,%d", (long)OEAmigaMouseDeltaEventType, x, y];
}

static NSEvent *motion(CGEventType type, int64_t dx, int64_t dy)
{
    CGEventRef cg = CGEventCreateMouseEvent(NULL, type, CGPointMake(100, 100), kCGMouseButtonLeft);
    CGEventSetIntegerValueField(cg, kCGMouseEventDeltaX, dx);
    CGEventSetIntegerValueField(cg, kCGMouseEventDeltaY, dy);
    NSEvent *event = [NSEvent eventWithCGEvent:cg];
    CFRelease(cg);
    return event;
}

// A game view inside its controller's view, as GameViewController sets them up.
static _TtC10OpenEmuKit15OEGameLayerView *make_game_view(OEGameViewController *controller, NSSize size)
{
    controller.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    _TtC10OpenEmuKit15OEGameLayerView *view =
        [[_TtC10OpenEmuKit15OEGameLayerView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    [controller.view addSubview:view];
    return view;
}

static void check_calls(NSArray *expected)
{
    if (![calls isEqualToArray:expected]) {
        fprintf(stderr, "calls %s, expected %s\n", calls.description.UTF8String, expected.description.UTF8String);
        test_failures++;
    }
    [calls removeAllObjects];
}

static void delta(OEAmigaPointerRemainder *r, CGFloat dx, CGFloat dy, CGSize view, CGSize game, int ex, int ey)
{
    int x = 99, y = 99;
    OEAmigaPointerDelta(r, dx, dy, view, game, &x, &y);
    if (x != ex || y != ey) {
        fprintf(stderr, "delta(%g,%g) -> (%d,%d), expected (%d,%d)\n", dx, dy, x, y, ex, ey);
        test_failures++;
    }
}

// The game screen is fitted in the view like OEGameLayerView does it: the narrower side sets the scale.
static void test_delta_math(void)
{
    OEAmigaPointerRemainder r = { 0 };
    delta(&r, 3, -3, CGSizeMake(1440, 1080), CGSizeMake(720, 540), 1, -1);  // 2 points per pixel, 0.5 kept
    delta(&r, 1, -1, CGSizeMake(1440, 1080), CGSizeMake(720, 540), 1, -1);  // remainder used up
    delta(&r, 0.5, 0, CGSizeMake(1440, 1080), CGSizeMake(720, 540), 0, 0);

    OEAmigaPointerRemainder letterbox = { 0 };
    delta(&letterbox, 4, 4, CGSizeMake(1920, 1080), CGSizeMake(720, 540), 2, 2);

    OEAmigaPointerRemainder empty = { 0 };
    delta(&empty, 4, 4, CGSizeMake(1440, 1080), CGSizeZero, 0, 0);
    delta(&empty, 4, 4, CGSizeZero, CGSizeMake(720, 540), 0, 0);
    CHECK(empty.x == 0 && empty.y == 0);
}

static void test_amiga_view_sends_delta_before_stock_event(void)
{
    OEGameViewController *controller = [OEGameViewController new];
    controller.document = [NSObject new];
    controller.systemIdentifier = @"openemu.system.amiga";
    controller.defaultScreenSize = CGSizeMake(720, 540);
    _TtC10OpenEmuKit15OEGameLayerView *view = make_game_view(controller, NSMakeSize(1440, 1080));

    NSEvent *event = motion(kCGEventMouseMoved, 4, -6);
    CHECK(event.deltaX == 4 && event.deltaY == -6);
    [view mouseMoved:event];
    check_calls(@[ delta_call(2, -3), @"stock mouseMoved" ]);

    [view mouseDragged:motion(kCGEventLeftMouseDragged, 2, 0)];
    check_calls(@[ delta_call(1, 0), @"stock mouseDragged" ]);
    [view rightMouseDragged:motion(kCGEventRightMouseDragged, 0, 2)];
    check_calls(@[ delta_call(0, 1), @"stock rightMouseDragged" ]);
    [view otherMouseDragged:motion(kCGEventOtherMouseDragged, -2, 0)];
    check_calls(@[ delta_call(-1, 0), @"stock otherMouseDragged" ]);

    // Less than a game pixel: nothing extra to send until it adds up.
    [view mouseMoved:motion(kCGEventMouseMoved, 1, 0)];
    check_calls(@[ @"stock mouseMoved" ]);
    [view mouseMoved:motion(kCGEventMouseMoved, 1, 0)];
    check_calls(@[ delta_call(1, 0), @"stock mouseMoved" ]);
}

static void test_other_systems_are_untouched(void)
{
    OEGameViewController *controller = [OEGameViewController new];
    controller.document = [NSObject new];
    controller.systemIdentifier = @"openemu.system.nes";
    controller.defaultScreenSize = CGSizeMake(256, 240);
    _TtC10OpenEmuKit15OEGameLayerView *view = make_game_view(controller, NSMakeSize(512, 480));

    [view mouseMoved:motion(kCGEventMouseMoved, 8, 8)];
    check_calls(@[ @"stock mouseMoved" ]);
}

// Without a document (the game is closing) the view isn't classified, and isn't cached either.
static void test_view_without_document(void)
{
    OEGameViewController *controller = [OEGameViewController new];
    controller.systemIdentifier = @"openemu.system.amiga";
    controller.defaultScreenSize = CGSizeMake(720, 540);
    _TtC10OpenEmuKit15OEGameLayerView *view = make_game_view(controller, NSMakeSize(720, 540));

    [view mouseMoved:motion(kCGEventMouseMoved, 2, 0)];
    check_calls(@[ @"stock mouseMoved" ]);

    controller.document = [NSObject new];
    [view mouseMoved:motion(kCGEventMouseMoved, 2, 0)];
    check_calls(@[ delta_call(2, 0), @"stock mouseMoved" ]);
}

// A view outside any game view controller: stock behaviour.
static void test_view_without_controller(void)
{
    _TtC10OpenEmuKit15OEGameLayerView *view =
        [[_TtC10OpenEmuKit15OEGameLayerView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    [view mouseMoved:motion(kCGEventMouseMoved, 2, 0)];
    check_calls(@[ @"stock mouseMoved" ]);
}

static void test_cursor_hidden_only_over_amiga_views(void)
{
    OEGameViewController *amiga = [OEGameViewController new];
    amiga.document = [NSObject new];
    amiga.systemIdentifier = @"openemu.system.amiga";
    _TtC10OpenEmuKit15OEGameLayerView *amigaView = make_game_view(amiga, NSMakeSize(720, 540));
    CHECK(OEAmigaPointerHidesCursorInView(amigaView));

    OEGameViewController *nes = [OEGameViewController new];
    nes.document = [NSObject new];
    nes.systemIdentifier = @"openemu.system.nes";
    _TtC10OpenEmuKit15OEGameLayerView *nesView = make_game_view(nes, NSMakeSize(512, 480));
    CHECK(!OEAmigaPointerHidesCursorInView(nesView));

    CHECK([_TtC10OpenEmuKit15OEGameLayerView instancesRespondToSelector:@selector(resetCursorRects)]);
    [amigaView resetCursorRects];  // no window: must not crash
    [nesView resetCursorRects];
}

int main(void)
{
    @autoreleasepool {
        calls = [NSMutableArray array];
        test_delta_math();
        test_amiga_view_sends_delta_before_stock_event();
        test_other_systems_are_untouched();
        test_view_without_document();
        test_view_without_controller();
        test_cursor_hidden_only_over_amiga_views();
    }
    return test_report("test_pointer");
}
