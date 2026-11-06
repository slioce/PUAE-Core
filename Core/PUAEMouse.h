/*
 * The Amiga mouse is relative. OpenEmu itself reports the mouse as absolute positions inside the game
 * screen, clamped to it, so the core can feed PUAE the difference between positions. The Amiga system
 * plugin also sends real mouse deltas (Amiga/OEAmigaPointer.m); once those arrive, the core uses them
 * and ignores the absolute positions, which keep coming for clicks and for older cores.
 */

#ifndef PUAE_MOUSE_H
#define PUAE_MOUSE_H

#include <stdbool.h>

typedef struct {
    int last_x, last_y;
    bool has_last;
    bool relative;     /* deltas arrive through puae_mouse_relative: absolute points are ignored */
    int rem_x, rem_y;  /* screen pixels not yet worth a whole Amiga step */
} puae_mouse_tracker;

/* Motion since the previous point. The first point, or a jump over 64 px on either axis (the cursor
 * left the game area and came back elsewhere), gives 0,0. So does every point in relative mode. */
void puae_mouse_track(puae_mouse_tracker *t, int x, int y, int *dx, int *dy);
void puae_mouse_reset(puae_mouse_tracker *t);

/* Screen-pixel motion -> Amiga mouse counts, so the Amiga pointer keeps pace with the Mac cursor: the
 * pointer moves in lores pixels and non-interlaced lines, while PUAE's screen is usually hires (720)
 * wide, sometimes super-hires or interlaced. Fractions carry over to the next call. */
void puae_mouse_scale(puae_mouse_tracker *t, int dx, int dy, unsigned screen_width, unsigned screen_height,
                      int *amiga_dx, int *amiga_dy);

/* A real mouse delta in game-screen pixels (the space of the absolute points): switches the tracker to
 * relative mode for good and scales like puae_mouse_scale. */
void puae_mouse_relative(puae_mouse_tracker *t, int dx, int dy, unsigned screen_width, unsigned screen_height,
                         int *amiga_dx, int *amiga_dy);

#endif
