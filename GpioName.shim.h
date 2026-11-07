/*
 * GpioName.shim.h - the same-basename shim for GpioName.m.ct.
 *
 * The pin table and its two operations stay in PosixHal.h.ct; this shim only
 * parses `gpio<N>` and forwards to them, so there is exactly one copy of the
 * GPIO logic. The extern declarations let the generated consumer call them
 * without including PosixHal.h; PosixHal.h.ct imports this unit, so the
 * definitions are part of the same build closure.
 *
 * Invalid names (NULL, empty, wrong prefix, non-digits, negative, or a pin
 * outside 0..31) return -1 with errno = EINVAL.
 */
#ifndef HAL_POSIX_GPIO_NAME_SHIM_H
#define HAL_POSIX_GPIO_NAME_SHIM_H

#include <errno.h>

extern int hal_posix_gpio_read(int pin);
extern int hal_posix_gpio_write(int pin, int value);

static inline int hal_posix_gpio_name_pin(const char *dev)
{
    int pin = 0;
    int i;

    if (dev == 0) return -1;
    if (dev[0] != 'g') return -1;
    if (dev[1] != 'p') return -1;
    if (dev[2] != 'i') return -1;
    if (dev[3] != 'o') return -1;
    if (dev[4] == '\0') return -1;
    for (i = 4; dev[i] != '\0'; i = i + 1) {
        if (dev[i] < '0' || dev[i] > '9') return -1;
        pin = pin * 10 + (dev[i] - '0');
        if (pin >= 32) return -1;
    }
    return pin;
}

static inline int hal_posix_gpio_name_read(char *dev)
{
    int pin = hal_posix_gpio_name_pin(dev);

    if (pin < 0) {
        errno = EINVAL;
        return -1;
    }
    return hal_posix_gpio_read(pin);
}

static inline int hal_posix_gpio_name_write(char *dev, int value)
{
    int pin = hal_posix_gpio_name_pin(dev);

    if (pin < 0) {
        errno = EINVAL;
        return -1;
    }
    return hal_posix_gpio_write(pin, value);
}

#endif /* HAL_POSIX_GPIO_NAME_SHIM_H */
