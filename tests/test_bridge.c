/* Bridge callbacks, exercised without retro_init or a game. */

#include "test.h"
#include "PUAEBridge.h"

#include <stdlib.h>

static bool env(unsigned cmd, void *data)
{
    return puae_bridge_environment(cmd, data);
}

static void configure(void)
{
    puae_bridge_config config = { .system_dir = "/sys", .save_dir = "/save" };
    puae_bridge_configure(&config);
}

static void test_directories(void)
{
    configure();
    const char *dir = NULL;
    CHECK(env(RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY, &dir));
    CHECK_STR(dir, "/sys");
    dir = NULL;
    CHECK(env(RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY, &dir));
    CHECK_STR(dir, "/save");
}

static void test_variables_use_overrides(void)
{
    configure();
    struct retro_variable vars[] = { { "puae_model", "Model; A500|auto" }, { NULL, NULL } };
    CHECK(env(RETRO_ENVIRONMENT_SET_VARIABLES, vars));

    struct retro_variable var = { "puae_model", NULL };
    CHECK(env(RETRO_ENVIRONMENT_GET_VARIABLE, &var));
    CHECK_STR(var.value, "auto");

    struct retro_variable missing = { "nope", NULL };
    CHECK(!env(RETRO_ENVIRONMENT_GET_VARIABLE, &missing));
}

/* PUAE binds Right Ctrl (gamepad becomes a mouse) and F12 (statusbar) by default; the keyboard is the Amiga's. */
static void test_keyboard_hotkeys_are_unbound(void)
{
    configure();
    struct retro_variable vars[] = {
        { "puae_mapper_mouse_toggle", "Mouse toggle; RETROK_RCTRL|---|RETROK_F11" },
        { "puae_mapper_statusbar", "Statusbar; RETROK_F12|---|RETROK_F11" },
        { NULL, NULL },
    };
    CHECK(env(RETRO_ENVIRONMENT_SET_VARIABLES, vars));
    struct retro_variable toggle = { "puae_mapper_mouse_toggle", NULL }, statusbar = { "puae_mapper_statusbar", NULL };
    CHECK(env(RETRO_ENVIRONMENT_GET_VARIABLE, &toggle));
    CHECK_STR(toggle.value, "---");
    CHECK(env(RETRO_ENVIRONMENT_GET_VARIABLE, &statusbar));
    CHECK_STR(statusbar.value, "---");
}

static const struct retro_variable floppy_vars[] = {
    { "puae_floppy_speed", "Floppy Speed; 100|200|400|800|0" },
    { NULL, NULL },
};

static void test_floppy_speed_defaults_to_turbo(void)
{
    configure();
    CHECK(env(RETRO_ENVIRONMENT_SET_VARIABLES, (void *)floppy_vars));
    struct retro_variable var = { "puae_floppy_speed", NULL };
    CHECK(env(RETRO_ENVIRONMENT_GET_VARIABLE, &var));
    CHECK_STR(var.value, "0");
}

/* PUAE builds its configuration from the options once, in retro_init, so saved choices come with the config. */
static void test_config_options_override_defaults(void)
{
    const char *options[] = { "puae_floppy_speed", "100", NULL };
    puae_bridge_config config = { .system_dir = "/sys", .save_dir = "/save", .options = options };
    puae_bridge_configure(&config);
    env(RETRO_ENVIRONMENT_SET_VARIABLES, (void *)floppy_vars);
    struct retro_variable var = { "puae_floppy_speed", NULL };
    CHECK(env(RETRO_ENVIRONMENT_GET_VARIABLE, &var));
    CHECK_STR(var.value, "100");

    /* A value PUAE doesn't declare falls back to our default, not to PUAE's. */
    const char *bad[] = { "puae_floppy_speed", "123", NULL };
    config.options = bad;
    puae_bridge_configure(&config);
    env(RETRO_ENVIRONMENT_SET_VARIABLES, (void *)floppy_vars);
    CHECK(env(RETRO_ENVIRONMENT_GET_VARIABLE, &var));
    CHECK_STR(var.value, "0");
}

static void test_set_option_takes_effect_at_next_update(void)
{
    configure();
    env(RETRO_ENVIRONMENT_SET_VARIABLES, (void *)floppy_vars);
    bool updated = true;
    CHECK(env(RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE, &updated) && !updated);

    CHECK(puae_bridge_set_option("puae_floppy_speed", "400"));
    CHECK(env(RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE, &updated) && updated);
    CHECK(env(RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE, &updated) && !updated);  /* reported once */
    struct retro_variable var = { "puae_floppy_speed", NULL };
    CHECK(env(RETRO_ENVIRONMENT_GET_VARIABLE, &var));
    CHECK_STR(var.value, "400");

    CHECK(!puae_bridge_set_option("puae_floppy_speed", "123"));  /* not a declared value */
    CHECK(env(RETRO_ENVIRONMENT_GET_VARIABLE, &var));
    CHECK_STR(var.value, "400");
}

