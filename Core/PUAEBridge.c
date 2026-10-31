#include "PUAEBridge.h"
#include "PUAEOptions.h"

#include <pthread.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Large enough for super-hires interlaced PAL; frames beyond it are clipped. */
#define MIN_BUFFER_WIDTH  1440
#define MIN_BUFFER_HEIGHT 576
#define KEY_QUEUE_SIZE    64

static const struct { const char *key, *value; } option_overrides[] = {
    { "puae_model", "auto" },
    { "puae_use_whdload", "files" },
    { "puae_kickstart", "auto" },
    { "puae_gfx_colors", "24bit" },
    { "puae_physicalmouse", "enabled" },
    { "puae_floppy_write_redirect", "enabled" },
    { "puae_floppy_speed", "0" },  /* Turbo; switchable from the core's display-mode menu */
    /* The keyboard belongs to the Amiga: no PUAE hotkeys on it (Right Ctrl would turn the pad into a mouse). */
    { "puae_mapper_mouse_toggle", "---" },
    { "puae_mapper_statusbar", "---" },
};

static struct {
    char *system_dir, *save_dir;
    void *ctx;
    void (*audio)(void *ctx, const int16_t *frames, size_t count);
    void (*log)(void *ctx, int level, const char *message);

    puae_options *options;
    char **config_options;  /* key, value pairs from puae_bridge_config.options */
    size_t config_option_count;
    enum retro_pixel_format pixel_format;
    float reported_aspect;
    uint32_t *frame;
    puae_bridge_video video;

    retro_keyboard_event_t keyboard;
    struct retro_disk_control_ext_callback disk;
    char last_error[512];
    bool has_error, initialized, loaded;
    bool unknown_logged[128];

    atomic_bool options_updated;
    atomic_bool joypad[2][16];
    atomic_bool mouse_buttons[16];
    atomic_int mouse_dx, mouse_dy;
    int16_t latched_dx, latched_dy;
    bool keys[RETROK_LAST];
} bridge;

/* Outside the struct so configure's reset never clobbers it. */
static pthread_mutex_t key_lock = PTHREAD_MUTEX_INITIALIZER;
static struct { unsigned key; bool down; } key_queue[KEY_QUEUE_SIZE];
static size_t key_queue_count;

static void log_message(enum retro_log_level level, const char *fmt, ...)
{
    char buf[1024];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);

    size_t len = strlen(buf);
    while (len && (buf[len - 1] == '\n' || buf[len - 1] == '\r'))
        buf[--len] = '\0';
    if (level == RETRO_LOG_ERROR) {
        snprintf(bridge.last_error, sizeof(bridge.last_error), "%s", buf);
        bridge.has_error = true;
    }
    if (bridge.log)
        bridge.log(bridge.ctx, level, buf);
}

static void ensure_buffer(unsigned width, unsigned height)
{
    if (bridge.frame)
        return;
    unsigned w = width > MIN_BUFFER_WIDTH ? width : MIN_BUFFER_WIDTH;
    unsigned h = height > MIN_BUFFER_HEIGHT ? height : MIN_BUFFER_HEIGHT;
    bridge.frame = calloc((size_t)w * h, sizeof(uint32_t));
    if (!bridge.frame)
        return;
    bridge.video.buffer_width = w;
    bridge.video.buffer_height = h;
    bridge.video.frame = bridge.frame;
}

static void apply_av_info(const struct retro_system_av_info *av)
{
    bridge.video.fps = av->timing.fps;
    bridge.video.sample_rate = av->timing.sample_rate;
    bridge.reported_aspect = av->geometry.aspect_ratio;
    ensure_buffer(av->geometry.max_width, av->geometry.max_height);
}

static const char *default_override(const char *key)
{
    for (size_t i = 0; i < sizeof(option_overrides) / sizeof(option_overrides[0]); i++)
        if (strcmp(option_overrides[i].key, key) == 0)
            return option_overrides[i].value;
    return NULL;
}

/* Drop overrides PUAE doesn't declare, so GET_VARIABLE never hands it a value it can't parse. A bad
 * value from the config falls back to the bridge's default for that key. */
static void validate_overrides(void)
{
    for (size_t i = 0; i < sizeof(option_overrides) / sizeof(option_overrides[0]); i++) {
        const char *key = option_overrides[i].key, *value = option_overrides[i].value;
        if (!puae_options_is_valid(bridge.options, key, value)) {
            log_message(RETRO_LOG_WARN, "Option override %s=%s is not declared by PUAE, ignoring it", key, value);
            puae_options_set_override(bridge.options, key, NULL);
        }
    }
    for (size_t i = 0; i < bridge.config_option_count; i++) {
        const char *key = bridge.config_options[2 * i], *value = bridge.config_options[2 * i + 1];
        if (puae_options_is_valid(bridge.options, key, value))
            continue;
        const char *fallback = default_override(key);
        log_message(RETRO_LOG_WARN, "Option %s=%s is not declared by PUAE, ignoring it", key, value);
        puae_options_set_override(bridge.options, key,
                                  fallback && puae_options_is_valid(bridge.options, key, fallback) ? fallback : NULL);
    }
}

