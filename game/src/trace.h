// trace.h — ray setup and voxel traversal (Amanatides & Woo DDA).
// kc_trace() has exactly the VTRACE contract from the Interfaces section, so:
//   * the software build of it IS the "C reference for one ray" for the VTRACE testbench,
//   * swapping in the hardware unit (KC_VTRACE=1) changes nothing above this file.
#ifndef KC_TRACE_H
#define KC_TRACE_H
#include <stdint.h>
#include "fixed.h"

// VSET fields. f[0] start cell packed (x 5:0, y 10:6, z 16:11); f[1..3] tMax x,y,z;
// f[4..6] tDelta x,y,z (Q16.16); f[7] step signs (bit0 x, bit1 y, bit2 z; 1 = negative).
typedef struct { uint32_t f[8]; } kc_ray;

// VTRACE result + VGET fields.
typedef struct {
    uint32_t res;    // bit0 hit, 2:1 face axis, 3 face sign, 7:4 type, 15:8 steps
    uint32_t cell;   // VGET 0: hit cell packed like f[0]
    q16      t;      // VGET 1: t at hit
} kc_hit;

#define HIT_HIT(r)   ((r) & 1u)
#define HIT_AXIS(r)  (((r) >> 1) & 3u)
#define HIT_NEG(r)   (((r) >> 3) & 1u)
#define HIT_TYPE(r)  (((r) >> 4) & 15u)
#define HIT_STEPS(r) (((r) >> 8) & 255u)
#define CELL_PACK(x, y, z) (((uint32_t)(x) & 63u) | (((uint32_t)(y) & 31u) << 6) | (((uint32_t)(z) & 63u) << 11))
#define CELL_X(c) ((int32_t)((c) & 63u))
#define CELL_Y(c) ((int32_t)(((c) >> 6) & 31u))
#define CELL_Z(c) ((int32_t)(((c) >> 11) & 63u))

// Build VSET fields from a window-relative origin and a direction (both Q16.16).
// The origin must be inside the window. Branch-free: safe on 8 lanes.
void ray_setup(kc_ray *r, const q16 o[3], const q16 d[3]);

// Step the ray up to max_steps (1..255) until it hits a solid block or leaves the window.
// Rules (must match vtrace.sv): the start cell is never tested; ties pick x, then y, then z
// (x if tMax.x <= tMax.y && tMax.x <= tMax.z, else y if tMax.y <= tMax.z, else z);
// a ray that leaves the window or runs out of steps returns hit = 0, type = 0.
void kc_trace(const kc_ray *r, int32_t max_steps, kc_hit *h);

// Always the software version (used by tests to compare against VTRACE).
void vtrace_ref(const kc_ray *r, int32_t max_steps, kc_hit *h);

#endif
