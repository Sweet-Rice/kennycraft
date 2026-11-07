# Bennett

Toolchain, simulator, Verilator. Owner · Bennett.

## My stages

| Stage | Builds | Done when | Needs first |
| --- | --- | --- | --- |
| Stage 0 · one lane, the whole game | GCC, kc.ld, crt0, the ELF-to-hex script and make board by hour 2. Then the simulator with RV32I, every custom instruction and the chunk engine model by hour 4, and the Verilator harness on Tai's RTL. | make board works by hour 2. Custom instructions in the simulator by hour 5. | Interfaces v1.0. Tai's top module ports. |
| Stage 1 · eight lanes | Per-instruction test programs, each with a make vl target. tracediff and make check. | Every t\_ test passes on the simulator and in Verilator. | Opcode tables in Interfaces v1.0. |
| Stage 2 · VTRACE | VTRACE model in the simulator. Regression on every RTL change. | Simulator and board agree on VTRACE frames. | VTRACE port list. |
| Pipelined core | tracediff of the pipelined core against the multi-cycle core. | Traces match on every test and on a replayed play session. | The agent's core building in Verilator. |
| Stage 3 · stretch | Regression on every stretch build. Backup demo video. | make check is green on whatever ships. | The stretch RTL. |

## Bennett's role

Bennett owns the bench that every stage is judged against. When Tai and Kennedy disagree about a pixel, Bennett's tools say who is right.

- **Toolchain.** GCC, gpu.h, kc.ld, crt0, the Makefile and the two hex images.
- **Instruction simulator.** The reference for everything from Stage 1 on (Toolchain & Simulator section below).
- **Verilator harness.** Runs Tai's RTL on the same hex images, writes a PNG per frame, prints traces, and replays key files (Toolchain & Simulator section below).
- **Regression.** Per-instruction tests, golden camera shots, and make check, which has to pass before every make board.
- **Agent checks.** The trace comparison that decides whether the pipelining agent's core is correct.

## Toolchain & Simulator

**Owner · Bennett · Status · Draft**

### Compiler

Use the xPack `riscv-none-elf-gcc` (easiest install on every OS) or `riscv64-unknown-elf-gcc`, version 12 or newer for Zmmul.

```makefile
CFLAGS  = -march=rv32i_zmmul -mabi=ilp32 -O2 -ffreestanding -nostdlib \
          -fno-builtin -msmall-data-limit=0 -Wall
LDFLAGS = -T kc.ld -nostdlib
LIBS    = -lgcc
```

If `rv32i_zmmul` isn't accepted, fall back to `rv32im` and never write `/` or `%` in chip code.

### gpu.h

```c
#pragma once
#include <stdint.h>
/* ---- lane control: custom-0 (0x0B) ---- */
static inline uint32_t lane_id(void) {
    uint32_t r;
    asm volatile(".insn r 0x0B, 0, 0, %0, x0, x0" : "=r"(r));
    return r;
}
static inline void lmask(uint32_t keep) {
    asm volatile(".insn r 0x0B, 1, 0, x0, %0, x0" :: "r"(keep) : "memory");
}
static inline uint32_t ballot(uint32_t pred) {
    uint32_t r;
    asm volatile(".insn r 0x0B, 3, 0, %0, %1, x0" : "=r"(r) : "r"(pred) : "memory");
    return r;
}
static inline uint32_t mask_get(void) {
    uint32_t r;
    asm volatile(".insn r 0x0B, 5, 0, %0, x0, x0" : "=r"(r) :: "memory");
    return r;
}
static inline void mask_set(uint32_t m) {
    asm volatile(".insn r 0x0B, 6, 0, x0, %0, x0" :: "r"(m) : "memory");
}
static inline void mask_all(void) {
    asm volatile(".insn r 0x0B, 7, 0, x0, x0, x0" ::: "memory");
}
/* ---- divergence: custom-2 (0x5B) ---- */
#define GPU_IF(cond, else_lbl) \
    asm goto(".insn b 0x5B, 0, %0, x0, %l1" :: "r"(cond) : "memory" : else_lbl)
#define GPU_ELSE(end_lbl) \
    asm goto(".insn b 0x5B, 1, x0, x0, %l0" ::: "memory" : end_lbl)
#define GPU_ENDIF() \
    asm volatile(".insn r 0x5B, 2, 0, x0, x0, x0" ::: "memory")
/* usage:
 *   GPU_IF(hit, L_else);
 *       color = shade(...);
 *   L_else:
 *   GPU_ELSE(L_end);
 *       color = sky(row);
 *   L_end:
 *   GPU_ENDIF();
 * The label goes BEFORE GPU_ELSE so a skipped then-body still runs DELSE.
 */
/* ---- ray unit: custom-1 (0x2B) ---- */
#define VSET(field, v) \
    asm volatile(".insn r 0x2B, 0, " #field ", x0, %0, x0" :: "r"(v) : "memory")
#define VGET(field) ({ uint32_t _r; \
    asm volatile(".insn r 0x2B, 2, " #field ", %0, x0, x0" : "=r"(_r) :: "memory"); _r; })
static inline uint32_t vtrace(uint32_t max_steps) {
    uint32_t r;
    asm volatile(".insn r 0x2B, 1, 0, %0, %1, x0" : "=r"(r) : "r"(max_steps) : "memory");
    return r;
}
/* ---- helpers ---- */
static inline int32_t sel(uint32_t c, int32_t a, int32_t b) {   /* branchless c ? a : b */
    int32_t m = -(int32_t)(c != 0);
    return (a & m) | (b & ~m);
}
#define gpu_keep(x) asm volatile("" : "+r"(x))   /* pin a value before a mask change */
```

