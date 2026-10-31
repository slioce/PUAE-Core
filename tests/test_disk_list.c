#include "test.h"
#include "PUAEDiskList.h"

#include <stdlib.h>
#include <unistd.h>

static char *make_dir(void)
{
    const char *tmp = getenv("TMPDIR");
    char *dir = NULL;
    asprintf(&dir, "%s/puae-disks-XXXXXX", tmp && *tmp ? tmp : "/tmp");
    return mkdtemp(dir);
}

static char *path_in(const char *dir, const char *name)
{
    char *path = NULL;
    asprintf(&path, "%s/%s", dir, name);
    return path;
}

static void touch(const char *dir, const char *name)
{
    char *path = path_in(dir, name);
    FILE *f = fopen(path, "w");
    if (f)
        fclose(f);
    free(path);
}

static void check_path(const char *actual, const char *dir, const char *name)
{
    char *expected = path_in(dir, name);
    CHECK_STR(actual, expected);
    free(expected);
}

static void test_opened_from_disk_2_lists_disk_1_first(void)
{
    char *dir = make_dir();
    touch(dir, "Lemmings_Disk1.adf");
    touch(dir, "Lemmings_Disk2.adf");
    touch(dir, "Lemmings 2.adf");
    touch(dir, "Other_Disk1.adf");
    char *path = path_in(dir, "Lemmings_Disk2.adf");

    puae_disk_list list;
    CHECK(puae_disk_list_find(path, &list) == 0);
    CHECK(list.count == 2);
    if (list.count == 2) {
        check_path(list.paths[0], dir, "Lemmings_Disk1.adf");
        check_path(list.paths[1], dir, "Lemmings_Disk2.adf");
    }
    puae_disk_list_free(&list);
    free(path);
    free(dir);
}

static void test_disk_n_of_m_ignores_other_extensions(void)
{
    char *dir = make_dir();
    touch(dir, "Syndicate (Europe) (Disk 3 of 4).adf");
    touch(dir, "Syndicate (Europe) (Disk 1 of 4).adf");
    touch(dir, "Syndicate (Europe) (Disk 4 of 4).adf");
    touch(dir, "Syndicate (Europe) (Disk 2 of 4).adf");
    touch(dir, "Syndicate (Europe) (Disk 1 of 4).ipf");
    char *path = path_in(dir, "Syndicate (Europe) (Disk 3 of 4).adf");

    puae_disk_list list;
    CHECK(puae_disk_list_find(path, &list) == 0);
    CHECK(list.count == 4);
    if (list.count == 4) {
        check_path(list.paths[0], dir, "Syndicate (Europe) (Disk 1 of 4).adf");
        check_path(list.paths[1], dir, "Syndicate (Europe) (Disk 2 of 4).adf");
        check_path(list.paths[2], dir, "Syndicate (Europe) (Disk 3 of 4).adf");
        check_path(list.paths[3], dir, "Syndicate (Europe) (Disk 4 of 4).adf");
    }
    puae_disk_list_free(&list);
    free(path);
    free(dir);
}

static void test_disks_sort_numerically(void)
{
    char *dir = make_dir();
    touch(dir, "Game_Disk10.adf");
    touch(dir, "Game_Disk2.adf");
    touch(dir, "Game_Disk1.adf");
    char *path = path_in(dir, "Game_Disk1.adf");

    puae_disk_list list;
    CHECK(puae_disk_list_find(path, &list) == 0);
    CHECK(list.count == 3);
    if (list.count == 3) {
        check_path(list.paths[0], dir, "Game_Disk1.adf");
        check_path(list.paths[1], dir, "Game_Disk2.adf");
        check_path(list.paths[2], dir, "Game_Disk10.adf");
    }
    puae_disk_list_free(&list);
    free(path);
    free(dir);
}

