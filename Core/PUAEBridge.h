/*
 * A minimal libretro frontend for PUAE (libretro-uae, linked statically). PUAE keeps all of its state in
 * globals, so there is exactly one bridge per process, which matches OpenEmu's one game per helper.
 *
 * Input: PUAE reads RetroPad B as fire and A as 2nd fire (puae_retropad_options default "disabled",
 * libretro-core.c). RetroPad port 0 is player 1 on the Amiga joystick port; PUAE swaps ports, so
 * RetroPad port 1 is the Amiga mouse port. The mouse is read on port 0 (libretro-mapper.c).
 */

#ifndef PUAE_BRIDGE_H
#define PUAE_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "libretro.h"

typedef struct {
    const char *system_dir, *save_dir;
    void *ctx;
    void (*audio)(void *ctx, const int16_t *frames, size_t count);  /* interleaved stereo, count = frames */
    void (*log)(void *ctx, int level, const char *message);          /* level = enum retro_log_level */
    const char *const *options;  /* "key", "value", ... NULL-terminated; on top of the bridge's defaults. PUAE
                                  * reads options once in retro_init, so this is how choices apply from the start. */
} puae_bridge_config;

typedef struct {
    double fps, sample_rate;
    unsigned buffer_width, buffer_height;  /* fixed once allocated */
    unsigned width, height;                /* last frame, clamped to the buffer */
    float aspect;                          /* display aspect; width/height if PUAE reports <= 0 */
    const uint32_t *frame;                 /* XRGB8888, stride = buffer_width pixels */
} puae_bridge_video;

/* Resets all bridge state and stores the config (strings are copied). No retro_* calls. */
void puae_bridge_configure(const puae_bridge_config *config);
/* configure + retro_set_* callbacks + retro_init. 0 on success. */
int puae_bridge_init(const puae_bridge_config *config);
/* retro_load_game, av info, frame buffer, controller ports. Fails if PUAE reports a missing Kickstart. */
bool puae_bridge_load(const char *path);
void puae_bridge_run_frame(void);
void puae_bridge_reset(void);
/* retro_unload_game + retro_deinit. */
void puae_bridge_deinit(void);

const puae_bridge_video *puae_bridge_video_info(void);
/* Text of the last RETRO_LOG_ERROR PUAE logged, or NULL. */
const char *puae_bridge_last_error(void);

/* Input setters may be called from any thread; they take effect at PUAE's next input poll. */
void puae_bridge_set_joypad(unsigned port, unsigned retro_id, bool pressed);  /* port 0 = player 1 */
void puae_bridge_mouse_move(int dx, int dy);                                  /* accumulated until the next poll */
void puae_bridge_set_mouse_button(unsigned retro_id, bool pressed);          /* RETRO_DEVICE_ID_MOUSE_LEFT/RIGHT */
void puae_bridge_key(unsigned retrok, bool down);  /* keyboard callback + pressed table for RETRO_DEVICE_KEYBOARD */

/* Changes a core option while running (on the emulation thread); PUAE re-reads options at its next frame.
 * Fails if PUAE doesn't declare the value for the key. */
bool puae_bridge_set_option(const char *key, const char *value);

unsigned puae_bridge_disk_count(void);
unsigned puae_bridge_disk_index(void);
bool puae_bridge_set_disk(unsigned index);  /* 0-based: eject, select, insert */

size_t puae_bridge_state_size(void);
bool puae_bridge_save_state(void *buffer, size_t size);
bool puae_bridge_load_state(const void *buffer, size_t size);

/* The libretro callbacks the bridge registers, exposed for tests. */
bool puae_bridge_environment(unsigned cmd, void *data);
void puae_bridge_video_refresh(const void *data, unsigned width, unsigned height, size_t pitch);
void puae_bridge_input_poll(void);
int16_t puae_bridge_input_state(unsigned port, unsigned device, unsigned index, unsigned id);

#endif
