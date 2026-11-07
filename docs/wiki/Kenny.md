# Kenny

Engine, game, look. Owner · Kennedy.

## My stages

| Stage | Builds | Done when | Needs first |
| --- | --- | --- | --- |
| Stage 0 · one lane, the whole game | Plain C renderer, game loop and chunk manager (chunks.h) from hour 0, with the same files building for the laptop and the chip. Flat colors and a 16-step view distance until Stage 1. | The game plays on the board at 1 to 3 fps by hour 5. | Nothing for plain C. Bennett's toolchain by hour 2. |
| Stage 1 · eight lanes | 8-lane kernel on the simulator (mask loop for the DDA walk, sel() everywhere else). Textures. C reference for one ray by hour 6. | The 8-lane kernel matches plain C with no DIVERGE errors. | Custom instructions in the simulator. |
| Stage 2 · VTRACE | VTRACE path in the kernel (8 VSETs, vtrace, VGET). | Same pixels as the software DDA. | VTRACE in the simulator. |
| Pipelined core | Game polish, hotbar, crosshair. Switches to FB\_MODE 0 (320×240) once the pipelined core lands. | The game runs at 320×240. | Pipelined core on the board. |
| Stage 3 · stretch | Kernel side of each stretch (fog, shadow rays). Devpost, video, pitch. | The final build plays for 5 minutes with no error LED. | Final bitstream by hour 21. |

## How Kennedy iterates

Use the fastest loop that can show the bug. Only move to a slower one when the faster one passes.

| Loop | Time per try | Use it for |
| --- | --- | --- |
| Plain C on the laptop, with an SDL3 window | Under a second | How the game looks and feels. Textures, palette, fog, physics, controls. |
| make sim (from hour 5) | Seconds | Anything that touches gpu.h, masks or lanes. Stray branches and divergence halt with a PC. |
| make check | About a minute | Before anything goes to the board. Golden shots on plain C, sim and Verilator. |
| make board | Under a minute | Hours 0 to 5 directly. After that, only once make check passes. |

- Keep render.c and game.c free of anything platform-specific, so the same files compile for the laptop and for RISC-V. Window, keys and the framebuffer pointer live in platform\_pc.c and platform\_kc.c.
- On the laptop build, gpu.h runs lane\_id(), sel() and lmask() as an 8-wide loop. Plain C then behaves like 8 lanes and catches mask bugs before the simulator does.
- Golden shots are 8 fixed camera blocks checked into the repo. Any change that moves a pixel shows up as a diff image.
- Record key replay files while playing on the laptop, so a physics bug reproduces the same way on every rung.

## Engine & Game

**Owner · Kennedy · Status · Draft**

### Fixed point

```c
typedef int32_t fx;                      /* Q16.16, 1.5 == 98304 */
#define FX_ONE  (1 << 16)
#define FX(x)   ((fx)((x) * 65536))      /* constants only, folded at compile time */
static inline fx fx_mul(fx a, fx b) { return (fx)(((int64_t)a * b) >> 16); }
fx fx_recip(fx x);   /* from the 4 KB table in .rodata, clamps near 0 to 0x7FFFFFFF */
```

No floats, no division, no malloc, no STL. Fixed-size arrays set up at startup. Per-frame scratch buffers come from the arena (Arena Allocator section (Bennett tab)), never from big local arrays, since each lane stack is only 1 KB.

### Rendering kernel

Shades 8 pixels at a time, one per lane. It's the only GPU kernel.

**Per frame (tile rendering, D15).** The game writes the camera block. The kernel walks the screen in 8 × 8-pixel tiles, left to right, then top to bottom, which is 300 tiles at 160 × 120. Each tile takes 8 passes of the 8 lanes, and each pass shades a 4 × 2 block. In pass p of tile (tx, ty), lane L shades pixel x = 8 × tx + 4 × (p & 1) + (L & 3), y = 8 × ty + 2 × (p >> 1) + (L >> 2).

**Why tiles.** Pixels in a compact block send rays in similar directions, so the 8 lanes finish their walks at similar times and fewer sit idle waiting on the slowest one. A tile buffer for burst write-out isn't worth it at 160 × 120, where all pixel stores together cost about 0.4 ms per frame.

