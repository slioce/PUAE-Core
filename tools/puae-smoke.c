/*
 * Runs a game through the bridge without OpenEmu, building the disk set exactly as PUAEGameCore does.
 *
 *   puae-smoke --bios DIR --system DIR --save DIR [--frames N] [--ppm FILE] [--state-roundtrip]
 *              [--expect-disks N] [--min-nonblack PERCENT] [--press F:input]... [--snap F:file.ppm]...
 *              [--option key=value]... GAME
 *
 * --press holds an input (lmb rmb fire fire2 up down left right space return) for 10 frames from frame F;
 * "moveDX,DY" moves the mouse once.
 *
 * Prints "kickstarts: N", "disks: N", "video: WxH", "state: N bytes", "nonblack: P%"; PUAE's log goes
 * to stderr. Exits non-zero when loading or any expectation fails.
 */

#include "PUAEBridge.h"
#include "PUAEDiskList.h"
#include "PUAESystemDir.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static unsigned long audio_frames;

static void on_audio(void *ctx, const int16_t *frames, size_t count)
{
    (void)ctx;
    (void)frames;
    audio_frames += count;
}

static void on_log(void *ctx, int level, const char *message)
{
    (void)ctx;
    static const char *names[] = { "debug", "info", "warn", "error" };
    fprintf(stderr, "[%s] %s\n", level >= 0 && level <= 3 ? names[level] : "?", message);
}

static int fail(const char *what)
{
    const char *err = puae_bridge_last_error();
    printf("FAIL: %s%s%s\n", what, err ? ": " : "", err ? err : "");
    return 1;
}

static void write_ppm(const char *path, const puae_bridge_video *v)
{
    FILE *f = fopen(path, "wb");
    if (!f)
        return;
    fprintf(f, "P6\n%u %u\n255\n", v->width, v->height);
    for (unsigned y = 0; y < v->height; y++)
        for (unsigned x = 0; x < v->width; x++) {
            uint32_t p = v->frame[(size_t)y * v->buffer_width + x];
            unsigned char rgb[3] = { (p >> 16) & 0xFF, (p >> 8) & 0xFF, p & 0xFF };
            fwrite(rgb, 1, 3, f);
        }
    fclose(f);
}

static double nonblack_percent(const puae_bridge_video *v)
{
    if (!v->width || !v->height)
        return 0;
    size_t lit = 0;
    for (unsigned y = 0; y < v->height; y++)
        for (unsigned x = 0; x < v->width; x++)
            if (v->frame[(size_t)y * v->buffer_width + x] & 0xFFFFFF)
                lit++;
    return 100.0 * (double)lit / ((double)v->width * v->height);
}

static void run_frames(unsigned n)
{
    for (unsigned i = 0; i < n; i++)
        puae_bridge_run_frame();
}

/* Scripted input for the main run: "--press F:what" holds `what` from frame F for PRESS_FRAMES frames,
 * "--snap F:file.ppm" saves the screen at frame F. */
#define PRESS_FRAMES 10
#define MAX_SCRIPT   32

static struct { unsigned frame; const char *what; } presses[MAX_SCRIPT], snaps[MAX_SCRIPT];
static unsigned press_count, snap_count;

