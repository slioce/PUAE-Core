#include "test.h"
#include "PUAESystemDir.h"

#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

static char *make_dir(void)
{
    const char *tmp = getenv("TMPDIR");
    char *dir = NULL;
    asprintf(&dir, "%s/puae-system-XXXXXX", tmp && *tmp ? tmp : "/tmp");
    return mkdtemp(dir);
}

static char *path_in(const char *dir, const char *name)
{
    char *path = NULL;
    asprintf(&path, "%s/%s", dir, name);
    return path;
}

static void touch(const char *path)
{
    FILE *f = fopen(path, "w");
    if (f)
        fclose(f);
}

static void test_links_known_kickstarts_and_drops_stale_links(void)
{
    char *root = make_dir();
    char *bios = path_in(root, "BIOS");
    char *system = path_in(root, "PUAE/system");
    mkdir(bios, 0755);
    char *kick = path_in(bios, "kick34005.A500");
    char *other = path_in(bios, "unrelated.bin");
    touch(kick);
    touch(other);

    char *puae = path_in(root, "PUAE");
    mkdir(puae, 0755);
    mkdir(system, 0755);
    char *stale = path_in(system, "kick40068.A1200");
    symlink("/nonexistent/kick40068.A1200", stale);

    CHECK(puae_system_dir_link_kickstarts(bios, system) == 1);

    char *link = path_in(system, "kick34005.A500");
    char target[PATH_MAX] = { 0 };
    CHECK(readlink(link, target, sizeof(target) - 1) > 0);
    CHECK_STR(target, kick);

    struct stat st;
    CHECK(lstat(stale, &st) != 0 && errno == ENOENT);
    char *unrelated = path_in(system, "unrelated.bin");
    CHECK(lstat(unrelated, &st) != 0);

    CHECK(puae_system_dir_link_kickstarts(bios, system) == 1);

    free(unrelated);
    free(link);
    free(stale);
    free(puae);
    free(other);
    free(kick);
    free(system);
    free(bios);
    free(root);
}

static void test_creates_missing_system_dir(void)
{
    char *root = make_dir();
    char *bios = path_in(root, "BIOS");
    char *system = path_in(root, "a/b/system");
    mkdir(bios, 0755);
    char *kick = path_in(bios, "kick40068.A1200");
    touch(kick);

    CHECK(puae_system_dir_link_kickstarts(bios, system) == 1);
    struct stat st;
    CHECK(stat(system, &st) == 0 && S_ISDIR(st.st_mode));

    free(kick);
    free(system);
    free(bios);
    free(root);
}

static void test_leaves_regular_files_alone(void)
{
    char *root = make_dir();
    char *bios = path_in(root, "BIOS");
    char *system = path_in(root, "system");
    mkdir(bios, 0755);
    mkdir(system, 0755);
    char *copy = path_in(system, "kick34005.A500");
    touch(copy);

    CHECK(puae_system_dir_link_kickstarts(bios, system) == 0);
    struct stat st;
    CHECK(lstat(copy, &st) == 0 && S_ISREG(st.st_mode));

    free(copy);
    free(system);
    free(bios);
    free(root);
}

/* A relative bios_dir must not produce links that resolve relative to system_dir. */
static void test_relative_bios_dir_links_resolve(void)
{
    char *root = make_dir();
    char cwd[PATH_MAX];
    getcwd(cwd, sizeof(cwd));
    chdir(root);
    mkdir("BIOS", 0755);
    touch("BIOS/kick34005.A500");

    CHECK(puae_system_dir_link_kickstarts("BIOS", "out/system") == 1);
    struct stat st;
    CHECK(stat("out/system/kick34005.A500", &st) == 0 && S_ISREG(st.st_mode));

    chdir(cwd);
    free(root);
}

int main(void)
{
    test_links_known_kickstarts_and_drops_stale_links();
    test_creates_missing_system_dir();
    test_leaves_regular_files_alone();
    test_relative_bios_dir_links_resolve();
    return test_report("test_system_dir");
}