bool puae_bridge_environment(unsigned cmd, void *data)
{
    switch (cmd) {
    case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
        *(const char **)data = bridge.system_dir;
        return bridge.system_dir != NULL;
    case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
        *(const char **)data = bridge.save_dir;
        return bridge.save_dir != NULL;
    case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
        *(unsigned *)data = 0;  /* PUAE then falls back to SET_VARIABLES */
        return true;
    case RETRO_ENVIRONMENT_SET_VARIABLES:
        puae_options_set_variables(bridge.options, data);
        validate_overrides();
        return true;
    case RETRO_ENVIRONMENT_GET_VARIABLE: {
        struct retro_variable *var = data;
        var->value = var->key ? puae_options_get(bridge.options, var->key) : NULL;
        return var->value != NULL;
    }
    case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
        *(bool *)data = atomic_exchange(&bridge.options_updated, false);
        return true;
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
        enum retro_pixel_format fmt = *(const enum retro_pixel_format *)data;
        if (fmt != RETRO_PIXEL_FORMAT_XRGB8888 && fmt != RETRO_PIXEL_FORMAT_RGB565)
            return false;
        bridge.pixel_format = fmt;
        return true;
    }
    case RETRO_ENVIRONMENT_SET_GEOMETRY:
        bridge.reported_aspect = ((const struct retro_game_geometry *)data)->aspect_ratio;
        return true;
    case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO:
        apply_av_info(data);
        return true;
    case RETRO_ENVIRONMENT_SET_KEYBOARD_CALLBACK:
        bridge.keyboard = ((const struct retro_keyboard_callback *)data)->callback;
        return true;
    case RETRO_ENVIRONMENT_GET_DISK_CONTROL_INTERFACE_VERSION:
        *(unsigned *)data = 1;
        return true;
    case RETRO_ENVIRONMENT_SET_DISK_CONTROL_INTERFACE:
        memset(&bridge.disk, 0, sizeof(bridge.disk));
        memcpy(&bridge.disk, data, sizeof(struct retro_disk_control_callback));
        return true;
    case RETRO_ENVIRONMENT_SET_DISK_CONTROL_EXT_INTERFACE:
        bridge.disk = *(const struct retro_disk_control_ext_callback *)data;
        return true;
    case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
        ((struct retro_log_callback *)data)->log = log_message;
        return true;
    case RETRO_ENVIRONMENT_SET_MESSAGE:
        log_message(RETRO_LOG_INFO, "Message: %s", ((const struct retro_message *)data)->msg);
        return true;
    case RETRO_ENVIRONMENT_SET_MESSAGE_EXT:
        log_message(RETRO_LOG_INFO, "Message: %s", ((const struct retro_message_ext *)data)->msg);
        return true;
    case RETRO_ENVIRONMENT_GET_CAN_DUPE:
        *(bool *)data = true;
        return true;
    case RETRO_ENVIRONMENT_SHUTDOWN:
        log_message(RETRO_LOG_WARN, "PUAE requested shutdown");
        return true;
    case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
    case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
    case RETRO_ENVIRONMENT_SET_MEMORY_MAPS:
        return true;  /* accepted, not needed */
    default: {
        unsigned slot = cmd & 0xFFFF;
        if (slot >= sizeof(bridge.unknown_logged) || !bridge.unknown_logged[slot]) {
            log_message(RETRO_LOG_DEBUG, "Unhandled environment command %u", cmd);
            if (slot < sizeof(bridge.unknown_logged))
                bridge.unknown_logged[slot] = true;
        }
        return false;
    }
    }
}

static inline uint32_t rgb565_to_xrgb8888(uint16_t p)
{
    uint32_t r = (p >> 11) & 0x1F, g = (p >> 5) & 0x3F, b = p & 0x1F;
    r = (r << 3) | (r >> 2);
    g = (g << 2) | (g >> 4);
    b = (b << 3) | (b >> 2);
    return (r << 16) | (g << 8) | b;
}