**Per pixel group**

1. **Ray.** direction = forward + (x − W/2) × right\_step − (y − H/2) × up\_step
2. **Setup.** Step sign per axis. tDelta = fx\_recip(|dir|). tMax = distance to the first block edge × tDelta.
3. **Walk, Stages 0–1.** Mask loop from the GPU Core section (Tai tab). Pick the smallest tMax with `sel()` (no per-lane branches), step one block, load the world, `lmask()` lanes that hit or left the world.
4. **Walk, Stage 2.** 8 VSETs, one `vtrace(160)`, one `VGET(1)`. Same inputs and outputs as step 3.
5. **Shade.** Face picks the top, side or bottom texture. Texel u, v = top 4 fraction bits of the hit point on the face's other two axes. Shade by face (top brightest). Fog = min(3, steps / 8) computed as `steps >> 3` clamped, so fog is full by about 24 steps and the edge of the chunk window never shows (fog level 3 is the sky color in the palette). No hit = sky by screen row.
6. **Write** the pixel byte. The kernel never touches FB\_SWAP. The game writes it after the kernel returns (MMIO only with mask 0x01).

**Kernel rules.** Prefer `sel()` over `if` on lane values. Use GPU\_IF only for big bodies. Run on the simulator before every hardware test. Look at `kc.dis` once for stray branches.

**Resolution.** 160×120 (FB\_MODE 1) through Stage 2. 320×240 only after pipelining (D6).

### Game on the chip

Same core, taking turns each frame.

1. Poll FB\_SWAP until it reads 0, so the last frame's swap has happened.
2. Read key bytes from UART\_RX until the FIFO is empty, update key state.
3. Move the player. Walk about 4.3 blocks/s, gravity, jump. Collide one axis at a time. Box 0.6 × 1.8 × 0.6, eye at 1.62.
4. `world_update(px, pz)` keeps the 4 × 4-chunk window around the player (Chunk API below).
5. Pick. Walk the eye ray up to 5 blocks to find the aimed-at block and the empty cell before it.
6. J breaks (writes air). K places the selected type unless it overlaps the player. 1–9 select. Both go through `world_set()`.
7. Write the camera block.
8. `mask_all()`, run the kernel, `mask_set(1)`.
9. Write 1 to FB\_SWAP.

**Startup.** Wait until DDR\_STATUS says DDR3 is calibrated, then fill the 16 chunks around the spawn point. Terrain is fixed-point value noise as a function of absolute (x, z), so any chunk can be generated on demand (heights about 10–25, grass, 3 dirt, stone, bedrock, sand low, trees from a seeded hash).

**Block types.** 0 air · 1 grass · 2 dirt · 3 stone · 4 cobblestone · 5 log · 6 leaves · 7 planks · 8 sand · 9 brick · 10 bedrock · 11 redstone wire (stretch) · 12 lamp (stretch) · 13–15 spare

**Fallback.** None needed. The game runs on the chip from hour 5, and the same C runs natively on the laptop for development. If DDR3 is cut (D14), chunk\_load and chunk\_store become no-ops and every chunk is generated.

### Chunk API (D14)

Game code never touches DDR3 or the chunk registers directly. It calls chunks.h, and the chunk manager keeps the 4 × 4-chunk window around the player. Formats and registers are in Interfaces, Chunks (Shared tab).

```c
#pragma once
#include <stdint.h>

/* ---- high level: what game code calls ---- */
void    world_update(int px, int pz);                 /* once per frame, mask 0x01 */
uint8_t world_get(int x, int y, int z);               /* absolute coords, air if not loaded */
void    world_set(int x, int y, int z, uint8_t t);    /* writes the window, marks the chunk dirty */
int     world_corner_x(void);                         /* window corner, absolute block coords */
int     world_corner_z(void);

/* ---- low level: one MMIO access each, used by the chunk manager ---- */
uint32_t chunk_load(int cx, int cz);    /* DDR3 chunk -> its slot, returns a ticket */
uint32_t chunk_store(int cx, int cz);   /* its slot -> DDR3 chunk, returns a ticket */
int      chunk_done(uint32_t ticket);   /* 1 once that command has finished */
void     chunk_wait(uint32_t ticket);
void     slot_valid(int cx, int cz, int on);
void     window_origin(int corner_x, int corner_z);   /* multiples of 16 */
```

