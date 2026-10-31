/*
 * Multi-disk games. OpenEmu can't import an .m3u of ADFs, so every disk of a game is its own library
 * entry, all in the same folder. Given one of them, find the whole set by its disk tag ("_Disk2",
 * "(Disk 2 of 4)", "Disk 2") so the core can hand PUAE a generated playlist starting at disk 1.
 */

#ifndef PUAE_DISK_LIST_H
#define PUAE_DISK_LIST_H

#include <stddef.h>

typedef struct {
    char **paths;
    size_t count;
} puae_disk_list;

/* The set path belongs to, sorted by disk number; just {path} if its name has no disk tag. 0 on success. */
int puae_disk_list_find(const char *path, puae_disk_list *out);
void puae_disk_list_free(puae_disk_list *list);

/* File name minus extension minus disk tag, trimmed: "Turrican (AGA) (Disk 1 of 2).adf" -> "Turrican (AGA)". malloc'd. */
char *puae_disk_list_game_name(const char *path);
/* "<dir>/<name without extension>.m3u" if that file exists, else NULL. malloc'd. */
char *puae_disk_list_sidecar_m3u(const char *path);
/* One absolute path per line, each followed by "\n". 0 on success. */
int puae_disk_list_write_m3u(const puae_disk_list *list, const char *m3u_path);

#endif
