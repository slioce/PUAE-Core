#include "PUAEFloppySpeed.h"

#include <stddef.h>
#include <string.h>

/* Turbo drops disk rotation emulation: loads take a fraction of the time, though a few timing-sensitive
 * loaders may need Normal. */
const puae_floppy_speed puae_floppy_speeds[] = {
    { "Turbo", "0" },
    { "Normal", "100" },
    { "2x", "200" },
    { "4x", "400" },
    { "8x", "800" },
    { NULL, NULL },
};

const char *puae_floppy_speed_value(const char *name)
{
    for (const puae_floppy_speed *s = puae_floppy_speeds; name && s->name; s++)
        if (strcmp(s->name, name) == 0)
            return s->value;
    return NULL;
}

const char *puae_floppy_speed_or_default(const char *value)
{
    for (const puae_floppy_speed *s = puae_floppy_speeds; value && s->name; s++)
        if (strcmp(s->value, value) == 0)
            return s->value;
    return puae_floppy_speeds[0].value;
}
