#include "test.h"
#include "PUAEFloppySpeed.h"

int main(void)
{
    CHECK_STR(puae_floppy_speeds[0].name, "Turbo");  /* the default comes first */
    CHECK_STR(puae_floppy_speed_value("Turbo"), "0");
    CHECK_STR(puae_floppy_speed_value("Normal"), "100");
    CHECK_STR(puae_floppy_speed_value("4x"), "400");
    CHECK(puae_floppy_speed_value("Warp") == NULL);
    CHECK(puae_floppy_speed_value(NULL) == NULL);

    /* A saved preference, if it is still a known speed; otherwise Turbo. */
    CHECK_STR(puae_floppy_speed_or_default("800"), "800");
    CHECK_STR(puae_floppy_speed_or_default("100"), "100");
    CHECK_STR(puae_floppy_speed_or_default("123"), "0");
    CHECK_STR(puae_floppy_speed_or_default(NULL), "0");
    return test_report("test_floppy_speed");
}
