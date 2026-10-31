/*
 * PUAE's system directory. PUAE writes WHDLoad.prefs there and mounts it as RASystem:, so it gets a
 * folder of its own instead of OpenEmu's shared BIOS folder, with symlinks to the Kickstarts OpenEmu
 * imported (already under the names PUAE looks for).
 */

#ifndef PUAE_SYSTEM_DIR_H
#define PUAE_SYSTEM_DIR_H

/* The Kickstart names declared in the core's Info.plist, NULL-terminated. */
extern const char *const puae_kickstart_names[];

/*
 * Creates system_dir if needed, symlinks every known Kickstart present in bios_dir and removes
 * links whose target is gone. Regular files are left alone. Returns the number of links, -1 on error.
 */
int puae_system_dir_link_kickstarts(const char *bios_dir, const char *system_dir);

#endif