static void test_names_with_punctuation_survive(void)
{
    char *dir = make_dir();
    touch(dir, "It's Magic (Europe) (Disk 1 of 2).adf");
    touch(dir, "It's Magic (Europe) (Disk 2 of 2).adf");
    char *path = path_in(dir, "It's Magic (Europe) (Disk 1 of 2).adf");

    puae_disk_list list;
    CHECK(puae_disk_list_find(path, &list) == 0);
    CHECK(list.count == 2);
    if (list.count == 2) {
        check_path(list.paths[0], dir, "It's Magic (Europe) (Disk 1 of 2).adf");
        check_path(list.paths[1], dir, "It's Magic (Europe) (Disk 2 of 2).adf");
    }
    puae_disk_list_free(&list);
    free(path);
    free(dir);
}

static void test_untagged_names_are_single_disks(void)
{
    char *dir = make_dir();
    touch(dir, "New Zealand Story, The.adf");
    touch(dir, "SensibleSoccerSaveDisk.adf");
    const char *names[] = { "New Zealand Story, The.adf", "SensibleSoccerSaveDisk.adf" };
    for (int i = 0; i < 2; i++) {
        char *path = path_in(dir, names[i]);
        puae_disk_list list;
        CHECK(puae_disk_list_find(path, &list) == 0);
        CHECK(list.count == 1);
        if (list.count == 1)
            CHECK_STR(list.paths[0], path);
        puae_disk_list_free(&list);
        free(path);
    }
    free(dir);
}

/* A zip is unpacked alone into a temp folder, so its disk 1 has no siblings. */
static void test_lone_tagged_disk_is_single(void)
{
    char *dir = make_dir();
    touch(dir, "Lemmings_Disk1.adf");
    char *path = path_in(dir, "Lemmings_Disk1.adf");

    puae_disk_list list;
    CHECK(puae_disk_list_find(path, &list) == 0);
    CHECK(list.count == 1);
    if (list.count == 1)
        CHECK_STR(list.paths[0], path);
    puae_disk_list_free(&list);
    free(path);
    free(dir);
}

static void test_game_name(void)
{
    const struct { const char *path, *name; } cases[] = {
        { "/x/Lemmings_Disk2.adf", "Lemmings" },
        { "/x/Syndicate (Europe) (Disk 1 of 4).adf", "Syndicate (Europe)" },
        { "/x/Turrican (AGA) (Disk 1 of 2).adf", "Turrican (AGA)" },
        { "/x/New Zealand Story, The.adf", "New Zealand Story, The" },
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        char *name = puae_disk_list_game_name(cases[i].path);
        CHECK_STR(name, cases[i].name);
        free(name);
    }
}

static void test_sidecar_m3u(void)
{
    char *dir = make_dir();
    touch(dir, "Sensible Soccer.adf");
    char *path = path_in(dir, "Sensible Soccer.adf");
    CHECK(puae_disk_list_sidecar_m3u(path) == NULL);

    touch(dir, "Sensible Soccer.m3u");
    char *m3u = puae_disk_list_sidecar_m3u(path);
    check_path(m3u, dir, "Sensible Soccer.m3u");
    free(m3u);
    free(path);
    free(dir);
}

static void test_write_m3u(void)
{
    char *dir = make_dir();
    char *paths[] = { "/games/A (Disk 1 of 2).adf", "/games/A (Disk 2 of 2).adf" };
    puae_disk_list list = { paths, 2 };
    char *m3u = path_in(dir, "A.m3u");
    CHECK(puae_disk_list_write_m3u(&list, m3u) == 0);

    char buf[256] = { 0 };
    FILE *f = fopen(m3u, "r");
    if (f) {
        fread(buf, 1, sizeof(buf) - 1, f);
        fclose(f);
    }
    CHECK_STR(buf, "/games/A (Disk 1 of 2).adf\n/games/A (Disk 2 of 2).adf\n");
    free(m3u);
    free(dir);
}

int main(void)
{
    test_opened_from_disk_2_lists_disk_1_first();
    test_disk_n_of_m_ignores_other_extensions();
    test_disks_sort_numerically();
    test_names_with_punctuation_survive();
    test_untagged_names_are_single_disks();
    test_lone_tagged_disk_is_single();
    test_game_name();
    test_sidecar_m3u();
    test_write_m3u();
    return test_report("test_disk_list");
}
