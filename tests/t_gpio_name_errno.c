/*
 * t_gpio_name_errno.c - errno contract of the `char *` GPIO shim.
 *
 * CT cannot read `errno` (it is a libc macro that expands to a function call),
 * so the EINVAL assertion lives on the C side: include the shim directly and
 * link stub pin accessors. The CT test (t_gpio_name.ct) covers the mapping and
 * the -1 returns; this one covers the errno value.
 */
#include <errno.h>
#include <stdio.h>

#include "../GpioName.shim.h"

int hal_posix_gpio_read(int pin)
{
    return pin == 17 ? 1 : 0;
}

int hal_posix_gpio_write(int pin, int value)
{
    (void)pin;
    (void)value;
    return 0;
}

static int check(const char *name, int want_ret, int *ok)
{
    int r;

    errno = 0;
    r = hal_posix_gpio_name_read((char *)name);
    if (r != want_ret || errno != EINVAL) {
        printf("FAIL name=\"%s\" ret=%d errno=%d want ret=%d errno=%d\n",
               name, r, errno, want_ret, EINVAL);
        *ok = 0;
        return 1;
    }
    return 0;
}

int main(void)
{
    int ok = 1;

    check("", -1, &ok);
    check("gpio", -1, &ok);
    check("gpioX", -1, &ok);
    check("GPIO17", -1, &ok);
    check("gpio32", -1, &ok);
    check("gpio-1", -1, &ok);

    errno = 0;
    if (hal_posix_gpio_name_read("gpio17") != 1 || errno != 0) {
        printf("FAIL gpio17 ret/errno mismatch (errno=%d)\n", errno);
        ok = 0;
    }

    if (!ok) return 1;
    printf("errno-cases=7 ok\n");
    return 0;
}
