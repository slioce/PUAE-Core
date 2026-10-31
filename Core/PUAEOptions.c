#include "PUAEOptions.h"

#include <stdlib.h>
#include <string.h>

typedef struct {
    char *key;
    char **values;      /* declared values, values[0] is the default */
    size_t value_count;
    char *override;
} puae_option;

struct puae_options {
    puae_option *items;
    size_t count, capacity;
};

static puae_option *find_option(const puae_options *o, const char *key)
{
    for (size_t i = 0; i < o->count; i++)
        if (strcmp(o->items[i].key, key) == 0)
            return &o->items[i];
    return NULL;
}

static puae_option *find_or_add_option(puae_options *o, const char *key)
{
    puae_option *opt = find_option(o, key);
    if (opt)
        return opt;
    if (o->count == o->capacity) {
        size_t capacity = o->capacity ? o->capacity * 2 : 64;
        puae_option *items = realloc(o->items, capacity * sizeof(*items));
        if (!items)
            return NULL;
        o->items = items;
        o->capacity = capacity;
    }
    opt = &o->items[o->count++];
    *opt = (puae_option){ .key = strdup(key) };
    return opt;
}

static void free_values(puae_option *opt)
{
    for (size_t i = 0; i < opt->value_count; i++)
        free(opt->values[i]);
    free(opt->values);
    opt->values = NULL;
    opt->value_count = 0;
}

/* "Description; a|b|c": the values follow the last "; ", since descriptions may contain one too. */
static void parse_values(puae_option *opt, const char *spec)
{
    const char *values = spec;
    for (const char *p = strstr(spec, "; "); p; p = strstr(p + 2, "; "))
        values = p + 2;

    size_t count = 1;
    for (const char *p = values; *p; p++)
        if (*p == '|')
            count++;

    opt->values = calloc(count, sizeof(char *));
    if (!opt->values)
        return;
    const char *start = values;
    for (size_t i = 0; i < count; i++) {
        const char *end = strchr(start, '|');
        size_t len = end ? (size_t)(end - start) : strlen(start);
        opt->values[i] = strndup(start, len);
        start = end ? end + 1 : start + len;
    }
    opt->value_count = count;
}

puae_options *puae_options_create(void)
{
    return calloc(1, sizeof(puae_options));
}

void puae_options_destroy(puae_options *o)
{
    if (!o)
        return;
    for (size_t i = 0; i < o->count; i++) {
        free_values(&o->items[i]);
        free(o->items[i].key);
        free(o->items[i].override);
    }
    free(o->items);
    free(o);
}

void puae_options_set_variables(puae_options *o, const struct retro_variable *vars)
{
    for (; vars && vars->key; vars++) {
        puae_option *opt = find_or_add_option(o, vars->key);
        if (!opt)
            continue;
        free_values(opt);
        if (vars->value)
            parse_values(opt, vars->value);
    }
}

void puae_options_set_override(puae_options *o, const char *key, const char *value)
{
    puae_option *opt = find_or_add_option(o, key);
    if (!opt)
        return;
    free(opt->override);
    opt->override = value ? strdup(value) : NULL;
}

const char *puae_options_get(const puae_options *o, const char *key)
{
    const puae_option *opt = find_option(o, key);
    if (!opt)
        return NULL;
    if (opt->override)
        return opt->override;
    return opt->value_count ? opt->values[0] : NULL;
}

bool puae_options_is_valid(const puae_options *o, const char *key, const char *value)
{
    const puae_option *opt = find_option(o, key);
    if (!opt || !value)
        return false;
    for (size_t i = 0; i < opt->value_count; i++)
        if (strcmp(opt->values[i], value) == 0)
            return true;
    return false;
}
