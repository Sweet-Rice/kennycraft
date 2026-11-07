// kc_libc.c — the two functions a freestanding compiler may call for struct copies and
// zeroing. Chip build only; the laptop uses its own libc. (If Bennett's crt0 ships these,
// drop this file.)
#ifndef KC_HOST
#include <stddef.h>
#include <stdint.h>

void *memcpy(void *dst, const void *src, size_t n) {
    uint8_t *d = dst;
    const uint8_t *s = src;
    if ((((uintptr_t)d | (uintptr_t)s | n) & 3) == 0) {
        uint32_t *dw = (uint32_t *)d;
        const uint32_t *sw = (const uint32_t *)s;
        for (size_t i = 0; i < n / 4; i++) dw[i] = sw[i];
        return dst;
    }
    for (size_t i = 0; i < n; i++) d[i] = s[i];
    return dst;
}

void *memset(void *dst, int c, size_t n) {
    uint8_t *d = dst;
    for (size_t i = 0; i < n; i++) d[i] = (uint8_t)c;
    return dst;
}
#endif
