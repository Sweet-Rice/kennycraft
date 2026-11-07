// hal_host.h — laptop-only hooks into the emulated chip.
#ifndef KC_HAL_HOST_H
#define KC_HAL_HOST_H
#include <stdint.h>

typedef struct {
    uint64_t world_reads, frames, chunk_loads, chunk_stores;
} host_stats;
extern host_stats hstats;

void host_init(int realtime_clock);          // 1: CYCLES follows the wall clock; 0: host_advance_cycles
void host_push_key(uint8_t key_byte);
void host_advance_cycles(uint32_t cycles);
const uint8_t  *host_front_buffer(void);     // what VGA shows (after the last swap)
const uint8_t  *host_back_buffer(void);
const uint16_t *host_palette(void);          // RGB444
int  host_fb_mode(void);                     // 1 = 160x120
void host_on_swap(void);                     // implemented by the front-end

int  png_write_fb(const char *path, const uint8_t *fb, const uint16_t *pal, int w, int h, int scale);

#endif
