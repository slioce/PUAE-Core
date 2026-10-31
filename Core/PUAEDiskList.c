#include "PUAEDiskList.h"

#include <ctype.h>
#include <dirent.h>
#include <regex.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>

/* "_Disk2", " Disk 2", "-disk2", " (Disk 2 of 4)": the number is group 1. */
#define DISK_TAG_PATTERN "[ _-]?\\(?disk[ _-]?([0-9]{1,2})([ _-]?of[ _-]?[0-9]{1,2})?\\)?"

typedef struct {
    char *path;
    int number;
} disk_entry;

static const char *file_name(const char *path)
{
    const char *slash = strrchr(path, '/');
    return slash ? slash + 1 : path;
}

/* Extension including the dot, or "" if the name has none. */
static const char *extension(const char *name)
{
    const char *dot = strrchr(name, '.');
    return dot && dot != name ? dot : name + strlen(name);
}

/*
 * Splits a file name into its set key (the name without extension and disk tag) and disk number.
 * Returns the malloc'd key; *number is 0 when the name has no disk tag.
 */
static char *parse_name(const char *name, int *number)
{
    size_t len = (size_t)(extension(name) - name);
    char *base = strndup(name, len);
    *number = 0;
    if (!base)
        return NULL;

    static regex_t tag;
    static int compiled;
    if (!compiled) {
        if (regcomp(&tag, DISK_TAG_PATTERN, REG_EXTENDED | REG_ICASE) != 0)
            return base;
        compiled = 1;
    }

    regmatch_t m[2];
    if (regexec(&tag, base, 2, m, 0) != 0)
        return base;

    *number = atoi(base + m[1].rm_so);
    memmove(base + m[0].rm_so, base + m[0].rm_eo, len - (size_t)m[0].rm_eo + 1);
    return base;
}

static char *trim(char *s)
{
    char *start = s;
    while (isspace((unsigned char)*start))
        start++;
    size_t len = strlen(start);
    while (len && (isspace((unsigned char)start[len - 1]) || start[len - 1] == '_' || start[len - 1] == '-'))
        len--;
    memmove(s, start, len);
    s[len] = '\0';
    return s;
}

static int compare_entries(const void *a, const void *b)
{
    const disk_entry *x = a, *y = b;
    if (x->number != y->number)
        return x->number < y->number ? -1 : 1;
    return strcmp(x->path, y->path);
}

static int single_disk(const char *path, puae_disk_list *out)
{
    out->paths = malloc(sizeof(char *));
    if (!out->paths)
        return -1;
    out->paths[0] = strdup(path);
    out->count = 1;
    return 0;
}

int puae_disk_list_find(const char *path, puae_disk_list *out)
{
    *out = (puae_disk_list){ 0 };
    const char *name = file_name(path);
    int number;
    char *key = parse_name(name, &number);
    if (!key)
        return -1;
    if (number == 0) {
        free(key);
        return single_disk(path, out);
    }

    char *dir = name == path ? strdup(".") : strndup(path, (size_t)(name - path - 1));
    DIR *d = dir ? opendir(dir) : NULL;
    if (!d) {
        free(dir);
        free(key);
        return single_disk(path, out);
    }

    disk_entry *entries = NULL;
    size_t count = 0, capacity = 0;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.' || strcasecmp(extension(e->d_name), extension(name)) != 0)
            continue;
        int n;
        char *other = parse_name(e->d_name, &n);
        if (other && n > 0 && strcasecmp(other, key) == 0) {
            if (count == capacity) {
                capacity = capacity ? capacity * 2 : 8;
                disk_entry *grown = realloc(entries, capacity * sizeof(*entries));
                if (!grown) {
                    free(other);
                    break;
                }
                entries = grown;
            }
            asprintf(&entries[count].path, "%s/%s", dir, e->d_name);
            entries[count++].number = n;
        }
        free(other);
    }
    closedir(d);
    free(dir);
    free(key);

    if (count == 0) {
        free(entries);
        return single_disk(path, out);
    }
    qsort(entries, count, sizeof(*entries), compare_entries);
    out->paths = malloc(count * sizeof(char *));
    for (size_t i = 0; i < count; i++) {
        if (out->paths)
            out->paths[i] = entries[i].path;
        else
            free(entries[i].path);
    }
    out->count = out->paths ? count : 0;
    free(entries);
    return out->paths ? 0 : -1;
}

void puae_disk_list_free(puae_disk_list *list)
{
    for (size_t i = 0; i < list->count; i++)
        free(list->paths[i]);
    free(list->paths);
    *list = (puae_disk_list){ 0 };
}

char *puae_disk_list_game_name(const char *path)
{
    int number;
    char *key = parse_name(file_name(path), &number);
    return key ? trim(key) : NULL;
}

char *puae_disk_list_sidecar_m3u(const char *path)
{
    const char *ext = extension(file_name(path));
    char *m3u = NULL;
    if (asprintf(&m3u, "%.*s.m3u", (int)(ext - path), path) < 0)
        return NULL;
    if (access(m3u, R_OK) != 0) {
        free(m3u);
        return NULL;
    }
    return m3u;
}

int puae_disk_list_write_m3u(const puae_disk_list *list, const char *m3u_path)
{
    FILE *f = fopen(m3u_path, "w");
    if (!f)
        return -1;
    for (size_t i = 0; i < list->count; i++)
        fprintf(f, "%s\n", list->paths[i]);
    return fclose(f) == 0 ? 0 : -1;
}
