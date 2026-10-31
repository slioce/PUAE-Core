/* Core option store: the values PUAE declares through RETRO_ENVIRONMENT_SET_VARIABLES, plus our overrides. */

#ifndef PUAE_OPTIONS_H
#define PUAE_OPTIONS_H

#include <stdbool.h>
#include "libretro.h"

typedef struct puae_options puae_options;

puae_options *puae_options_create(void);
void puae_options_destroy(puae_options *o);

/* vars is {NULL,NULL}-terminated, each value "Description; first|second|...". Records each key's declared values. */
void puae_options_set_variables(puae_options *o, const struct retro_variable *vars);
void puae_options_set_override(puae_options *o, const char *key, const char *value);

/* Override, else the default (first declared value), else NULL. */
const char *puae_options_get(const puae_options *o, const char *key);
/* Whether value is among the values declared for key. */
bool puae_options_is_valid(const puae_options *o, const char *key, const char *value);

#endif
