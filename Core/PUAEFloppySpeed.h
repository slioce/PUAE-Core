/* The floppy speeds offered in OpenEmu's display-mode menu, as values of PUAE's puae_floppy_speed option. */

#ifndef PUAE_FLOPPY_SPEED_H
#define PUAE_FLOPPY_SPEED_H

typedef struct {
    const char *name;   /* menu item */
    const char *value;  /* puae_floppy_speed value */
} puae_floppy_speed;

/* Turbo first (the default), then Normal, 2x, 4x, 8x; {NULL, NULL}-terminated. */
extern const puae_floppy_speed puae_floppy_speeds[];

/* The option value for a menu item, or NULL. */
const char *puae_floppy_speed_value(const char *name);
/* value if it is one of the speeds, else the default (Turbo). */
const char *puae_floppy_speed_or_default(const char *value);

#endif
