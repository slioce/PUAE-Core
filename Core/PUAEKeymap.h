/* OpenEmu delivers keys as USB HID usages (keyboard page 0x07); PUAE expects RETROK_* codes. */

#ifndef PUAE_KEYMAP_H
#define PUAE_KEYMAP_H

#include "libretro.h"

/* The RETROK_* code for a HID usage, or RETROK_UNKNOWN. */
unsigned puae_keymap_hid_to_retrok(unsigned hid_usage);

#endif
