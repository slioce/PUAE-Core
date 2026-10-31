#include "test.h"
#include "PUAEKeymap.h"

static const struct { unsigned hid, retrok; } cases[] = {
    { 0x04, RETROK_a },
    { 0x1D, RETROK_z },
    { 0x1E, RETROK_1 },
    { 0x27, RETROK_0 },
    { 0x28, RETROK_RETURN },
    { 0x29, RETROK_ESCAPE },
    { 0x2A, RETROK_BACKSPACE },
    { 0x2B, RETROK_TAB },
    { 0x2C, RETROK_SPACE },
    { 0x3A, RETROK_F1 },
    { 0x43, RETROK_F10 },
    { 0x4C, RETROK_DELETE },
    { 0x4F, RETROK_RIGHT },
    { 0x50, RETROK_LEFT },
    { 0x51, RETROK_DOWN },
    { 0x52, RETROK_UP },
    { 0x59, RETROK_KP1 },
    { 0x58, RETROK_KP_ENTER },
    { 0xE0, RETROK_LCTRL },
    { 0xE1, RETROK_LSHIFT },
    { 0xE2, RETROK_LALT },
    { 0xE5, RETROK_RSHIFT },
    /* Cmd keys are the Amiga keys: PUAE maps LSUPER/RSUPER to AK_LAMI/AK_RAMI (libretro-mapper.h). */
    { 0xE3, RETROK_LSUPER },
    { 0xE7, RETROK_RSUPER },
    { 0x00, RETROK_UNKNOWN },
    { 0xFFFF, RETROK_UNKNOWN },
};

int main(void)
{
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        unsigned got = puae_keymap_hid_to_retrok(cases[i].hid);
        if (got != cases[i].retrok) {
            fprintf(stderr, "HID 0x%02X -> %u, expected %u\n", cases[i].hid, got, cases[i].retrok);
            test_failures++;
        }
    }
    return test_report("test_keymap");
}
