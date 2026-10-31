#include "test.h"
#include "PUAEOptions.h"

static const struct retro_variable vars[] = {
    { "puae_model", "Model; auto|A500|A1200" },
    { "puae_gfx_colors", "Colors; 16bit|24bit" },
    { "puae_statusbar", "Status Bar; Shows LEDs; bottom|top|disabled" },
    { NULL, NULL },
};

static void test_defaults_are_first_declared_value(void)
{
    puae_options *o = puae_options_create();
    puae_options_set_variables(o, vars);
    CHECK_STR(puae_options_get(o, "puae_model"), "auto");
    CHECK_STR(puae_options_get(o, "puae_gfx_colors"), "16bit");
    CHECK(puae_options_get(o, "nope") == NULL);
    puae_options_destroy(o);
}

static void test_override_wins_over_default(void)
{
    puae_options *o = puae_options_create();
    puae_options_set_variables(o, vars);
    puae_options_set_override(o, "puae_gfx_colors", "24bit");
    CHECK_STR(puae_options_get(o, "puae_gfx_colors"), "24bit");
    puae_options_destroy(o);
}

static void test_override_before_variables_still_wins(void)
{
    puae_options *o = puae_options_create();
    puae_options_set_override(o, "puae_model", "A1200");
    puae_options_set_variables(o, vars);
    CHECK_STR(puae_options_get(o, "puae_model"), "A1200");
    puae_options_destroy(o);
}

static void test_is_valid_checks_declared_values(void)
{
    puae_options *o = puae_options_create();
    puae_options_set_variables(o, vars);
    CHECK(puae_options_is_valid(o, "puae_model", "A1200"));
    CHECK(!puae_options_is_valid(o, "puae_model", "A9000"));
    CHECK(!puae_options_is_valid(o, "nope", "auto"));
    puae_options_destroy(o);
}

static void test_description_with_semicolon(void)
{
    puae_options *o = puae_options_create();
    puae_options_set_variables(o, vars);
    CHECK_STR(puae_options_get(o, "puae_statusbar"), "bottom");
    CHECK(puae_options_is_valid(o, "puae_statusbar", "disabled"));
    puae_options_destroy(o);
}

int main(void)
{
    test_defaults_are_first_declared_value();
    test_override_wins_over_default();
    test_override_before_variables_still_wins();
    test_is_valid_checks_declared_values();
    test_description_with_semicolon();
    return test_report("test_options");
}