static void apply_press(const char *what, bool down)
{
    int dx, dy;
    if (sscanf(what, "move%d,%d", &dx, &dy) == 2) {  /* "moveDX,DY": one mouse motion, at press time */
        if (down)
            puae_bridge_mouse_move(dx, dy);
        return;
    }
    static const struct { const char *name; int joy; int mouse; unsigned key; } inputs[] = {
        { "lmb", -1, RETRO_DEVICE_ID_MOUSE_LEFT, 0 },  { "rmb", -1, RETRO_DEVICE_ID_MOUSE_RIGHT, 0 },
        { "fire", RETRO_DEVICE_ID_JOYPAD_B, -1, 0 },   { "fire2", RETRO_DEVICE_ID_JOYPAD_A, -1, 0 },
        { "up", RETRO_DEVICE_ID_JOYPAD_UP, -1, 0 },    { "down", RETRO_DEVICE_ID_JOYPAD_DOWN, -1, 0 },
        { "left", RETRO_DEVICE_ID_JOYPAD_LEFT, -1, 0 },{ "right", RETRO_DEVICE_ID_JOYPAD_RIGHT, -1, 0 },
        { "space", -1, -1, RETROK_SPACE },             { "return", -1, -1, RETROK_RETURN },
    };
    for (size_t i = 0; i < sizeof(inputs) / sizeof(inputs[0]); i++) {
        if (strcmp(inputs[i].name, what) != 0)
            continue;
        if (inputs[i].joy >= 0)
            puae_bridge_set_joypad(0, (unsigned)inputs[i].joy, down);
        else if (inputs[i].mouse >= 0)
            puae_bridge_set_mouse_button((unsigned)inputs[i].mouse, down);
        else
            puae_bridge_key(inputs[i].key, down);
        return;
    }
    fprintf(stderr, "unknown --press input %s\n", what);
}

static int add_script(const char *arg, unsigned *count, unsigned *frame, const char **what)
{
    const char *colon = strchr(arg, ':');
    if (!colon || *count >= MAX_SCRIPT)
        return -1;
    *frame = (unsigned)atoi(arg);
    *what = colon + 1;
    (*count)++;
    return 0;
}

static void run_scripted_frames(unsigned n)
{
    for (unsigned f = 0; f < n; f++) {
        for (unsigned i = 0; i < press_count; i++) {
            if (presses[i].frame == f)
                apply_press(presses[i].what, true);
            else if (presses[i].frame + PRESS_FRAMES == f)
                apply_press(presses[i].what, false);
        }
        for (unsigned i = 0; i < snap_count; i++)
            if (snaps[i].frame == f)
                write_ppm(snaps[i].what, puae_bridge_video_info());
        puae_bridge_run_frame();
    }
}

/* Sidecar m3u, else the sibling set as a generated playlist, else the file itself. Caller frees. */
static char *load_path_for(const char *game, const char *save_dir)
{
    char *m3u = puae_disk_list_sidecar_m3u(game);
    if (m3u)
        return m3u;

    puae_disk_list list;
    if (puae_disk_list_find(game, &list) != 0 || list.count < 2) {
        if (list.count)
            puae_disk_list_free(&list);
        return strdup(game);
    }
    char *dir = NULL, *name = puae_disk_list_game_name(game);
    asprintf(&dir, "%s/playlists", save_dir);
    mkdir(dir, 0755);
    asprintf(&m3u, "%s/%s.m3u", dir, name);
    int written = puae_disk_list_write_m3u(&list, m3u);
    puae_disk_list_free(&list);
    free(name);
    free(dir);
    if (written != 0) {
        free(m3u);
        return strdup(game);
    }
    return m3u;
}

