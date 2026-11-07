// trace.c — ray setup + voxel DDA. Branch-free per lane; the only loop condition is a
// BALLOT, so the same code runs on 1 lane (laptop, Stage 0) and 8 lanes (Stage 1).
#include "trace.h"
#include "kc_hal.h"
#include "kc_lanes.h"

#if KC_LANES == 1
uint32_t kc_soft_mask = 1;
#endif

void ray_setup(kc_ray *r, const q16 o[3], const q16 d[3]) {
    uint32_t signs = 0;
    for (int i = 0; i < 3; i++) {                     // unrolled by -O2; uniform trip count
        int32_t neg = (int32_t)((uint32_t)d[i] >> 31);
        q16 ad = sel(neg, -d[i], d[i]);
        q16 td = qrcp(ad);                            // tDelta = 1/|d|
        q16 fr = qfrac(o[i]);
        fr = sel(neg, fr, Q16_ONE - fr);              // distance to the first boundary
        r->f[1 + i] = (uint32_t)qmul(fr, td);         // tMax
        r->f[4 + i] = (uint32_t)td;
        signs |= (uint32_t)neg << i;
    }
    r->f[0] = CELL_PACK(qfloor(o[0]), qfloor(o[1]), qfloor(o[2]));
    r->f[7] = signs;
}

void vtrace_ref(const kc_ray *r, int32_t max_steps, kc_hit *h) {
    int32_t x = CELL_X(r->f[0]), y = CELL_Y(r->f[0]), z = CELL_Z(r->f[0]);
    q16 tmx = (q16)r->f[1], tmy = (q16)r->f[2], tmz = (q16)r->f[3];
    q16 tdx = (q16)r->f[4], tdy = (q16)r->f[5], tdz = (q16)r->f[6];
    int32_t nx = r->f[7] & 1, ny = (r->f[7] >> 1) & 1, nz = (r->f[7] >> 2) & 1;
    int32_t sx = 1 - 2 * nx, sy = 1 - 2 * ny, sz = 1 - 2 * nz;

    int32_t steps = 0, ax = 0, neg = 0, typ = 0, hit = 0;
    q16 t = 0;
    uint32_t saved = mask_get();
    for (;;) {
        int32_t cx = (tmx <= tmy) & (tmx <= tmz);
        int32_t cy = (cx ^ 1) & (tmy <= tmz);
        int32_t cz = (cx | cy) ^ 1;
        t   = sel(cx, tmx, sel(cy, tmy, tmz));
        ax  = sel(cy, 1, sel(cz, 2, 0));
        neg = sel(cx, nx, sel(cy, ny, nz));
        x += sel(cx, sx, 0);  y += sel(cy, sy, 0);  z += sel(cz, sz, 0);
        tmx += sel(cx, tdx, 0); tmy += sel(cy, tdy, 0); tmz += sel(cz, tdz, 0);
        steps++;

        int32_t oob = ((uint32_t)x > 63u) | ((uint32_t)y > 31u) | ((uint32_t)z > 63u);
        typ = hal_win_get(x & 63, y & 31, z & 63);   // always a legal address
        hit = (typ != 0) & (oob ^ 1);
        int32_t alive = ((hit | oob) ^ 1) & (steps < max_steps);
        lmask((uint32_t)alive);                      // finished lanes freeze their registers
        if (ballot(1) == 0) break;                   // uniform: "any lane still walking?"
    }
    mask_set(saved);

    h->res  = (uint32_t)hit | ((uint32_t)ax << 1) | ((uint32_t)neg << 3)
            | ((uint32_t)(typ & -hit) << 4) | ((uint32_t)steps << 8);
    h->cell = CELL_PACK(x, y, z);
    h->t    = t;
}

#if KC_VTRACE
// Ray unit, custom-1 (0x2B). funct7 carries the field number.
#define VSET(field, v) __asm__ volatile(".insn r 0x2B, 0, " #field ", x0, %0, x0" :: "r"(v))
void kc_trace(const kc_ray *r, int32_t max_steps, kc_hit *h) {
    VSET(0, r->f[0]); VSET(1, r->f[1]); VSET(2, r->f[2]); VSET(3, r->f[3]);
    VSET(4, r->f[4]); VSET(5, r->f[5]); VSET(6, r->f[6]); VSET(7, r->f[7]);
    uint32_t res, cell, t;
    __asm__ volatile(".insn r 0x2B, 1, 0, %0, %1, x0" : "=r"(res) : "r"(max_steps) : "memory");
    __asm__ volatile(".insn r 0x2B, 2, 0, %0, x0, x0" : "=r"(cell));
    __asm__ volatile(".insn r 0x2B, 2, 1, %0, x0, x0" : "=r"(t));
    h->res = res & 0xFFFFu; h->cell = cell; h->t = (q16)t;
}
#else
void kc_trace(const kc_ray *r, int32_t max_steps, kc_hit *h) { vtrace_ref(r, max_steps, h); }
#endif