### Linker script (kc.ld)

```
MEMORY {
  IMEM (rx) : ORIGIN = 0x00000000, LENGTH = 32K
  DMEM (rw) : ORIGIN = 0x10000100, LENGTH = 0x5F00
}
SECTIONS {
  .text   : { *(.text.start) *(.text*) } > IMEM
  .rodata : { *(.rodata*) } > DMEM
  .data   : { *(.data*) }   > DMEM
  .bss    : { __bss_start = .; *(.bss*) *(COMMON) __bss_end = .; } > DMEM
}
```

`.rodata` goes in data memory because instruction memory isn't readable by loads. Both memory images are loaded when the FPGA is configured, so nothing needs copying at startup. Stacks sit above 0x1000\_6000 and aren't in the linker script.

### Startup (crt0.S)

```asm
    .section .text.start
    .globl _start
_start:
    .insn r 0x0B, 7, 0, x0, x0, x0      # MASKALL
    .insn r 0x0B, 0, 0, t0, x0, x0      # t0 = LANEID
    slli  t0, t0, 10                    # lane * 1024
    li    sp, 0x10008000
    sub   sp, sp, t0                    # each lane gets its own 1 KB stack
    li    t1, 1
    .insn r 0x0B, 6, 0, x0, t1, x0      # MASKSET 1, lane 0 only
    la    a0, __bss_start
    la    a1, __bss_end
1:  bgeu  a0, a1, 2f
    sw    zero, 0(a0)
    addi  a0, a0, 4
    j     1b
2:  call  main
3:  j     3b
```

### Build

One make turns crt0.S, game.c and kernel.c into kc.elf, plus kc.dis (disassembly), kc.map, and two memory images. kc\_imem.hex holds .text and kc\_dmem.hex holds .rodata and .data, one 32-bit word per line in $readmemh format (objcopy to binary, then a 20-line Python script). Check `kc.dis` for branches inside the kernel's lane code.

### Instruction simulator

C++, runs the same ELF. It is the reference everyone else is checked against.

- [ ] State. PC, mask, 8 × 32 registers, divergence stack, every memory region from the map.
- [ ] Executes RV32I + Zmmul + all custom instructions with the exact encodings, masking rules and illegal cases in Tai\_2 sections 1 and 2.
- [ ] MMIO. UART RX from a file or stdin, UART TX to the terminal, FB\_SWAP dumps the front buffer to a PNG. The chunk registers (0x2C to 0x3C) copy chunks between a sparse 256 MB DDR3 array and the window after a configurable delay, with WIN\_ORIGIN and SLOT\_VALID applied to every world access (D14).
- [ ] Uniform-branch and divergence-stack errors halt and print every lane's operands.
- [ ] Cycle estimate using the CPU Core section's CPI table (Tai tab), so frame-rate numbers exist before hardware does.
- [ ] Trace mode. One line per retired instruction, `pc instr mask lane:rd=value ...`. Verilator prints the same format and a script reports the first mismatch.
- [ ] Optional. SDL3 window and keyboard, so the whole game is playable on the simulator.

### Verilator harness

- Owner Bennett. Verilator compiles Tai's SystemVerilog top (minus the MMCM and VGA pins) into a C++ model that runs on a laptop.
- Loads the same kc\_imem.hex and kc\_dmem.hex the board uses, so every rung runs the identical program. MIG can't be simulated in Verilator, so the harness builds with ddr\_model.sv behind the same chunk engine.
- Runs a set number of frames and writes the back framebuffer to a PNG at every FB\_SWAP, in the same format as the simulator.
- Prints the trace format from the simulator section. tracediff.py reports the first instruction where Verilator and the simulator disagree, with every lane's registers.
- Key input comes from a replay file (frame number, key byte), so a bug reproduces the same way every run.
- Optional VCD waveform dump for a window of cycles around the first mismatch, so Tai can open it in GTKWave without rerunning.
- Optional live mode with an SDL3 window and keyboard, running the real RTL at whatever speed Verilator manages.
- Tai keeps the top module's ports stable from hour 1, so Bennett can build the harness against any Stage 0 snapshot that compiles.

### Make targets

