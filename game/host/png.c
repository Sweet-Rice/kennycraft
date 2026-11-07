// png.c — dependency-free PNG writer (stored deflate). Palette-maps a framebuffer to RGB.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "hal_host.h"

static uint32_t crc_table[256];
static void crc_init(void) {
    for (uint32_t n = 0; n < 256; n++) {
        uint32_t c = n;
        for (int k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
        crc_table[n] = c;
    }
}
static uint32_t crc(const uint8_t *b, size_t n, uint32_t c) {
    c ^= 0xFFFFFFFFu;
    while (n--) c = crc_table[(c ^ *b++) & 255] ^ (c >> 8);
    return c ^ 0xFFFFFFFFu;
}
static void be32(uint8_t *p, uint32_t v) { p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v; }
static void chunk(FILE *f, const char *type, const uint8_t *data, uint32_t len) {
    uint8_t hdr[8];
    be32(hdr, len); memcpy(hdr + 4, type, 4);
    fwrite(hdr, 1, 8, f);
    if (len) fwrite(data, 1, len, f);
    uint32_t c = crc((const uint8_t *)type, 4, 0);
    c = crc(data, len, c);
    uint8_t t[4]; be32(t, c); fwrite(t, 1, 4, f);
}

int png_write_fb(const char *path, const uint8_t *fb, const uint16_t *pal, int w, int h, int scale) {
    crc_init();
    int W = w * scale, H = h * scale;
    size_t raw_len = (size_t)H * (1 + (size_t)W * 3);
    uint8_t *raw = malloc(raw_len);
    for (int y = 0; y < H; y++) {
        uint8_t *row = raw + (size_t)y * (1 + (size_t)W * 3);
        row[0] = 0;
        for (int x = 0; x < W; x++) {
            uint16_t c = pal[fb[(y / scale) * 320 + (x / scale)]];
            row[1 + x * 3 + 0] = (uint8_t)(((c >> 8) & 15) * 17);
            row[1 + x * 3 + 1] = (uint8_t)(((c >> 4) & 15) * 17);
            row[1 + x * 3 + 2] = (uint8_t)((c & 15) * 17);
        }
    }
    size_t nblocks = (raw_len + 65534) / 65535;
    size_t z_len = 2 + raw_len + nblocks * 5 + 4;
    uint8_t *z = malloc(z_len), *p = z;
    *p++ = 0x78; *p++ = 0x01;
    uint32_t a = 1, b = 0;
    for (size_t off = 0; off < raw_len; off += 65535) {
        size_t n = raw_len - off < 65535 ? raw_len - off : 65535;
        *p++ = off + n == raw_len;
        *p++ = n & 255; *p++ = n >> 8; *p++ = ~n & 255; *p++ = (~n >> 8) & 255;
        memcpy(p, raw + off, n); p += n;
    }
    for (size_t i = 0; i < raw_len; i++) { a = (a + raw[i]) % 65521; b = (b + a) % 65521; }
    be32(p, (b << 16) | a); p += 4;

    FILE *f = fopen(path, "wb");
    if (!f) { free(raw); free(z); return -1; }
    static const uint8_t sig[8] = { 137, 80, 78, 71, 13, 10, 26, 10 };
    fwrite(sig, 1, 8, f);
    uint8_t ihdr[13];
    be32(ihdr, (uint32_t)W); be32(ihdr + 4, (uint32_t)H);
    ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
    chunk(f, "IHDR", ihdr, 13);
    chunk(f, "IDAT", z, (uint32_t)(p - z));
    chunk(f, "IEND", NULL, 0);
    fclose(f);
    free(raw); free(z);
    return 0;
}
