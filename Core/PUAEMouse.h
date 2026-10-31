/*
 * OpenEmu reports the mouse as absolute positions inside the game screen, with no deltas and no pointer
 * capture. The Amiga mouse is relative, so the core feeds PUAE the difference between positions.
 */

#ifndef PUAE_MOUSE_H
#define PUAE_MOUSE_H

#include <stdbool.h>

typedef struct {
    int last_x, last_y;
    bool has_last;
    int rem_x, rem_y;  /* screen pixels not yet worth a whole Amiga step */
} puae_mouse_tracker;

/* Motion since the previous point. The first point, or a jump over 64 px on either axis (the cursor
 * left the game area and came back elsewhere), gives 0,0. */
void puae_mouse_track(puae_mouse_tracker *t, int x, int y, int *dx, int *dy);
void puae_mouse_reset(puae_mouse_tracker *t);

/* Screen-pixel motion -> Amiga mouse counts, so the Amiga pointer keeps pace with the Mac cursor: the
 * pointer moves in lores pixels and non-interlaced lines, while PUAE's screen is usually hires (720)
 * wide, sometimes super-hires or interlaced. Fractions carry over to the next call. */
void puae_mouse_scale(puae_mouse_tracker *t, int dx, int dy, unsigned screen_width, unsigned screen_height,
                      int *amiga_dx, int *amiga_dy);

#endif