static void test_capabilities(void)
{
    configure();
    unsigned version = 99;
    CHECK(env(RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION, &version) && version == 0);
    version = 0;
    CHECK(env(RETRO_ENVIRONMENT_GET_DISK_CONTROL_INTERFACE_VERSION, &version) && version == 1);
    bool dupe = false;
    CHECK(env(RETRO_ENVIRONMENT_GET_CAN_DUPE, &dupe) && dupe);
    CHECK(!env(9999, NULL));
}

static void test_pixel_formats(void)
{
    configure();
    enum retro_pixel_format fmt = RETRO_PIXEL_FORMAT_XRGB8888;
    CHECK(env(RETRO_ENVIRONMENT_SET_PIXEL_FORMAT, &fmt));
    fmt = RETRO_PIXEL_FORMAT_RGB565;
    CHECK(env(RETRO_ENVIRONMENT_SET_PIXEL_FORMAT, &fmt));
    fmt = RETRO_PIXEL_FORMAT_0RGB1555;
    CHECK(!env(RETRO_ENVIRONMENT_SET_PIXEL_FORMAT, &fmt));
}

static void set_av_info(unsigned max_width, unsigned max_height)
{
    struct retro_system_av_info av = {
        .geometry = { .base_width = 720, .base_height = 568, .max_width = max_width, .max_height = max_height, .aspect_ratio = 4.0f / 3.0f },
        .timing = { .fps = 49.920410, .sample_rate = 44100 },
    };
    CHECK(env(RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO, &av));
}

static void test_av_info_sizes_buffer(void)
{
    configure();
    set_av_info(720, 576);
    const puae_bridge_video *v = puae_bridge_video_info();
    CHECK(v->buffer_width >= 1440 && v->buffer_height >= 576);
    CHECK(v->fps > 49.9 && v->fps < 50.0);
    CHECK(v->sample_rate == 44100);
    CHECK(v->frame != NULL);
}

static void test_rgb565_frames_become_xrgb8888(void)
{
    configure();
    set_av_info(720, 576);
    enum retro_pixel_format fmt = RETRO_PIXEL_FORMAT_RGB565;
    env(RETRO_ENVIRONMENT_SET_PIXEL_FORMAT, &fmt);

    uint16_t pixels[2][4] = { { 0xF800, 0x07E0, 0x001F, 0xFFFF }, { 0, 0, 0, 0 } };
    puae_bridge_video_refresh(pixels, 4, 2, sizeof(pixels[0]));
    const puae_bridge_video *v = puae_bridge_video_info();
    CHECK(v->width == 4 && v->height == 2);
    CHECK(v->frame[0] == 0x00FF0000);
    CHECK(v->frame[1] == 0x0000FF00);
    CHECK(v->frame[2] == 0x000000FF);
    CHECK(v->frame[3] == 0x00FFFFFF);
}

static void test_xrgb8888_frames_are_copied(void)
{
    configure();
    set_av_info(720, 576);
    enum retro_pixel_format fmt = RETRO_PIXEL_FORMAT_XRGB8888;
    env(RETRO_ENVIRONMENT_SET_PIXEL_FORMAT, &fmt);

    uint32_t pixels[2] = { 0x00123456, 0x00ABCDEF };
    puae_bridge_video_refresh(pixels, 2, 1, sizeof(pixels));
    const puae_bridge_video *v = puae_bridge_video_info();
    CHECK(v->width == 2 && v->height == 1);
    CHECK(v->frame[0] == 0x00123456 && v->frame[1] == 0x00ABCDEF);
}

static void test_dupe_frame_keeps_last_image(void)
{
    configure();
    set_av_info(720, 576);
    enum retro_pixel_format fmt = RETRO_PIXEL_FORMAT_XRGB8888;
    env(RETRO_ENVIRONMENT_SET_PIXEL_FORMAT, &fmt);

    uint32_t pixels[2] = { 0x00112233, 0x00445566 };
    puae_bridge_video_refresh(pixels, 2, 1, sizeof(pixels));
    puae_bridge_video_refresh(NULL, 640, 480, 0);
    const puae_bridge_video *v = puae_bridge_video_info();
    CHECK(v->width == 2 && v->height == 1);
    CHECK(v->frame[0] == 0x00112233);
}