void puae_bridge_video_refresh(const void *data, unsigned width, unsigned height, size_t pitch)
{
    if (!data)
        return;  /* duplicate frame: keep the last one */
    ensure_buffer(width, height);
    if (!bridge.frame)
        return;

    unsigned w = width < bridge.video.buffer_width ? width : bridge.video.buffer_width;
    unsigned h = height < bridge.video.buffer_height ? height : bridge.video.buffer_height;
    for (unsigned y = 0; y < h; y++) {
        const uint8_t *src = (const uint8_t *)data + (size_t)y * pitch;
        uint32_t *dst = bridge.frame + (size_t)y * bridge.video.buffer_width;
        if (bridge.pixel_format == RETRO_PIXEL_FORMAT_XRGB8888) {
            memcpy(dst, src, (size_t)w * sizeof(uint32_t));
        } else {
            const uint16_t *row = (const uint16_t *)src;
            for (unsigned x = 0; x < w; x++)
                dst[x] = rgb565_to_xrgb8888(row[x]);
        }
    }
    bridge.video.width = w;
    bridge.video.height = h;
    bridge.video.aspect = bridge.reported_aspect > 0 ? bridge.reported_aspect : (float)w / (float)h;
}

static void audio_sample(int16_t left, int16_t right)
{
    int16_t frame[2] = { left, right };
    if (bridge.audio)
        bridge.audio(bridge.ctx, frame, 1);
}

static size_t audio_sample_batch(const int16_t *data, size_t frames)
{
    if (bridge.audio)
        bridge.audio(bridge.ctx, data, frames);
    return frames;
}

static uint16_t key_modifiers(void)
{
    uint16_t mods = 0;
    if (bridge.keys[RETROK_LSHIFT] || bridge.keys[RETROK_RSHIFT])
        mods |= RETROKMOD_SHIFT;
    if (bridge.keys[RETROK_LCTRL] || bridge.keys[RETROK_RCTRL])
        mods |= RETROKMOD_CTRL;
    if (bridge.keys[RETROK_LALT] || bridge.keys[RETROK_RALT])
        mods |= RETROKMOD_ALT;
    if (bridge.keys[RETROK_LSUPER] || bridge.keys[RETROK_RSUPER])
        mods |= RETROKMOD_META;
    return mods;
}

void puae_bridge_input_poll(void)
{
    bridge.latched_dx = (int16_t)atomic_exchange(&bridge.mouse_dx, 0);
    bridge.latched_dy = (int16_t)atomic_exchange(&bridge.mouse_dy, 0);

    pthread_mutex_lock(&key_lock);
    size_t count = key_queue_count;
    __typeof__(key_queue[0]) events[KEY_QUEUE_SIZE];
    memcpy(events, key_queue, count * sizeof(events[0]));
    key_queue_count = 0;
    pthread_mutex_unlock(&key_lock);

    for (size_t i = 0; i < count; i++) {
        bridge.keys[events[i].key] = events[i].down;
        if (bridge.keyboard)
            bridge.keyboard(events[i].down, events[i].key, 0, key_modifiers());
    }
}

int16_t puae_bridge_input_state(unsigned port, unsigned device, unsigned index, unsigned id)
{
    (void)index;
    switch (device & RETRO_DEVICE_MASK) {
    case RETRO_DEVICE_JOYPAD:
        return port < 2 && id < 16 ? atomic_load(&bridge.joypad[port][id]) : 0;
    case RETRO_DEVICE_MOUSE:
        if (port != 0)
            return 0;
        if (id == RETRO_DEVICE_ID_MOUSE_X)
            return bridge.latched_dx;
        if (id == RETRO_DEVICE_ID_MOUSE_Y)
            return bridge.latched_dy;
        return id < 16 ? atomic_load(&bridge.mouse_buttons[id]) : 0;
    case RETRO_DEVICE_KEYBOARD:
        return id < RETROK_LAST ? bridge.keys[id] : 0;
    default:
        return 0;
    }
}

void puae_bridge_configure(const puae_bridge_config *config)
{
    free(bridge.system_dir);
    free(bridge.save_dir);
    free(bridge.frame);
    puae_options_destroy(bridge.options);
    for (size_t i = 0; i < 2 * bridge.config_option_count; i++)
        free(bridge.config_options[i]);
    free(bridge.config_options);
    memset(&bridge, 0, sizeof(bridge));
    pthread_mutex_lock(&key_lock);
    key_queue_count = 0;
    pthread_mutex_unlock(&key_lock);

    bridge.system_dir = config->system_dir ? strdup(config->system_dir) : NULL;
    bridge.save_dir = config->save_dir ? strdup(config->save_dir) : NULL;
    bridge.ctx = config->ctx;
    bridge.audio = config->audio;
    bridge.log = config->log;
    bridge.pixel_format = RETRO_PIXEL_FORMAT_0RGB1555;
    bridge.options = puae_options_create();
    for (size_t i = 0; i < sizeof(option_overrides) / sizeof(option_overrides[0]); i++)
        puae_options_set_override(bridge.options, option_overrides[i].key, option_overrides[i].value);

    size_t pairs = 0;
    while (config->options && config->options[2 * pairs] && config->options[2 * pairs + 1])
        pairs++;
    bridge.config_options = pairs ? calloc(2 * pairs, sizeof(char *)) : NULL;
    for (size_t i = 0; bridge.config_options && i < pairs; i++) {
        bridge.config_options[2 * i] = strdup(config->options[2 * i]);
        bridge.config_options[2 * i + 1] = strdup(config->options[2 * i + 1]);
        puae_options_set_override(bridge.options, config->options[2 * i], config->options[2 * i + 1]);
    }
    bridge.config_option_count = bridge.config_options ? pairs : 0;
}

