#define _POSIX_C_SOURCE 199309L
// hal_host.c — laptop emulation of the chip's memory map.
// Mirrors the hardware rules from the Interfaces section so chunk and render code is tested
// as-is: world window with WIN_ORIGIN ring addressing and SLOT_VALID (invalid reads = air),
// a DDR3 chunk engine, double framebuffer with FB_SWAP, UART RX FIFO, CYCLES counter.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "kc_hal.h"
#include "hal_host.h"
#include "kc_assets.h"

kc_camera  host_camera;
kc_rparams host_rparams;

static uint8_t  bram_world[WIN_X * WIN_Y * WIN_Z];
static uint32_t win_origin, slot_valid;
static uint8_t  fb[2][FB_STRIDE * 240];
static int      back = 1;
static uint32_t frame_count, fb_mode, leds;
static uint8_t *ddr[256 * 256];           // chunk store, allocated on first write
static uint32_t chunk_done;
static uint8_t  rx_fifo[256];
static uint32_t rx_head, rx_tail;
static uint64_t cycles;
static int      realtime;
static int      storage_ok = 1;
static uint64_t t0_ns;
host_stats      hstats;

static uint64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

void host_init(int realtime_clock) {
    realtime = realtime_clock;
    storage_ok = getenv("KC_NO_STORAGE") == NULL;
    t0_ns = now_ns();
}

// ---- world window ---------------------------------------------------------------------
static uint32_t phys(int32_t x, int32_t y, int32_t z, int *slot) {
    uint32_t px = ((uint32_t)x + (win_origin & 63)) & 63;
    uint32_t pz = ((uint32_t)z + ((win_origin >> 8) & 63)) & 63;
    if (slot) *slot = (int)((pz >> 4) * 4 + (px >> 4));
    return WIN_INDEX(px, (uint32_t)y & 31, pz);
}

uint8_t hal_win_get(int32_t x, int32_t y, int32_t z) {
    if ((uint32_t)x > 63 || (uint32_t)y > 31 || (uint32_t)z > 63) {
        fprintf(stderr, "hal: world read out of window (%d,%d,%d)\n", x, y, z);
        abort();
    }
    int s;
    uint32_t i = phys(x, y, z, &s);
    hstats.world_reads++;
    return (slot_valid >> s) & 1 ? (bram_world[i] & 15) : 0;
}

void hal_win_set(int32_t x, int32_t y, int32_t z, uint8_t t) {
    if ((uint32_t)x > 63 || (uint32_t)y > 31 || (uint32_t)z > 63) {
        fprintf(stderr, "hal: world write out of window (%d,%d,%d)\n", x, y, z);
        abort();
    }
    bram_world[phys(x, y, z, NULL)] = t & 15;
}

// ---- textures, framebuffer ---------------------------------------------------------------
uint8_t hal_tex_get(uint32_t idx) { return idx < TEX_BYTES ? kc_textures[idx] : 0; }

void hal_fb_put(uint32_t idx, uint8_t v) {
    if (idx >= FB_STRIDE * 240) { fprintf(stderr, "hal: fb write out of range %u\n", idx); abort(); }
    fb[back][idx] = v;
}
uint8_t hal_fb_get(uint32_t idx) { return fb[back][idx % (FB_STRIDE * 240)]; }

const uint8_t *host_front_buffer(void) { return fb[back ^ 1]; }
const uint8_t *host_back_buffer(void)  { return fb[back]; }
const uint16_t *host_palette(void)     { return kc_palette; }
int host_fb_mode(void)                 { return (int)fb_mode; }

// ---- chunk engine: chunk (cx,cz) <-> slot (cx&3, cz&3). DDR3 order y, z, x. -----------------
static void chunk_cmd(uint32_t cmd) {
    uint32_t cx = cmd & 255, cz = (cmd >> 8) & 255, id = cz * 256 + cx;
    int store = (cmd >> 31) & 1;
    uint32_t sx = (cx & 3) * 16, sz = (cz & 3) * 16;
    if (store && !ddr[id]) ddr[id] = calloc(16 * 32 * 16, 1);
    for (uint32_t y = 0; y < 32; y++)
        for (uint32_t z = 0; z < 16; z++)
            for (uint32_t x = 0; x < 16; x++) {
                uint8_t *b = &bram_world[WIN_INDEX(sx + x, y, sz + z)];
                uint32_t c = (y * 16 + z) * 16 + x;
                if (store) ddr[id][c] = *b;
                else *b = ddr[id] ? ddr[id][c] : 0;
            }
    if (store) hstats.chunk_stores++; else hstats.chunk_loads++;
    chunk_done++;
}

// ---- MMIO -------------------------------------------------------------------------------
uint32_t hal_mmio_r(uint32_t off) {
    switch (off) {
    case MMIO_FB_SWAP:     return 0;                       // swaps complete immediately
    case MMIO_FRAME_COUNT: return frame_count;
    case MMIO_VSYNC:       return 1;
    case MMIO_CYCLES:
        if (realtime) cycles = (now_ns() - t0_ns) * (CORE_HZ / 1000000u) / 1000u;
        else cycles += 64;                             // a free-running counter moves between reads
        return (uint32_t)cycles;
    case MMIO_UART_RX:     return rx_head != rx_tail ? rx_fifo[rx_tail++ & 255] : 0;
    case MMIO_UART_STATUS: return rx_head != rx_tail ? 1u : 0u;
    case MMIO_ERR: case MMIO_ERR_PC: return 0;
    case MMIO_FB_MODE:     return fb_mode;
    case MMIO_DDR_STATUS:  return (uint32_t)storage_ok;    // memory API ready, idle
    case MMIO_CHUNK_DONE:  return chunk_done;
    case MMIO_SLOT_VALID:  return slot_valid;
    case MMIO_WIN_ORIGIN:  return win_origin;
    default: fprintf(stderr, "hal: read of unknown MMIO 0x%02x\n", off); abort();
    }
}

void hal_mmio_w(uint32_t off, uint32_t v) {
    switch (off) {
    case MMIO_FB_SWAP:
        if (v & 1) { back ^= 1; frame_count++; hstats.frames++; host_on_swap(); }
        break;
    case MMIO_UART_TX:     fputc((int)(v & 255), stderr); break;
    case MMIO_ERR:         break;
    case MMIO_LEDS:        leds = v; break;
    case MMIO_FB_MODE:     fb_mode = v & 1; break;
    case MMIO_CHUNK_CMD:   chunk_cmd(v); break;
    case MMIO_SLOT_VALID:  slot_valid = v & 0xFFFF; break;
    case MMIO_WIN_ORIGIN:
        if ((v & 0x0F) || (v & 0x0F00)) { fprintf(stderr, "hal: WIN_ORIGIN not chunk aligned 0x%x\n", v); abort(); }
        win_origin = v & 0x3F3F; break;
    default: fprintf(stderr, "hal: write to unknown/read-only MMIO 0x%02x\n", off); abort();
    }
}

// ---- host-side hooks -----------------------------------------------------------------------
void host_push_key(uint8_t b) { rx_fifo[rx_head++ & 255] = b; }
void host_advance_cycles(uint32_t c) { cycles += c; }
