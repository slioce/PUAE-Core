/* Minimal test helpers: each test file calls CHECK/CHECK_STR and returns test_report() from main. */

#ifndef PUAE_TEST_H
#define PUAE_TEST_H

#include <stdio.h>
#include <string.h>

static int test_failures;

#define CHECK(cond) do { \
    if (!(cond)) { \
        fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #cond); \
        test_failures++; \
    } \
} while (0)

#define CHECK_STR(actual, expected) do { \
    const char *a_ = (actual), *e_ = (expected); \
    if (!a_ || !e_ || strcmp(a_, e_) != 0) { \
        fprintf(stderr, "%s:%d: CHECK_STR failed: %s = \"%s\", expected \"%s\"\n", __FILE__, __LINE__, \
                #actual, a_ ? a_ : "(null)", e_ ? e_ : "(null)"); \
        test_failures++; \
    } \
} while (0)

static int test_report(const char *name)
{
    if (test_failures) {
        fprintf(stderr, "%s: %d check(s) failed\n", name, test_failures);
        return 1;
    }
    printf("%s: ok\n", name);
    return 0;
}

#endif