static void test_oversized_frame_is_clipped(void)
{
    configure();
    set_av_info(720, 576);
    enum retro_pixel_format fmt = RETRO_PIXEL_FORMAT_XRGB8888;
    env(RETRO_ENVIRONMENT_SET_PIXEL_FORMAT, &fmt);

    const puae_bridge_video *v = puae_bridge_video_info();
    unsigned w = v->buffer_width + 16, h = v->buffer_height + 16;
    uint32_t *big = calloc((size_t)w * h, sizeof(uint32_t));
    big[0] = 0x00FEDCBA;
    puae_bridge_video_refresh(big, w, h, (size_t)w * sizeof(uint32_t));
    CHECK(v->width == v->buffer_width && v->height == v->buffer_height);
    CHECK(v->frame[0] == 0x00FEDCBA);
    free(big);
}

static void test_joypad_state(void)
{
    configure();
    puae_bridge_set_joypad(0, RETRO_DEVICE_ID_JOYPAD_B, true);
    CHECK(puae_bridge_input_state(0, RETRO_DEVICE_JOYPAD, 0, RETRO_DEVICE_ID_JOYPAD_B) == 1);
    CHECK(puae_bridge_input_state(1, RETRO_DEVICE_JOYPAD, 0, RETRO_DEVICE_ID_JOYPAD_B) == 0);
    puae_bridge_set_joypad(0, RETRO_DEVICE_ID_JOYPAD_B, false);
    CHECK(puae_bridge_input_state(0, RETRO_DEVICE_JOYPAD, 0, RETRO_DEVICE_ID_JOYPAD_B) == 0);
}

static void test_mouse_motion_is_latched_at_poll(void)
{
    configure();
    puae_bridge_mouse_move(3, -2);
    puae_bridge_mouse_move(3, -2);
    CHECK(puae_bridge_input_state(0, RETRO_DEVICE_MOUSE, 0, RETRO_DEVICE_ID_MOUSE_X) == 0);
    puae_bridge_input_poll();
    CHECK(puae_bridge_input_state(0, RETRO_DEVICE_MOUSE, 0, RETRO_DEVICE_ID_MOUSE_X) == 6);
    CHECK(puae_bridge_input_state(0, RETRO_DEVICE_MOUSE, 0, RETRO_DEVICE_ID_MOUSE_Y) == -4);
    CHECK(puae_bridge_input_state(1, RETRO_DEVICE_MOUSE, 0, RETRO_DEVICE_ID_MOUSE_X) == 0);
    puae_bridge_input_poll();
    CHECK(puae_bridge_input_state(0, RETRO_DEVICE_MOUSE, 0, RETRO_DEVICE_ID_MOUSE_X) == 0);

    puae_bridge_set_mouse_button(RETRO_DEVICE_ID_MOUSE_LEFT, true);
    CHECK(puae_bridge_input_state(0, RETRO_DEVICE_MOUSE, 0, RETRO_DEVICE_ID_MOUSE_LEFT) == 1);
    CHECK(puae_bridge_input_state(0, RETRO_DEVICE_MOUSE, 0, RETRO_DEVICE_ID_MOUSE_RIGHT) == 0);
}

static bool key_down_seen;
static unsigned key_seen;

static void keyboard_event(bool down, unsigned keycode, uint32_t character, uint16_t modifiers)
{
    (void)character;
    (void)modifiers;
    key_down_seen = down;
    key_seen = keycode;
}

static void test_keys_reach_callback_and_polling(void)
{
    configure();
    struct retro_keyboard_callback cb = { keyboard_event };
    CHECK(env(RETRO_ENVIRONMENT_SET_KEYBOARD_CALLBACK, &cb));

    puae_bridge_key(RETROK_a, true);
    puae_bridge_input_poll();
    CHECK(key_down_seen && key_seen == RETROK_a);
    CHECK(puae_bridge_input_state(0, RETRO_DEVICE_KEYBOARD, 0, RETROK_a) == 1);

    puae_bridge_key(RETROK_a, false);
    puae_bridge_input_poll();
    CHECK(!key_down_seen && key_seen == RETROK_a);
    CHECK(puae_bridge_input_state(0, RETRO_DEVICE_KEYBOARD, 0, RETROK_a) == 0);
}

int main(void)
{
    test_directories();
    test_variables_use_overrides();
    test_keyboard_hotkeys_are_unbound();
    test_floppy_speed_defaults_to_turbo();
    test_config_options_override_defaults();
    test_set_option_takes_effect_at_next_update();
    test_capabilities();
    test_pixel_formats();
    test_av_info_sizes_buffer();
    test_rgb565_frames_become_xrgb8888();
    test_xrgb8888_frames_are_copied();
    test_dupe_frame_keeps_last_image();
    test_oversized_frame_is_clipped();
    test_joypad_state();
    test_mouse_motion_is_latched_at_poll();
    test_keys_reach_callback_and_polling();
    return test_report("test_bridge");
}
