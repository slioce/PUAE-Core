#include "PUAESystemDir.h"

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

const char *const puae_kickstart_names[] = {
    "kick34005.A500",   /* Kickstart 1.3, A500 */
    "kick40068.A1200",  /* Kickstart 3.1, A1200 */
    "kick40063.A600",   /* Kickstart 3.1, A600 */
    "kick37175.A500",   /* Kickstart 2.04, A500+ */
    NULL,
};

static int make_dirs(const char *path)
{
    char buf[PATH_MAX];
    if (snprintf(buf, sizeof(buf), "%s", path) >= (int)sizeof(buf))
        return -1;
    for (char *p = buf + 1; *p; p++) {
        if (*p != '/')
            continue;
        *p = '\0';
        if (mkdir(buf, 0755) != 0 && errno != EEXIST)
            return -1;
        *p = '/';
    }
    return mkdir(buf, 0755) == 0 || errno == EEXIST ? 0 : -1;
}

int puae_system_dir_link_kickstarts(const char *bios_dir, const char *system_dir)
{
    if (make_dirs(system_dir) != 0)
        return -1;

    /* Symlink targets resolve relative to the link's own directory, so anchor a relative bios_dir. */
    char bios[PATH_MAX], cwd[PATH_MAX];
    if (bios_dir[0] != '/' && getcwd(cwd, sizeof(cwd)))
        snprintf(bios, sizeof(bios), "%s/%s", cwd, bios_dir);
    else
        snprintf(bios, sizeof(bios), "%s", bios_dir);

    int linked = 0;
    for (const char *const *name = puae_kickstart_names; *name; name++) {
        char src[PATH_MAX], dst[PATH_MAX];
        snprintf(src, sizeof(src), "%s/%s", bios, *name);
        snprintf(dst, sizeof(dst), "%s/%s", system_dir, *name);

        struct stat st;
        if (lstat(dst, &st) == 0) {
            if (!S_ISLNK(st.st_mode))
                continue;  /* a real file someone put there: theirs */
            char target[PATH_MAX] = { 0 };
            ssize_t len = readlink(dst, target, sizeof(target) - 1);
            if (len > 0 && strcmp(target, src) == 0 && stat(dst, &st) == 0) {
                linked++;
                continue;
            }
            unlink(dst);
        }

        if (stat(src, &st) != 0)
            continue;
        if (symlink(src, dst) != 0)
            return -1;
        linked++;
    }
    return linked;
}