**How a call reaches the hardware.** `chunk_load(cx, cz)` is one store of (cz << 8) | cx to CHUNK\_CMD and returns a ticket, which is the number of commands issued so far. `chunk_done(t)` reads CHUNK\_DONE and checks it has reached t. Nothing waits unless you call `chunk_wait()`.

**What world\_update does each frame**

1. The wanted window is the 4 × 4 chunks centered nearest the player, starting at chunk round((p − 32) / 16) on each axis. The player then always sits 24 to 40 blocks from every window edge.
2. For each slot holding the wrong chunk, clear its valid bit, and queue `chunk_store` if it's dirty.
3. If the new chunk was generated before (bitmap in data memory, 8 KB), queue `chunk_load`. If not, generate it straight into the window and mark it generated and dirty.
4. When a load's ticket is done, set that slot valid. When the whole new edge is in, call `window_origin()`.
5. Generating a never-seen chunk costs about 8 ms, so the manager generates at most one per frame.

**Rules**

- Only game code calls this, with mask 0x01. The render kernel never does.
- The camera block stays in absolute coordinates. The kernel subtracts `world_corner_x()` and `world_corner_z()` to get the ray's start cell in window coordinates before VSET field 0.
- Redstone, sand and every other update only run on loaded chunks.
- The laptop build implements the same header with a 256 MB array that copies instantly, so the chunk manager is written and tested on the laptop first. Rays that leave the window return hit = 0 and draw as fogged sky.

### Assets

- [ ] 16 types × 3 faces of 16×16 textures, 4-bit indexed
- [ ] 256-entry palette (texel × shade × fog)
- [ ] 1/x table generator
- [ ] Crosshair, hotbar, controls card for the table

### Testing ladder

Plain C on the laptop (PNG) → instruction simulator (PNG) → Verilator (PNG + trace) → board (framebuffer sent over UART\_TX on a debug key). Every rung produces the same pixels as the one before. The day-to-day loop is in How Kennedy iterates, above.

## Pitch

**Owner · Kennedy · Status · Draft**

Lead with the live game, then the claim. "This board is the whole computer. We turned a CPU into a GPU this weekend, built a ray unit for it, and wrote a voxel engine that runs on every lane."

| Part | Time | Content |
| --- | --- | --- |
| Hook | 15 s | Hand a judge the keyboard. "Everything on this screen, the game logic and every pixel, runs on hardware we designed." |
| What we built | 30 s | An 8-lane SIMD GPU grown from a RISC-V core, custom lane and ray instructions, hardware divergence handling, a memory system that feeds every lane, a toolchain, and KennyCraft |
| How it works | 45 s | Architecture diagram. Why a ray unit (one instruction walks a whole ray, like RT cores). Why multi-cycle first (correct divergence before speed). |
| Proof | 20 s | Simulator vs hardware pixel match. LUTs, BRAM, MHz, fps from the real reports. |
| Impact | 15 s | An open teaching platform you can read from game code down to circuits, on a student-priced board. Repo goes public after the event. |
| Next | 10 s | Pipelining, warps, DDR3 for bigger worlds, DOOM on an in-world screen |

**If a judge knows the HackMIT 2026 GPU.** Theirs is the stronger general-purpose design (16 lanes, 4 warps, five demos). Ours is built for graphics. KennyCraft renders on every lane through a hardware ray unit, and the game runs on the chip too. The CPU core is credited in the README as "inspired by" Tai's earlier RV32I project (D11). Say so plainly if asked, and present the weekend's work.

**Judging criteria (2025 list).** Innovation · Technical complexity · Completeness (never crash in front of a judge) · Design (crosshair, hotbar, textures, controls card) · Impact · Presentation (rehearse 60-second and 3-minute versions)

**Sources** · [HackMIT GPU writeup](https://armaangomes.com/blogs/hackmitgpu/) · [HackUTD 2026 Zero Day](https://zeroday.hackutd.co/) · [HackUTD 2025 Devpost](https://hackutd-2025.devpost.com/)