int puae_bridge_init(const puae_bridge_config *config)
{
    puae_bridge_configure(config);
    retro_set_environment(puae_bridge_environment);
    retro_set_video_refresh(puae_bridge_video_refresh);
    retro_set_audio_sample(audio_sample);
    retro_set_audio_sample_batch(audio_sample_batch);
    retro_set_input_poll(puae_bridge_input_poll);
    retro_set_input_state(puae_bridge_input_state);
    retro_init();
    bridge.initialized = true;
    return 0;
}

bool puae_bridge_load(const char *path)
{
    bridge.has_error = false;
    bridge.last_error[0] = '\0';

    struct retro_game_info info = { .path = path };
    if (!retro_load_game(&info))
        return false;
    bridge.loaded = true;

    /* PUAE only logs a missing Kickstart and boots without it; for us that is a failed load. */
    if (bridge.has_error && strcasestr(bridge.last_error, "kickstart"))
        return false;

    struct retro_system_av_info av;
    memset(&av, 0, sizeof(av));
    retro_get_system_av_info(&av);
    apply_av_info(&av);
    retro_set_controller_port_device(0, RETRO_DEVICE_JOYPAD);
    retro_set_controller_port_device(1, RETRO_DEVICE_JOYPAD);
    return true;
}

void puae_bridge_run_frame(void)
{
    retro_run();
}

void puae_bridge_reset(void)
{
    retro_reset();
}

void puae_bridge_deinit(void)
{
    if (bridge.loaded)
        retro_unload_game();
    if (bridge.initialized)
        retro_deinit();
    bridge.loaded = bridge.initialized = false;
}

const puae_bridge_video *puae_bridge_video_info(void)
{
    return &bridge.video;
}

const char *puae_bridge_last_error(void)
{
    return bridge.has_error ? bridge.last_error : NULL;
}

void puae_bridge_set_joypad(unsigned port, unsigned retro_id, bool pressed)
{
    if (port < 2 && retro_id < 16)
        atomic_store(&bridge.joypad[port][retro_id], pressed);
}

void puae_bridge_mouse_move(int dx, int dy)
{
    atomic_fetch_add(&bridge.mouse_dx, dx);
    atomic_fetch_add(&bridge.mouse_dy, dy);
}

void puae_bridge_set_mouse_button(unsigned retro_id, bool pressed)
{
    if (retro_id < 16)
        atomic_store(&bridge.mouse_buttons[retro_id], pressed);
}

void puae_bridge_key(unsigned retrok, bool down)
{
    if (retrok == RETROK_UNKNOWN || retrok >= RETROK_LAST)
        return;
    pthread_mutex_lock(&key_lock);
    if (key_queue_count < KEY_QUEUE_SIZE) {
        key_queue[key_queue_count].key = retrok;
        key_queue[key_queue_count].down = down;
        key_queue_count++;
    }
    pthread_mutex_unlock(&key_lock);
}

bool puae_bridge_set_option(const char *key, const char *value)
{
    if (!bridge.options || !puae_options_is_valid(bridge.options, key, value))
        return false;
    puae_options_set_override(bridge.options, key, value);
    atomic_store(&bridge.options_updated, true);
    return true;
}

unsigned puae_bridge_disk_count(void)
{
    return bridge.disk.get_num_images ? bridge.disk.get_num_images() : 0;
}

unsigned puae_bridge_disk_index(void)
{
    return bridge.disk.get_image_index ? bridge.disk.get_image_index() : 0;
}

bool puae_bridge_set_disk(unsigned index)
{
    if (!bridge.disk.set_eject_state || !bridge.disk.set_image_index || index >= puae_bridge_disk_count())
        return false;
    if (!bridge.disk.set_eject_state(true))
        return false;
    bool ok = bridge.disk.set_image_index(index);
    return bridge.disk.set_eject_state(false) && ok;
}

size_t puae_bridge_state_size(void)
{
    return retro_serialize_size();
}

bool puae_bridge_save_state(void *buffer, size_t size)
{
    return retro_serialize(buffer, size);
}

bool puae_bridge_load_state(const void *buffer, size_t size)
{
    return retro_unserialize(buffer, size);
}
