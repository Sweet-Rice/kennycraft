// chunks.c — world memory API (issue #2). Lane 0 only.
//
// world_update, per frame:
//   1. Wanted window = 4 x 4 chunks from round((p - 32) / 16) per axis (player 24-40 blocks
//      from every edge), clamped to the world.
//   2. Each slot holding the wrong chunk: clear its SLOT_VALID bit, chunk_store it if dirty.
//   3. Incoming chunk generated before (8 KB bitmap) -> chunk_load; otherwise generate it
//      into the window, mark it generated + dirty. At most one generation per frame after
//      startup (startup generates all 16).
//   4. A load whose ticket is done -> slot valid. Whole new window in -> window_origin().
//
// Addressing: the CPU uses window-relative x, z in 0..63 and hardware adds WIN_ORIGIN, so
// physical = abs & 63. Using (abs - committed_corner) & 63 reaches the right BRAM cell even
// for a chunk the committed window doesn't cover yet, which is what lets the new edge fill
// in before window_origin() moves.
//
// Fallback (KC_NO_DDR, or DDR_STATUS never calibrates): chunk_load/chunk_store are no-ops
// and every chunk is generated. Game code doesn't change.
#include "chunks.h"
#include "blocks.h"
#include "terrain.h"
#include "kc_hal.h"
#include "fixed.h"
#if KC_RASTER
#include "mesh.h"
#define MESH_MARK_SLOT(s) mesh_mark_slot(s)
#define MESH_MARK_BLOCK(x, z) mesh_mark_block(x, z)
#else
#define MESH_MARK_SLOT(s) ((void)0)
#define MESH_MARK_BLOCK(x, z) ((void)0)
#endif

#define CAL_TIMEOUT_CYCLES (2u * CORE_HZ)      // wait up to 2 s for DDR3 calibration

enum { S_NEED, S_LOAD, S_GEN, S_READY };

static uint8_t  generated[WORLD_CHUNKS * WORLD_CHUNKS / 8];   // 8 KB: chunk was generated before
static int32_t  slot_id[16];                   // chunk id + 1 this slot holds or is filling, 0 = none
static uint8_t  slot_state[16];
static uint8_t  slot_dirty[16];
static uint32_t slot_ticket[16];               // pending load, or the last store from this slot
static int32_t  corner_cx, corner_cz;          // committed window (= WIN_ORIGIN)
static int32_t  target_cx = -1, target_cz = -1;
static int32_t  committed;
static uint32_t issued;                        // tickets handed out
static int32_t  storage_ok;
static int32_t  started;
static uint32_t n_generated;

// ---------------------------------------------------------------- low level --------------
uint32_t chunk_load(int cx, int cz) {
    if (!storage_ok) return issued;            // fallback: no-op, already "done"
    hal_mmio_w(MMIO_CHUNK_CMD, ((uint32_t)cz << 8) | (uint32_t)cx);
    return ++issued;
}

uint32_t chunk_store(int cx, int cz) {
    if (!storage_ok) return issued;
    hal_mmio_w(MMIO_CHUNK_CMD, (1u << 31) | ((uint32_t)cz << 8) | (uint32_t)cx);
    return ++issued;
}

int chunk_done(uint32_t ticket) { return (int32_t)(hal_mmio_r(MMIO_CHUNK_DONE) - ticket) >= 0; }

void chunk_wait(uint32_t ticket) { while (!chunk_done(ticket)) {} }

void slot_valid(int cx, int cz, int on) {
    uint32_t bit = 1u << ((cz & 3) * 4 + (cx & 3));
    uint32_t v = hal_mmio_r(MMIO_SLOT_VALID);
    hal_mmio_w(MMIO_SLOT_VALID, on ? (v | bit) : (v & ~bit));
}

void window_origin(int corner_x, int corner_z) {
    hal_mmio_w(MMIO_WIN_ORIGIN, (uint32_t)(corner_x & 63) | ((uint32_t)(corner_z & 63) << 8));
}

// ---------------------------------------------------------------- helpers ----------------
static int32_t gen_bit(int32_t id) { return (generated[id >> 3] >> (id & 7)) & 1; }
static void    gen_set(int32_t id) { generated[id >> 3] |= (uint8_t)(1u << (id & 7)); }
static int32_t slot_of(int32_t cx, int32_t cz) { return (cz & 3) * 4 + (cx & 3); }

static int32_t window_c0(int32_t p) {
    return iclamp((p - 24) >> 4, 0, WORLD_CHUNKS - 4);       // = round((p - 32) / 16)
}

static void slot_ready(int32_t s) {
    slot_state[s] = S_READY;
    int32_t sx = s & 3, sz = s >> 2;                          // remesh it and its neighbors
    MESH_MARK_SLOT(s);
    MESH_MARK_SLOT(sz * 4 + ((sx + 1) & 3)); MESH_MARK_SLOT(sz * 4 + ((sx + 3) & 3));
    MESH_MARK_SLOT(((sz + 1) & 3) * 4 + sx); MESH_MARK_SLOT(((sz + 3) & 3) * 4 + sx);
    (void)sx; (void)sz;
}

