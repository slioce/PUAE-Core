#include "test.h"
#include "PUAEMouse.h"

static void track(puae_mouse_tracker *t, int x, int y, int ex, int ey)
{
    int dx = 99, dy = 99;
    puae_mouse_track(t, x, y, &dx, &dy);
    if (dx != ex || dy != ey) {
        fprintf(stderr, "track(%d,%d) -> (%d,%d), expected (%d,%d)\n", x, y, dx, dy, ex, ey);
        test_failures++;
    }
}

static void test_relative_motion(void)
{
    puae_mouse_tracker t = { 0 };
    track(&t, 10, 10, 0, 0);   /* first point: nothing to compare with */
    track(&t, 15, 8, 5, -2);
    track(&t, 15, 8, 0, 0);
}

/* The Mac cursor left the game area and came back elsewhere: no Amiga pointer jump. */
static void test_reentry_jump_is_ignored(void)
{
    puae_mouse_tracker t = { 0 };
    track(&t, 10, 10, 0, 0);
    track(&t, 15, 8, 5, -2);
    track(&t, 200, 8, 0, 0);
    track(&t, 201, 8, 1, 0);
    track(&t, 201, 100, 0, 0);
    track(&t, 201, 101, 0, 1);
}

static void test_fast_but_plausible_motion_passes(void)
{
    puae_mouse_tracker t = { 0 };
    track(&t, 100, 100, 0, 0);
    track(&t, 164, 36, 64, -64);
}

static void test_reset_forgets_last_point(void)
{
    puae_mouse_tracker t = { 0 };
    track(&t, 10, 10, 0, 0);
    puae_mouse_reset(&t);
    track(&t, 50, 50, 0, 0);
    track(&t, 51, 50, 1, 0);
}

static void scale(puae_mouse_tracker *t, int dx, int dy, unsigned w, unsigned h, int ex, int ey)
{
    int ax = 99, ay = 99;
    puae_mouse_scale(t, dx, dy, w, h, &ax, &ay);
    if (ax != ex || ay != ey) {
        fprintf(stderr, "scale(%d,%d @%ux%u) -> (%d,%d), expected (%d,%d)\n", dx, dy, w, h, ax, ay, ex, ey);
        test_failures++;
    }
}

/* The Amiga pointer moves in lores pixels and non-interlaced lines; PUAE shows hires (720) width. */
static void test_scale_to_amiga_pointer_units(void)
{
    puae_mouse_tracker t = { 0 };
    scale(&t, 5, -2, 720, 287, 2, -2);  /* half horizontally, remainder 1 kept */
    scale(&t, 1, 0, 720, 287, 1, 0);    /* remainder used up */
    scale(&t, -3, 0, 720, 287, -1, 0);  /* remainder -1 kept */
    scale(&t, -1, 0, 720, 287, -1, 0);

    puae_mouse_tracker interlaced = { 0 };
    scale(&interlaced, 4, 4, 720, 574, 2, 2);

    puae_mouse_tracker superhires = { 0 };
    scale(&superhires, 8, 0, 1440, 287, 2, 0);

    puae_mouse_tracker lores = { 0 };
    scale(&lores, 3, 3, 360, 287, 3, 3);
}

int main(void)
{
    test_scale_to_amiga_pointer_units();
    test_relative_motion();
    test_reentry_jump_is_ignored();
    test_fast_but_plausible_motion_passes();
    test_reset_forgets_last_point();
    return test_report("test_mouse");
}
