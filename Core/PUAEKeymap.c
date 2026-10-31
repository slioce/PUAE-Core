#include "PUAEKeymap.h"

/*
 * HID keyboard page 0x07 -> RETROK_*. PUAE's own RETROK -> Amiga table is in libretro-mapper.h:
 * Insert/Help -> AK_HELP, LSUPER/RSUPER (the Mac Cmd keys) -> AK_LAMI/AK_RAMI,
 * HASH -> AK_NUMBERSIGN, LESS (ISO key next to left Shift) -> AK_LTGT.
 */
static const unsigned short hid_to_retrok[0xE8] = {
    [0x04] = RETROK_a, [0x05] = RETROK_b, [0x06] = RETROK_c, [0x07] = RETROK_d,
    [0x08] = RETROK_e, [0x09] = RETROK_f, [0x0A] = RETROK_g, [0x0B] = RETROK_h,
    [0x0C] = RETROK_i, [0x0D] = RETROK_j, [0x0E] = RETROK_k, [0x0F] = RETROK_l,
    [0x10] = RETROK_m, [0x11] = RETROK_n, [0x12] = RETROK_o, [0x13] = RETROK_p,
    [0x14] = RETROK_q, [0x15] = RETROK_r, [0x16] = RETROK_s, [0x17] = RETROK_t,
    [0x18] = RETROK_u, [0x19] = RETROK_v, [0x1A] = RETROK_w, [0x1B] = RETROK_x,
    [0x1C] = RETROK_y, [0x1D] = RETROK_z,

    [0x1E] = RETROK_1, [0x1F] = RETROK_2, [0x20] = RETROK_3, [0x21] = RETROK_4,
    [0x22] = RETROK_5, [0x23] = RETROK_6, [0x24] = RETROK_7, [0x25] = RETROK_8,
    [0x26] = RETROK_9, [0x27] = RETROK_0,

    [0x28] = RETROK_RETURN, [0x29] = RETROK_ESCAPE, [0x2A] = RETROK_BACKSPACE,
    [0x2B] = RETROK_TAB, [0x2C] = RETROK_SPACE,
    [0x2D] = RETROK_MINUS, [0x2E] = RETROK_EQUALS, [0x2F] = RETROK_LEFTBRACKET,
    [0x30] = RETROK_RIGHTBRACKET, [0x31] = RETROK_BACKSLASH, [0x32] = RETROK_HASH,
    [0x33] = RETROK_SEMICOLON, [0x34] = RETROK_QUOTE, [0x35] = RETROK_BACKQUOTE,
    [0x36] = RETROK_COMMA, [0x37] = RETROK_PERIOD, [0x38] = RETROK_SLASH,
    [0x39] = RETROK_CAPSLOCK,

    [0x3A] = RETROK_F1, [0x3B] = RETROK_F2, [0x3C] = RETROK_F3, [0x3D] = RETROK_F4,
    [0x3E] = RETROK_F5, [0x3F] = RETROK_F6, [0x40] = RETROK_F7, [0x41] = RETROK_F8,
    [0x42] = RETROK_F9, [0x43] = RETROK_F10, [0x44] = RETROK_F11, [0x45] = RETROK_F12,

    [0x46] = RETROK_PRINT, [0x47] = RETROK_SCROLLOCK, [0x48] = RETROK_PAUSE,
    [0x49] = RETROK_INSERT, [0x4A] = RETROK_HOME, [0x4B] = RETROK_PAGEUP,
    [0x4C] = RETROK_DELETE, [0x4D] = RETROK_END, [0x4E] = RETROK_PAGEDOWN,
    [0x4F] = RETROK_RIGHT, [0x50] = RETROK_LEFT, [0x51] = RETROK_DOWN, [0x52] = RETROK_UP,

    [0x53] = RETROK_NUMLOCK, [0x54] = RETROK_KP_DIVIDE, [0x55] = RETROK_KP_MULTIPLY,
    [0x56] = RETROK_KP_MINUS, [0x57] = RETROK_KP_PLUS, [0x58] = RETROK_KP_ENTER,
    [0x59] = RETROK_KP1, [0x5A] = RETROK_KP2, [0x5B] = RETROK_KP3, [0x5C] = RETROK_KP4,
    [0x5D] = RETROK_KP5, [0x5E] = RETROK_KP6, [0x5F] = RETROK_KP7, [0x60] = RETROK_KP8,
    [0x61] = RETROK_KP9, [0x62] = RETROK_KP0, [0x63] = RETROK_KP_PERIOD,
    [0x64] = RETROK_LESS, [0x67] = RETROK_KP_EQUALS, [0x75] = RETROK_HELP,

    [0xE0] = RETROK_LCTRL, [0xE1] = RETROK_LSHIFT, [0xE2] = RETROK_LALT, [0xE3] = RETROK_LSUPER,
    [0xE4] = RETROK_RCTRL, [0xE5] = RETROK_RSHIFT, [0xE6] = RETROK_RALT, [0xE7] = RETROK_RSUPER,
};

unsigned puae_keymap_hid_to_retrok(unsigned hid_usage)
{
    if (hid_usage >= sizeof(hid_to_retrok) / sizeof(hid_to_retrok[0]))
        return RETROK_UNKNOWN;
    return hid_to_retrok[hid_usage];
}