int main(int argc, char **argv)
{
    const char *bios = NULL, *system = NULL, *save = NULL, *ppm = NULL, *game = NULL;
    unsigned frames = 600, expect_disks = 0;
    double min_nonblack = -1;
    int roundtrip = 0;
    const char *options[2 * MAX_SCRIPT + 1] = { NULL };  /* "key", "value" pairs for the bridge config */
    char option_keys[MAX_SCRIPT][128];
    unsigned option_count = 0;

    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        const char *next = i + 1 < argc ? argv[i + 1] : NULL;
        if (!strcmp(a, "--bios") && next) bios = argv[++i];
        else if (!strcmp(a, "--system") && next) system = argv[++i];
        else if (!strcmp(a, "--save") && next) save = argv[++i];
        else if (!strcmp(a, "--frames") && next) frames = (unsigned)atoi(argv[++i]);
        else if (!strcmp(a, "--ppm") && next) ppm = argv[++i];
        else if (!strcmp(a, "--expect-disks") && next) expect_disks = (unsigned)atoi(argv[++i]);
        else if (!strcmp(a, "--min-nonblack") && next) min_nonblack = atof(argv[++i]);
        else if (!strcmp(a, "--state-roundtrip")) roundtrip = 1;
        else if (!strcmp(a, "--option") && next && option_count < MAX_SCRIPT) {
            const char *pair = argv[++i], *eq = strchr(pair, '=');
            if (!eq || (size_t)(eq - pair) >= sizeof(option_keys[0])) { fprintf(stderr, "bad --option %s\n", pair); return 2; }
            snprintf(option_keys[option_count], sizeof(option_keys[0]), "%.*s", (int)(eq - pair), pair);
            options[2 * option_count] = option_keys[option_count];
            options[2 * option_count + 1] = eq + 1;
            option_count++;
        }
        else if (!strcmp(a, "--press") && next) {
            if (add_script(argv[++i], &press_count, &presses[press_count].frame, &presses[press_count].what) != 0)
                { fprintf(stderr, "bad --press %s\n", argv[i]); return 2; }
        }
        else if (!strcmp(a, "--snap") && next) {
            if (add_script(argv[++i], &snap_count, &snaps[snap_count].frame, &snaps[snap_count].what) != 0)
                { fprintf(stderr, "bad --snap %s\n", argv[i]); return 2; }
        }
        else if (a[0] != '-') game = a;
        else { fprintf(stderr, "unknown argument %s\n", a); return 2; }
    }
    if (!bios || !system || !save || !game) {
        fprintf(stderr, "usage: puae-smoke --bios DIR --system DIR --save DIR [options] GAME\n");
        return 2;
    }
    if (mkdir(save, 0755) != 0 && errno != EEXIST)
        return fail("cannot create save directory");

    int linked = puae_system_dir_link_kickstarts(bios, system);
    printf("kickstarts: %d\n", linked);
    if (linked < 0)
        return fail("cannot prepare system directory");

    char *path = load_path_for(game, save);
    puae_bridge_config config = { .system_dir = system, .save_dir = save, .audio = on_audio, .log = on_log,
                                  .options = options };
    if (puae_bridge_init(&config) != 0)
        return fail("init");
    if (!puae_bridge_load(path))
        return fail("load");
    free(path);

    unsigned disks = puae_bridge_disk_count();
    printf("disks: %u\n", disks);
    if (expect_disks && disks != expect_disks)
        return fail("unexpected disk count");
    if (disks > 1) {
        if (!puae_bridge_set_disk(1) || puae_bridge_disk_index() != 1)
            return fail("cannot switch to disk 2");
        if (!puae_bridge_set_disk(0))
            return fail("cannot switch back to disk 1");
    }

    run_scripted_frames(frames);
    const puae_bridge_video *v = puae_bridge_video_info();
    printf("video: %ux%u (buffer %ux%u, %.3f fps, aspect %.3f)\n", v->width, v->height,
           v->buffer_width, v->buffer_height, v->fps, v->aspect);
    printf("audio: %lu frames\n", audio_frames);

    if (roundtrip) {
        size_t size = puae_bridge_state_size();
        void *state = size ? malloc(size) : NULL;
        if (!state || !puae_bridge_save_state(state, size))
            return fail("save state");
        run_frames(10);
        if (!puae_bridge_load_state(state, size))
            return fail("load state");
        run_frames(10);
        printf("state: %zu bytes\n", size);
        free(state);
    }

    double lit = nonblack_percent(v);
    printf("nonblack: %.1f%%\n", lit);
    if (ppm)
        write_ppm(ppm, v);
    if (min_nonblack >= 0 && lit < min_nonblack)
        return fail("screen is mostly black");

    puae_bridge_deinit();
    printf("ok\n");
    return 0;
}