```
make sim     # instruction simulator, PNG per frame, cycle estimate
make vl      # Verilator, PNG per frame, trace, diff against make sim
make check   # every t_ test plus golden camera shots on plain C, sim and Verilator, fails on the first mismatch
make board   # updatemem into the last bitstream, then program the Arty
make keys    # kc.py, forwards key bytes, prints UART_TX debug text
```

make board needs one full Vivado build first, plus the memory map file from write\_mem\_info. After that only RTL changes need a full rebuild, and a program change reaches the board in under a minute. make check has to pass before make board.

## Arena Allocator

**Owner · Bennett · Status · Draft**

Fixed-size scratch memory for game code. It replaces malloc and big local arrays, which would overflow the 1 KB lane stacks. The arena is the same size in Kennedy's laptop build and on the chip, so running out shows up on the laptop first.

### How it works

One static 8 KB array in .bss plus an offset. arena\_alloc() rounds the request up to 4 bytes, hands out the next chunk and moves the offset. A request that doesn't fit halts with an error instead of returning NULL. arena\_reset() puts the offset back to 0 at the start of every frame.

### arena.h

```c
#pragma once
#include <stdint.h>
#define ARENA_SIZE (8 * 1024)   /* bytes, same on laptop and chip */
void     arena_reset(void);             /* top of every frame */
void    *arena_alloc(uint32_t bytes);   /* 4-byte aligned, halts when full */
uint32_t arena_high_water(void);        /* peak bytes used since boot */
```

### arena.c

```c
#include "arena.h"
static uint8_t  arena_buf[ARENA_SIZE] __attribute__((aligned(4)));
static uint32_t arena_top, arena_peak;
__attribute__((noreturn)) static void arena_panic(uint32_t bytes);
void arena_reset(void) { arena_top = 0; }
void *arena_alloc(uint32_t bytes) {
    bytes = (bytes + 3u) & ~3u;
    if (bytes > ARENA_SIZE - arena_top) arena_panic(bytes);
    void *p = &arena_buf[arena_top];
    arena_top += bytes;
    if (arena_top > arena_peak) arena_peak = arena_top;
    return p;
}
uint32_t arena_high_water(void) { return arena_peak; }
#ifdef KC_CHIP
static void arena_panic(uint32_t bytes) {
    (void)bytes;
    *(volatile uint32_t *)0x50000024 = 0xA;   /* LEDS pattern 1010 */
    for (;;) { }                              /* jump-to-self, the simulator halts here */
}
#else
#include <stdio.h>
#include <stdlib.h>
static void arena_panic(uint32_t bytes) {
    fprintf(stderr, "arena full: asked %u, peak %u of %u\n",
            (unsigned)bytes, (unsigned)arena_peak, (unsigned)ARENA_SIZE);
    abort();
}
#endif
```

### Usage

```c
void game_frame(void) {
    arena_reset();
    uint8_t *visible = arena_alloc(64 * 64);   /* 4 KB scratch, gone next frame */
    /* ... */
}
```

### Rules

- Game code only, with mask = 0x01. Never call arena\_alloc() inside the render kernel. All 8 lanes would bump the offset at once, the serialized stores race, and lanes end up sharing buffers.
- The game calls arena\_reset() at the top of each frame, so nothing from the arena survives the frame. Data that has to last (world, player, key state) stays in fixed static arrays.
- Any local array bigger than about 64 bytes goes in the arena, not on the stack.
- No recursion in chip code. The compiler can't bound its stack use.
- ARENA\_SIZE is set once in arena.h and used by both builds. Changing it goes through the Decisions section (Shared tab).

### How overflow gets caught

- Laptop build. arena\_panic() prints the request size and the peak, then aborts.
- Chip build (compiled with -DKC\_CHIP). arena\_panic() lights LEDS pattern 1010 and spins.
- Simulator. Halts on any jump-to-self and prints the PC, which catches this and the end of main().
- Link time. The arena is in .bss, so it counts against DMEM. If .data, .rodata and .bss together pass the DMEM length in kc.ld, the build fails.
- Peak tracking. arena\_high\_water() reports the most ever used. Print it on the laptop and send it over UART on the chip. Keep the peak under 6 KB for headroom.

### DMEM math

The DMEM region in kc.ld is 0x5F00, about 23.75 KB. The 1/x table takes 4 KB, the arena 8 KB and the chunk-generated bitmap 8 KB (D14), which leaves about 3.75 KB for everything else in .data, .rodata and .bss. If that runs out, shrink the arena to 4 KB first. Check kc.map after every build.

### Checklist

- [ ] Bennett · arena.h and arena.c in the repo, both builds compile
- [ ] Bennett · -DKC\_CHIP in the chip build only
- [ ] Bennett · simulator halts on jump-to-self and prints the PC
- [ ] Kennedy · scratch buffers moved from locals to arena\_alloc()
- [ ] Kennedy · arena\_high\_water() printed once per second on the laptop build
