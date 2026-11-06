// Mouse pointer for Amiga games, inside the OpenEmu process (see OEAmigaPointer.m).

#import <Cocoa/Cocoa.h>

// OEEvent type of the mouse deltas OEAmigaPointer sends; OEEvent's locationInGameView holds the delta in
// game-screen pixels. OpenEmu never sends mouse events of this type, and OESystemResponder ignores it.
#define OEAmigaMouseDeltaEventType NSEventTypeApplicationDefined

typedef struct {
    CGFloat x, y;  // game-screen pixels not yet sent
} OEAmigaPointerRemainder;

// Mouse motion in view points -> whole game-screen pixels, with the game screen fitted into the view the
// way OEGameLayerView fits it. Fractions carry over in *remainder.
void OEAmigaPointerDelta(OEAmigaPointerRemainder *remainder, CGFloat dx, CGFloat dy, CGSize viewSize,
                         CGSize gameSize, int *outX, int *outY);

// YES when the view is the game view of an Amiga game: the Mac cursor is hidden over it.
BOOL OEAmigaPointerHidesCursorInView(NSView *view);