// ---------------------------------------------------------------- world_update -----------
void world_update(int px, int pz) {
    if (!started) {                                           // first call: storage check
        uint32_t t0 = hal_mmio_r(MMIO_CYCLES);
#if KC_NO_DDR
        storage_ok = 0;
#else
        while (!(hal_mmio_r(MMIO_DDR_STATUS) & 1u) && hal_mmio_r(MMIO_CYCLES) - t0 < CAL_TIMEOUT_CYCLES) {}
        storage_ok = (int32_t)(hal_mmio_r(MMIO_DDR_STATUS) & 1u);
#endif
        hal_puts(storage_ok ? "kc: ddr3 chunk store ready\n" : "kc: no ddr3, generating every chunk\n");
        issued = hal_mmio_r(MMIO_CHUNK_DONE);
        for (int32_t s = 0; s < 16; s++) { slot_id[s] = 0; slot_state[s] = S_NEED; slot_ticket[s] = issued; }
        hal_mmio_w(MMIO_SLOT_VALID, 0);
        window_origin(0, 0);                                  // corner 0 until the first commit
    }

    // 1-2. New target: evict slots that hold the wrong chunk.
    int32_t tcx = window_c0(px), tcz = window_c0(pz);
    if (tcx != target_cx || tcz != target_cz) {
        target_cx = tcx; target_cz = tcz;
        for (int32_t s = 0; s < 16; s++) {
            int32_t cx = tcx + (((s & 3) - tcx) & 3);         // chunk cx lives in slot cx & 3
            int32_t cz = tcz + (((s >> 2) - tcz) & 3);
            int32_t want = cz * WORLD_CHUNKS + cx + 1;
            if (slot_id[s] == want) continue;
            if (slot_id[s]) {
                int32_t old = slot_id[s] - 1;
                if (slot_state[s] == S_READY && slot_dirty[s])
                    slot_ticket[s] = chunk_store(old & 255, old >> 8);
                slot_valid(old & 255, old >> 8, 0);
                MESH_MARK_SLOT(s);                            // drop its old mesh
            }
            slot_id[s] = want;
            slot_state[s] = S_NEED;
            slot_dirty[s] = 0;
        }
    }

    // 3. Start loads; generate (all at startup, then one per frame).
    int32_t gens = started ? 1 : 16;
    for (int32_t s = 0; s < 16; s++) {
        if (slot_state[s] != S_NEED) continue;
        int32_t id = slot_id[s] - 1;
        if (storage_ok && gen_bit(id)) {
            slot_ticket[s] = chunk_load(id & 255, id >> 8);   // engine is in order: after any store
            slot_state[s] = S_LOAD;
        } else {
            slot_state[s] = S_GEN;
        }
    }
    for (int32_t s = 0; s < 16; s++) {
        int32_t id = slot_id[s] - 1;
        if (slot_state[s] == S_LOAD && chunk_done(slot_ticket[s])) {
            slot_valid(id & 255, id >> 8, 1);
            slot_dirty[s] = 0;
            slot_ready(s);
        } else if (slot_state[s] == S_GEN && gens > 0) {
            chunk_wait(slot_ticket[s]);                       // a store may still be reading the slot
            slot_valid(id & 255, id >> 8, 1);                 // valid first: tree code reads back
            terrain_gen_chunk(id & 255, id >> 8, corner_cx * CHUNK_W, corner_cz * CHUNK_W);
            gen_set(id);
            slot_dirty[s] = 1;                                // generated chunks get stored too
            n_generated++;
            gens--;
            slot_ready(s);
        }
    }

    // 4. Whole window in: commit it.
    int32_t all = 1;
    for (int32_t s = 0; s < 16; s++) all &= slot_state[s] == S_READY;
    if (all && (!committed || corner_cx != target_cx || corner_cz != target_cz)) {
        corner_cx = target_cx; corner_cz = target_cz;
        window_origin(corner_cx * CHUNK_W, corner_cz * CHUNK_W);
        committed = 1;
    }
    started = 1;
}

// ---------------------------------------------------------------- block access -----------
static int32_t loaded_slot(int x, int z) {
    if (x < 0 || z < 0) return -1;
    int32_t cx = x >> 4, cz = z >> 4;
    int32_t s = slot_of(cx, cz);
    return (slot_id[s] == cz * WORLD_CHUNKS + cx + 1 && slot_state[s] == S_READY) ? s : -1;
}

uint8_t world_get(int x, int y, int z) {
    if (y < 0) return B_BEDROCK;
    if (y >= WIN_Y || loaded_slot(x, z) < 0) return B_AIR;
    return hal_win_get((x - corner_cx * CHUNK_W) & 63, y, (z - corner_cz * CHUNK_W) & 63);
}

void world_set(int x, int y, int z, uint8_t t) {
    int32_t s = loaded_slot(x, z);
    if (s < 0 || (uint32_t)y >= WIN_Y) return;
    hal_win_set((x - corner_cx * CHUNK_W) & 63, y, (z - corner_cz * CHUNK_W) & 63, t);
    slot_dirty[s] = 1;
    MESH_MARK_BLOCK(x, z);
}

int world_corner_x(void) { return corner_cx * CHUNK_W; }
int world_corner_z(void) { return corner_cz * CHUNK_W; }
int world_ready(void) { return committed && corner_cx == target_cx && corner_cz == target_cz; }
int world_storage_ok(void) { return storage_ok; }
int world_loaded(int x, int z) { return loaded_slot(x, z) >= 0; }
int world_slot_chunk(int s) { return slot_state[s] == S_READY ? slot_id[s] : 0; }
uint32_t world_stats_generated(void) { return n_generated; }
