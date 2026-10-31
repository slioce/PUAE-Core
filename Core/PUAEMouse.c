#include "PUAEMouse.h"

#include <stdlib.h>

#define MAX_STEP 64

void puae_mouse_track(puae_mouse_tracker *t, int x, int y, int *dx, int *dy)
{
    *dx = *dy = 0;
    if (t->has_last && abs(x - t->last_x) <= MAX_STEP && abs(y - t->last_y) <= MAX_STEP) {
        *dx = x - t->last_x;
        *dy = y - t->last_y;
    }
    t->last_x = x;
    t->last_y = y;
    t->has_last = true;
}

void puae_mouse_reset(puae_mouse_tracker *t)
{
    t->has_last = false;
}

void puae_mouse_scale(puae_mouse_tracker *t, int dx, int dy, unsigned screen_width, unsigned screen_height,
                      int *amiga_dx, int *amiga_dy)
{
    int sx = screen_width >= 1280 ? 4 : screen_width >= 640 ? 2 : 1;
    int sy = screen_height >= 400 ? 2 : 1;
    t->rem_x += dx;
    t->rem_y += dy;
    /* C division truncates toward zero, so the remainder keeps the direction of travel. */
    *amiga_dx = t->rem_x / sx;
    *amiga_dy = t->rem_y / sy;
    t->rem_x -= *amiga_dx * sx;
    t->rem_y -= *amiga_dy * sy;
}
