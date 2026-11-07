# KennyCraft Design Doc

Nov 6, 2026 · @tai

## Overview

**KennyCraft** · one FPGA, the whole computer

HackUTD 2026 Zero Day · Nov 7–8 · 24 hours

Team · Tai (CPU/GPU hardware) · Kennedy (engine, game, look) · Bennett (toolchain, simulator, Verilator, build and test)

### How we use this doc

| Rule | Detail |
| --- | --- |
| Every tab and section has an owner | The owner edits freely. Everyone else leaves comments. |
| Frozen means frozen | Anything marked **Frozen** only changes through a change request in the Decisions section (Shared tab), acked by all three. |
| Questions live in the doc | Open questions go in the Decisions section (Shared tab) with an owner and a deadline, not in the group chat. |
| Checkboxes are live | During the event, tick boxes as things land so anyone can see status at a glance. |

| Tab | Owner | Status |
| --- | --- | --- |
| Shared | All | Live |
| Tai | Tai | Draft |
| Tai\_2 (ISA spec and agent prompts) | Tai | Draft |
| Kenny | Kennedy | Draft |
| Bennett | Bennett | Draft |

Status legend · Draft → In review → Frozen → Done

### Goal

KennyCraft is a voxel sandbox game running entirely on one Arty A7-100T. A SIMD GPU grown from Tai's RV32I core runs both the game logic and the renderer. The program is compiled straight into the bitstream, so there is no bootloader. The laptop only forwards key presses.

### Engineering principle

**Multi-cycle first, pipeline later.** Every unit (CPU, SIMD core, VTRACE) is built multi-cycle until it renders correct pixels and matches the simulator. Warp divergence and lane masking are the genuinely new problems this weekend, so we solve them on the simplest possible datapath instead of fighting hazards, forwarding and flushes at the same time. Pipelining is a performance upgrade we earn after things work.

### Staged targets

Every stage is a working demo and the fallback for the next one. Who does what in each stage, and what blocks what, is in the Stages section (Shared tab).

| Stage | Hardware | Demo | Target hour |
| --- | --- | --- | --- |
| 0 | Single-lane multi-cycle RV32I + Zmmul, program baked into BRAM, framebuffer, VGA, UART for keys, DDR3 chunk store (D14) | Kernel frame by hour 3. The whole game on one lane by hour 5, streaming chunks from DDR3, 1 to 3 fps at 160×120 (flat colors, 16-step view distance). | 5 |
| 1 | 8-lane multi-cycle SIMD core with mask, ballot, divergence stack | The same game on all 8 lanes, about 8 fps. The actual GPU. | 10 |
| 2 | VTRACE ray unit (hardware DDA) | About 35 fps at 160×120 | 12 |
| 3 | Stretch, in order (Stretch order, Tai tab) | Fog accumulator in VTRACE, two-level traversal, shadow rays for god rays, or a separate CPU and GPU | 15–21 |
| P | Pipelined core, built by an agent in parallel with VTRACE (D10) | 320×240 at about 20 fps | About 15 |

The game runs on the chip from Stage 0, so every later stage is a frame rate upgrade to a game that already works.

### The 60-second demo

Walk around generated terrain, break and place textured blocks, then point at the board and say "this is the whole computer." Show the resource report and the simulator vs hardware pixel match.

### Scope rules

- World 4,096 × 32 × 4,096 blocks, stored in DDR3 as chunks. The renderer only sees a 64 × 32 × 64 window in BRAM (D14). 16 block types.
- The renderer is the only GPU kernel. No side demos.
- Integer and fixed-point math only, everywhere on the chip.
- Stretch goals run in the order in the Stretch order section (Tai tab). Game-side extras (redstone, PS/2 keyboard, DOOM on an in-world screen) come after those, only if time is left.

## Decisions & Questions

### Decision log

| # | Date | Decision | Why | Owner | Acked |
| --- | --- | --- | --- | --- | --- |
| D1 | Nov 6 | Multi-cycle everywhere first (CPU, SIMD core, VTRACE v1). Pipeline only after Stage 1 matches the simulator. | Divergence and masking are the new hard problems. Debugging them next to hazards and forwarding doubles the bug surface. Multi-cycle also makes serialized loads and stalls trivial. | Tai | ☐ T ☐ K ☐ B |
| D2 | Nov 6 | The GPU programming model is custom RISC-V instructions called from C. No Vulkan layer. | Stock GCC works today. A Vulkan-shaped API is not buildable in 24 hours. | All | ☐ T ☐ K ☐ B |
| D3 | Nov 6 | Hardware divergence stack (DIF / DELSE / DENDIF) and a divergent-branch detector, both in Stage 1 | Per-lane `if` in C has to be safe. The detector turns silent wrong pixels into a loud error with a PC. | Tai | ☐ T ☐ K ☐ B |
| D4 | Nov 4 | Q16.16 fixed point in int32 everywhere | No FPU on the chip | Kennedy | ☐ T ☐ K ☐ B |
| D5 | Nov 6 | Compile with `rv32i_zmmul` (multiply, no divide) | MUL maps onto DSP slices. The kernel never divides. libgcc covers rare game-code division. | Bennett | ☐ T ☐ K ☐ B |
| D6 | Nov 6 | Stage 2 targets 160×120. 320×240 waits for pipelining. | Multi-cycle frame math in the GPU Core section (Tai tab) | Tai | ☐ T ☐ K ☐ B |
| D7 | Nov 6 | The core is one SystemVerilog design parameterized by `LANES`. Stage 0 is `LANES = 1`. | One codebase. Stage 1 starts as a parameter change, not a rewrite. | Tai | ☐ T ☐ K ☐ B |
| D8 | Nov 6 | No bootloader. The program is compiled into instruction and data memory with $readmemh, and program changes reach the board through updatemem. UART carries only key bytes and debug text. | Takes out the hardest failure to debug on the board, a chip that silently never boots. updatemem swaps memory contents into an existing bitstream in seconds, so program changes still skip a full Vivado build. | Tai | ☐ T ☐ K ☐ B |
| D9 | Nov 6 | Bennett owns the toolchain, the instruction simulator, the Verilator harness and make check. Kennedy iterates on plain C and the simulator, and reaches the board only through make board. | The bootloader and driver work is gone. The bench every stage is checked against is the most useful piece to own without deep RTL or renderer knowledge, and Kennedy never waits on a Vivado build. | All | ☐ T ☐ K ☐ B |
| D10 | Nov 6 | VTRACE and pipelining are built in parallel by two agent sessions, starting at hour 5 and hour 10. The VTRACE agent only touches vtrace.sv and its testbench, against the frozen port list. The pipelining agent only touches the core and treats VTRACE as a stall. Tai integrates both. | Pulls VTRACE to hour 12 and a pipelined core to about hour 15 without two edits colliding in the core's control logic. Each agent has its own check (fixed-ray testbench, trace match against the multi-cycle core). | Tai | ☐ T ☐ K ☐ B |
| D11 | Nov 6 | Build on Tai's existing RV32I core and credit it in the README as "inspired by" (answers Q1). | It is the Stage 0 baseline. Rewriting it would cost the hour 3 kernel frame. | Tai | ☐ T ☐ K ☐ B |
| D12 | Nov 6 | Tai owns VTRACE. The VTRACE agent writes the RTL and its testbench (D10) and Tai integrates it (answers Q3). | Bennett's column is the bench, and Kennedy's is the engine. VTRACE is RTL that plugs into Tai's core. | Tai | ☐ T ☐ K ☐ B |
| D13 | Nov 6 | The exact encodings and masking rules in Tai\_2 sections 1 and 2 are part of Interfaces v1.0. Divergence uses skip-on-empty jumps (answers Q6). | The opcode tables alone left mask-0, MMIO and illegal cases open, and the simulator and RTL have to agree on every one. | Tai | ☐ T ☐ K ☐ B |
| D14 | Nov 7 | DDR3 is the chunk store, built in Stage 0. Its 256 MB holds a 4,096 × 32 × 4,096 world as 65,536 chunks of 16 × 32 × 16 blocks, and the chunk engine is the only thing that touches it. The BRAM world becomes a 4 × 4-chunk window around the player. If the MIG controller isn't calibrating on the board by hour 6, chunks come from procedural generation through the same API. | Kennedy wants a big, persistent world. The renderer keeps 1-cycle BRAM reads, so DDR3 latency never reaches VTRACE, and the window plus chunk manager are needed for any big world anyway. | Tai | ☐ T ☐ K ☐ B |
| D15 | Nov 7 | Rendering is tile-based and image-order. The kernel walks the screen in 8 × 8-pixel tiles, and each pass of the 8 lanes shades a 4 × 2 block. The world is loaded in chunks (D14). No hardware cache. The renderer only ever reads the BRAM window, and the CPU decides what is in it. | Compact blocks send rays in similar directions, so lanes finish together and fewer sit idle. Ray tracing needs no rasterizer and no depth buffer, and the chunk window keeps DDR3 latency away from VTRACE. | Tai | ☐ T ☐ K ☐ B |

### What changed from Kenny's Nov 4 plan

So nobody has to diff it by hand.

- Everything starts multi-cycle (D1). Frame rate estimates redone for that.
- Added **MASKALL** (mask = 0xFF with no operand). Setting a mask from a register breaks when lane 0 is inactive.
- Added the divergence stack and the divergent-branch detector (D3).
- New rule. BALLOT and MASKGET write their result into every lane, even inactive ones.
- New rule. Instructions that need one value (branches, JALR, MASKSET, VTRACE step count) read it from the lowest active lane, or lane 0 if no lane is active.
- VGET t-at-hit is now Q16.16 (was Q8.10) so it matches everything else.
- No bootloader (D8). Reset starts at 0x0000 and the program is part of the bitstream.
- Back framebuffer is readable, for the pixel-match proof.
- New MMIO registers for errors, cycle counter and framebuffer mode.
- Key byte format and UART protocols are written down.
- VTRACE v1 does one step every 2 cycles. One step per cycle is a later upgrade.

### Open questions

| # | Question | Owner | Needed by | Answer |
| --- | --- | --- | --- | --- |
| Q1 | Can we build on Tai's existing RV32I core? Email hello@hackutd.co or ask on Discord. If yes, make the repo public and credit it in the README. | Tai | Fri noon | Yes. Use it and credit it in the README as "inspired by" (D11). |
| Q2 | Is the Pmod VGA arriving by Saturday? If not, build the resistor-ladder VGA. | Tai | Fri evening |  |
| Q3 | Who owns VTRACE RTL? With the bootloader and driver gone, Bennett's column is the toolchain, simulator and Verilator harness (D9), plus the VTRACE testbench. Options for the RTL are Tai after Stage 1, or cut it to stretch. | All | Fri night | Tai. The VTRACE agent writes the RTL and testbench, Tai integrates (D10, D12). |
| Q4 | Who writes the instruction simulator? Kennedy needs it first to run the kernel. Proposed · Bennett (D9). | All | Fri night | Bennett (D9). |
| Q5 | Clocks. Proposal is 50 MHz core, 25 MHz pixel. Does the HDMI converter accept 25.0 MHz for 640×480? | Tai | Fri night |  |
| Q6 | Divergence v1. Skip-on-empty jumps in DIF/DELSE, or plain predication only? | Tai + Bennett | Fri night | Skip-on-empty jumps, specified in Tai\_2 section 2 (D13). |
| Q7 | Are all three of us accepted and RSVP'd in Harp? | Kennedy | Fri noon |  |

### Change requests to frozen interfaces

| # | Date | Requested by | Change | Reason | T | K | B |
| --- | --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |  |  |

## Stages

**Owner · All · Status · Draft**

Who builds what in each stage, and what each person needs from the others before they can start. Every row in the handoff table is a promise. The person in the From column delivers it, and the work in the Unblocks column waits until they do.

The split is built so nobody waits on the board. The one-lane game needs only plain C and the toolchain, so the simulator is off the critical path until Stage 1. Two agent sessions build VTRACE and the pipelined core in parallel (D10), and Tai integrates both.

### Milestones

| Hour | Milestone | Frame rate (160×120) |
| --- | --- | --- |
| 3 | First kernel frame on the board |  |
| 5 | The whole game playable on one lane, streaming chunks from DDR3 | 1 to 3 fps (flat colors, 16-step view distance) |
| 10 | The same game on 8 lanes | About 8 fps |
| 12 | VTRACE integrated | About 35 fps |
| About 15 | Pipelined core with VTRACE | Enough headroom for 320×240 at about 20 fps |
| 15 to 21 | Stretch window |  |
| 21 | Freeze |  |

### Handoffs

Sorted by when they're needed. If a row is late, the people in the Unblocks column switch to their next row that isn't blocked and say so in the Decisions section (Shared tab).

| Deliverable | From | Unblocks | Needed by |
| --- | --- | --- | --- |
| Interfaces v1.0 (opcodes, memory map, MMIO, key byte, VTRACE ports) | All | Everything below | Fri night |
| Top module ports | Tai | Bennett's Verilator harness | Hour 1 |
| GCC, kc.ld, crt0, ELF-to-hex script, make board | Bennett | The first kernel frame on the board | Hour 2 |
| Plain C renderer building for the chip | Kennedy | The first kernel frame on the board | Hour 2 |
| Game loop building for the chip | Kennedy | The game on the board at hour 5 | Hour 4 |
| Textures, palette and 1/x table as hex files | Kennedy | Tai's BRAM initialization | Hour 4 |
| Chunk engine, DDR3 and chunk registers in the simulator | Bennett | Kennedy's chunk manager on the simulator | Hour 4 |
| DDR3 chunk store calibrated and passing its board test | Tai (DDR3 agent, P2b) | Chunk manager on the chip | Hour 5 (cut at hour 6) |
| Simulator with every custom instruction | Bennett | Tai's Stage 1 ladder. Kennedy's 8-lane kernel. | Hour 5 |
| VTRACE port list confirmed | Tai | The VTRACE agent | Fri night (Interfaces v1.0) |
| C reference for one ray | Kennedy | The VTRACE agent's testbench | Hour 6 |
| make vl and tracediff.py | Bennett | Debugging Stage 1 without the board | Hour 6 |
| Stage 1 green on the board | Tai | VTRACE integration. The pipelining agent. | Hour 10 |
| VTRACE in the simulator | Bennett | Kennedy's VTRACE kernel | Hour 11 |
| Pipelined core matching the multi-cycle trace | Pipelining agent and Bennett | Tai's integration | Hour 14 |

### Still open

- **AI-written code.** HackUTD's rule on it, since two agents are on the critical path.
- **Build time.** Time a Vivado build of the existing core with a VGA test pattern on the laptop we're bringing.

* **DDR3 calibration.** Untested on our board. If it isn't passing by hour 6, chunks come from procedural generation (D14).

## Interfaces

**Status · Draft v0.1, becomes Frozen v1.0 Friday night.** Changes after the freeze go through the Decisions section (Shared tab). The exact encodings and masking rules are in Tai\_2 sections 1 and 2, which are part of v1.0 (D13).

### Execution model

- One instruction stream, 8 lanes, each with its own 32 registers (x0 is always 0).
- One shared PC, one shared 8-bit **active mask**, one shared divergence stack.
- Reset state. PC = 0x0000\_0000 (\_start in crt0), mask = 0x01.
- **Per-lane writes.** Normal instructions (ALU, loads, LUI, AUIPC, link register of JAL/JALR, LANEID, VTRACE, VGET) write rd only in active lanes.
- **Uniform writes.** BALLOT and MASKGET write rd in every lane, active or not.
- **Scalar lane.** When an instruction needs a single value (branch compare, JALR target, MASKSET, VTRACE step count) it reads the lowest active lane. If the mask is 0 it reads lane 0.
- **Uniform branches.** BEQ/BNE/BLT/BGE/BLTU/BGEU and JALR must agree across all active lanes. If they don't, hardware sets `ERR.DIVERGE`, latches the PC into `ERR_PC`, and halts. The simulator does the same and prints every lane's operands.
- Divergent control flow goes through the divergence stack (if/else) or LMASK + BALLOT (loops).
- **Loads and stores** use each lane's own address and are serialized across active lanes in order 0 → 7. If several lanes store to one address, the highest lane wins.
- Game logic runs with mask = 0x01.

### Lane control · opcode custom-0 (0x0B), R-type, funct7 = 0

| Instruction | funct3 | Effect | rd written in |
| --- | --- | --- | --- |
| LANEID rd | 000 | rd = this lane's index, 0–7 | Active lanes |
| LMASK rs1 | 001 | Each lane where rs1 = 0 becomes inactive (mask &= rs1 ≠ 0) | none |
| BALLOT rd, rs1 | 011 | rd = bitmask of active lanes where rs1 ≠ 0 | **All lanes** |
| MASKGET rd | 101 | rd = current mask | **All lanes** |
| MASKSET rs1 | 110 | mask = low 8 bits of rs1 from the scalar lane | none |
| MASKALL | 111 | mask = 0xFF | none |

funct3 010 and 100 are reserved.

### Divergence · opcode custom-2 (0x5B)

| Instruction | Format | funct3 | Effect |
| --- | --- | --- | --- |
| DIF rs1, label | B | 000 | Push {saved = mask, else = mask & (rs1 = 0)}. Then mask &= (rs1 ≠ 0). If the new mask is 0, jump to label. |
| DELSE label | B (rs1 = rs2 = x0) | 001 | mask = top.else. If that is 0, jump to label. |
| DENDIF | R (all fields 0) | 010 | mask = top.saved, pop. |

Stack depth 8. Overflow or underflow sets `ERR.DIVSTACK` and halts. The jump target of DIF is the DELSE instruction (or DENDIF if there's no else). The jump target of DELSE is the DENDIF. The GPU Core section (Tai tab) has a walkthrough, and Tai\_2 section 2 has the exact pseudocode.

### Ray unit · opcode custom-1 (0x2B), R-type · Stage 2

| Instruction | funct3 | funct7 | Effect |
| --- | --- | --- | --- |
| VSET rs1 | 000 | field 0–7 | Load one field of each active lane's ray state |
| VTRACE rd, rs1 | 001 | 0 | Step every active lane's ray up to rs1 (scalar) steps until it hits a solid block or leaves the world. Stalls until all lanes finish. |
| VGET rd | 010 | field 0–1 | Read back a result field |

VSET fields

| Field | Contents |
| --- | --- |
| 0 | Start cell, packed. x in bits 5:0, y in 10:6, z in 16:11 |
| 1–3 | tMax x, y, z (Q16.16) |
| 4–6 | tDelta x, y, z (Q16.16) |
| 7 | Step signs. Bit 0 x, bit 1 y, bit 2 z. 1 = stepping negative. |

VTRACE result (rd, low 16 bits)

| Bits | Meaning |
| --- | --- |
| 0 | Hit |
| 2:1 | Face axis (0 x, 1 y, 2 z) |
| 3 | Face sign (1 = the ray was stepping negative on that axis) |
| 7:4 | Block type |
| 15:8 | Steps taken |

**VGET fields** · 0 hit cell (packed like VSET field 0) · 1 t at hit (Q16.16)

The start cell itself is never tested. A ray that leaves the world returns hit = 0.

### Memory map

| Address | Region | Access |
| --- | --- | --- |
| 0x0000\_0000 | Instruction memory, 32 KB. Contents come from kc\_imem.hex at build time (D8). | Fetch only |
| 0x1000\_0000 | Data memory, 32 KB | Read / write |
| 0x2000\_0000 | World window, one byte per block, index = (y × 64 + z) × 64 + x in window-relative coordinates. Low 4 bits = type. Hardware adds WIN\_ORIGIN before the BRAM, and reads in an invalid slot return 0 (D14). | Write updates all four copies. Reads come from copy 0. |
| 0x3000\_0000 | Textures, one byte per texel | Read / write |
| 0x4000\_0000 | Back framebuffer, one byte per pixel, stride always 320 | Read / write |
| 0x5000\_0000 | MMIO (table below) | Read / write |
| 0x6000\_0000 | Output palette, 256 entries of RGB444 | Write |
| Not mapped | DDR3, 256 MB, chunks only (D14) | Only through the chunk engine (MMIO 0x2C to 0x3C) |

Data memory layout

| Address | Contents |
| --- | --- |
| 0x1000\_0000 | Camera block (48 bytes, below) |
| 0x1000\_0030 | Reserved shared state up to 0x1000\_00FF |
| 0x1000\_0100 | .data, .rodata, .bss (1/x table lives in .rodata, the 8 KB arena in .bss) |
| 0x1000\_6000 – 0x1000\_7FFF | Lane stacks, 1 KB each. Lane n's stack top = 0x1000\_8000 − n × 1024. |

**Camera block** (Q16.16, all int32)

```c
struct camera {
    int32_t origin[3];
    int32_t forward[3];
    int32_t right_step[3];
    int32_t up_step[3];
};  // at 0x10000000
```

MMIO at 0x5000\_0000

| Offset | Name | Access | Meaning |
| --- | --- | --- | --- |
| 0x00 | FB\_SWAP | W / R | Write 1 to request a swap at the next vsync. Reads 1 while the swap is still pending. |
| 0x04 | FRAME\_COUNT | R | Increments every vsync |
| 0x08 | VSYNC | R | 1 during vertical blank |
| 0x0C | CYCLES | R | Free-running core cycle counter (for profiling) |
| 0x10 | UART\_RX | R | Next byte from the RX FIFO |
| 0x14 | UART\_STATUS | R | Bit 0 RX byte available · bit 1 TX busy |
| 0x18 | UART\_TX | W | Send one byte |
| 0x1C | ERR | R, write 1 to clear | Bit 0 DIVERGE · bit 1 DIVSTACK · bit 2 ILLEGAL instruction |
| 0x20 | ERR\_PC | R | PC of the instruction that raised the error |
| 0x24 | LEDS | W | Board LEDs |
| 0x28 | FB\_MODE | R / W | 0 = 320×240 · 1 = 160×120 (top-left quadrant, scaled ×4) |
| 0x2C | DDR\_STATUS | R | Bit 0 DDR3 calibrated · bit 1 chunk engine busy · bit 2 command queue full |
| 0x30 | CHUNK\_CMD | W | Queue one chunk copy (format under Chunks below). A write while the queue is full stalls until there is room. |
| 0x34 | CHUNK\_DONE | R | Count of finished chunk commands, wraps at 2³² |
| 0x38 | SLOT\_VALID | R / W | Bit s = slot s holds a loaded chunk, s = sz × 4 + sx. Reads in an invalid slot return air. |
| 0x3C | WIN\_ORIGIN | R / W | Window corner mod 64. Bits 5:0 x, bits 13:8 z. Always a multiple of 16. |

### Chunks (D14)

- A chunk is 16 × 32 × 16 blocks (the full world height) at 4 bits per block, so 4 KB. Blocks are stored y-major, then z, then x, the same order as the BRAM address.
- DDR3 holds 256 × 256 chunks, a 4,096 × 32 × 4,096 world. Chunk (cx, cz) lives at DDR3 address (cz × 256 + cx) × 4,096.
- The BRAM world is a window of 4 × 4 chunk slots. Chunk (cx, cz) always goes in slot (cx mod 4, cz mod 4), so the window is a ring buffer and nothing ever shifts.
- The CPU and VTRACE use window-relative coordinates (x and z from 0 to 63). Hardware adds WIN\_ORIGIN mod 64 before the BRAM. Reads in a slot whose SLOT\_VALID bit is 0 return air.
- DDR3 is not in the CPU memory map. The chunk engine is the only path to it. Game code reaches it through chunks.h (Kenny tab, Chunk API). There is no hardware cache. The CPU decides what is in the window, and the renderer never waits on DDR3 (D15).

CHUNK\_CMD format

| Bits | Field |
| --- | --- |
| 31 | Operation. 0 = load DDR3 chunk into its slot, 1 = store its slot back to DDR3 |
| 15:8 | Chunk z (0 to 255) |
| 7:0 | Chunk x (0 to 255) |

The slot always comes from the chunk coordinates (mod 4), so the command never names it.

### Pixel byte

| Bits | Meaning |
| --- | --- |
| 7:4 | Texel color index |
| 3:2 | Face shade |
| 1:0 | Fog level |

The palette maps every byte to an RGB444 color (bits 11:8 red, 7:4 green, 3:0 blue), so shading and fog cost nothing in the kernel.

### Key byte (laptop → board)

Bit 7 = 1 for key down, 0 for key up. Bits 6:0 = key code.

| Key | Code | Action |
| --- | --- | --- |
| W A S D | 0x77 0x61 0x73 0x64 | Move |
| Space | 0x20 | Jump |
| Arrows ← → ↑ ↓ | 0x10 0x11 0x12 0x13 | Look |
| J | 0x6A | Break block |
| K | 0x6B | Place block |
| 1–9 | 0x31–0x39 | Select block type |

### UART protocols

1 Mbaud, 8N1. All multi-byte values little-endian. `sum8` is the sum of the listed bytes mod 256.

Bootloader commands (retired by D8, kept only in case a bootloader comes back as a stretch goal)

| Command | Host sends | Board replies |
| --- | --- | --- |
| Ping | `P` | `K` |
| Load | `L`, addr (4), len (4, max 4096), data (len), sum8(data) | `K` ok, `E` bad checksum |
| Jump | `J`, addr (4) | `K`, then jumps |

Since D8, UART carries key bytes from the laptop and debug text from UART\_TX back to it. The world is generated on the chip at startup, or baked in with $readmemh like the program.

**Fallback packets** (retired, the game runs on the chip from hour 5)

A5, opcode, len (1), payload, sum8(opcode, len, payload)

| Opcode | Payload |
| --- | --- |
| 0x01 | Camera block, 48 bytes |
| 0x02 | Block edit · x, y, z, type (4 bytes) |

### VTRACE module ports

See the VTRACE section (Tai tab). The port list there is part of this freeze.

## Verification

**Owner · All · Status · Draft**

The instruction simulator is the contract. Hardware is correct when it matches the simulator, and the simulator is correct when it matches Kennedy's plain C renderer.

### Per-instruction tests

Each is a tiny program with a known answer stored to data memory, run on the simulator and in Verilator before anyone builds on that instruction.

| Test | Checks | Expected |
| --- | --- | --- |
| t\_laneid | Each lane stores LANEID to dmem\[lane\] | 0, 1, …, 7 |
| t\_mask | LMASK on lane & 1, then every lane stores | Only even lanes' slots change |
| t\_ballot | BALLOT(lane & 1) under mask 0x0F | 0x0A in every lane, including inactive ones |
| t\_maskgetset | MASKGET / MASKSET round trip, MASKALL | Original mask restored |
| t\_lsu\_order | All lanes store their LANEID to one address | 7 |
| t\_branch\_uniform | Uniform branch passes. Divergent branch halts. | ERR.DIVERGE set, ERR\_PC correct |
| t\_divstack | Nested if/else 2 deep, MASKGET stored at each point | Masks match the walkthrough table |
| t\_divskip | All-false and all-true conditions | DIF and DELSE jumps taken |
| t\_zmmul | MUL, MULH, MULHSU, MULHU on edge values | Known products |
| t\_uart | Echo bytes | Same bytes back |
| t\_fbswap | Draw, swap, poll | FB\_SWAP reads 0 after vsync |
| t\_vtrace | Fixed rays in a fixed world | Matches the C reference |
| t\_mask\_zero | Mask loop where the last lane drops out | Loop exits, BALLOT wrote 0 in every lane |
| t\_mmio\_lanes | UART\_RX read under mask 0x03 | Two bytes popped, in lane order |
| t\_jalr\_uniform | JALR with lane-dependent targets | ERR.DIVERGE set, ERR\_PC correct |
| t\_div\_nested\_lmask | LMASK inside a then-body | DENDIF restores the mask from before DIF |
| t\_divstack\_overflow | Nine nested DIFs | ERR.DIVSTACK set |
| t\_illegal | DIV, ECALL, a CSR read, a misaligned LW, VGET field 2 | Each sets ERR.ILLEGAL |
| t\_chunk\_roundtrip | Fill a slot, store it, clear it, load it back | Every block matches, CHUNK\_DONE advanced by 2 |
| t\_slot\_valid | Load and VTRACE into a slot with its valid bit cleared | Reads return air, rays pass through |
| t\_ring | Move WIN\_ORIGIN by one chunk, read the same absolute block | Same value before and after |

### Regression

`make check` runs every t\_ test and the golden camera shots on plain C, the simulator and Verilator, and diffs the traces. It has to be green before a Vivado build or a make board.

### Definition of done per stage

| Stage | Done when |
| --- | --- |
| 0 | Kernel frame on the board by hour 3, and the game plays on one lane by hour 5 |
| 1 | Same, with `LANES = 8`, all tests green |
| 2 | Same, with VTRACE, frame rate measured with CYCLES |
| 3 | The stretch passes make check and the game plays for 5 minutes with no error LED |

## Schedule, Roles & Risks

### Roles

| Tai · GPU/CPU hardware | Bennett · toolchain, simulator, Verilator | Kennedy · engine, game, look |
| --- | --- | --- |
| Clocking, VGA, framebuffers, palette, swap, DDR3 chunk store (D14) | GCC, gpu.h, linker script, crt0, make | Plain C reference renderer (PNG) |
| Stage 0 additions (Zmmul, MMIO, UART, $readmemh memories) | Instruction simulator | Render kernel, software DDA then VTRACE |
| `LANES` parameterization and Stage 1 ladder | Verilator harness, tracediff, make check, updatemem flow, key forwarder | Game (terrain, chunk manager, physics, picking, editing) |
| World × 4, memory map wiring | Per-instruction tests, golden-frame regression | Textures, palette, 1/x table |
| VTRACE RTL through the VTRACE agent, then integration (D12) | VTRACE simulator model and Verilator testbench | Devpost, demo video, pitch |
| Vivado builds, timing, resource report |  |  |

### Hour by hour

| Hours | Tai | Bennett | Kennedy |
| --- | --- | --- | --- |
| 0–3 | VGA, framebuffer, palette, Zmmul, UART, MMIO, hex-initialized memories, first build. Start the DDR3 agent (P2b) at hour 0. | GCC, kc.ld, crt0, ELF-to-hex script, make board | Plain C renderer, game loop and chunk manager, with the same files building for laptop and chip |
| 3–5 | Kernel frame at hour 3, then the game on the board with Kennedy (keys, swap timing). Merge the DDR3 chunk store by hour 5. | Simulator with RV32I, every custom instruction and the chunk engine, Verilator harness on Tai's RTL | Game on the board by hour 5 |
| 5–10 | Stage 1 ladder to 8 lanes. Starts the VTRACE agent at hour 5 against the frozen port list. | Custom instructions in the simulator by hour 5 (hard deadline). Then per-instruction tests, tracediff, make check. | 8-lane kernel on the simulator, textures. C reference for one ray by hour 6. |
| 10–12 | Integrate VTRACE into the multi-cycle core. Start the pipelining agent at hour 10. | VTRACE model in the simulator, regression on every RTL change | VTRACE path in the kernel |
| 12–15 | Review and integrate the pipelined core, with VTRACE as a stall | tracediff of the pipelined core against the multi-cycle core | Game polish, hotbar, crosshair |
| 15–21 | Stretches in order (Stretch order, Tai tab), resource report | Regression on every stretch build, backup video | Devpost, video, pitch |
| 21–24 | Freeze at hour 21, flash, rehearse | Freeze, rehearse | Pitch, rehearse |

**Checkpoints.** Toolchain and the first kernel frame by hour 3. Game on the chip and custom instructions in the simulator by hour 5. SIMD frame on the board by hour 10. VTRACE by hour 12. Pipelined core by about hour 15. Freeze at hour 21.

If there's no SIMD frame at hour 10, demo the one-lane game and keep fixing SIMD behind it. Take one staggered nap each, ideally during long Vivado builds.

### Before Saturday

**Rules**

- [x] Q1 answered
- [ ] Q7 answered

**Buy**

- [ ] Digilent Pmod VGA
- [ ] VGA-to-HDMI converter (USB-powered, accepts 640×480 at 60 Hz) plus cable
- [ ] Multi-port USB charger or powered hub
- [ ] Backup VGA breakout and resistors
- [ ] Optional PS/2 keyboard and PS/2 Pmod

**Install and test**

- [ ] Vivado + Arty board files, Verilator, RISC-V GCC, SDL3, Python + pyserial
- [ ] Display chain shows the existing output on the portable monitor
- [ ] Arty USB-UART works at 1 Mbaud
- [ ] updatemem patches new memory contents into a bitstream of the existing core (Tai and Bennett)
- [ ] Verilator builds the existing core and runs one test program (Bennett)

**Agree Friday night, then freeze**

- [ ] Interfaces section (Shared tab) v1.0
- [ ] D1–D13 acked
- [ ] Q2 and Q5 answered

**Read (no code)**

- [ ] HackMIT GPU writeup (all three)
- [ ] Amanatides & Woo, "A Fast Voxel Traversal Algorithm for Ray Tracing" (Tai and Kennedy)
- [ ] RISC-V unprivileged spec, RV32I, Zmmul and the custom opcode space (Bennett)

### Risks and fallbacks

At any hour the question is "what's the best stage that works right now," never "do we have a demo."

| Risk | Early sign | Fallback |
| --- | --- | --- |
| A judge questions the reused core | Questions at judging | Point to the "inspired by" credit (D11) and the weekend's commit history |
| Pmod VGA doesn't arrive | No tracking by Thursday night | Resistor-ladder VGA |
| SIMD core not working by hour 10 | Trace mismatches piling up | Demo the one-lane game |
| Divergence or masking bugs | DIVERGE errors or wrong pixels on the simulator | Debug one 8-pixel group with a trace. Replace GPU\_IF with `sel()`. |
| Multi-cycle too slow | Under 5 fps on the simulator's cycle estimate | Drop textures to flat colors, cap ray steps lower, shrink the view |
| VTRACE late or broken | Fails its own testbench by hour 11 | Ship software DDA at 160×120 |
| Four world copies don't fit or close timing | Over 135 BRAM or negative slack | Two copies, or a 32³ world |
| Vivado builds eat the night | More than 2 builds an hour | Debug in Verilator only. Program changes go through updatemem, not rebuilds. |
| Game on the chip runs late | Not playable by hour 5 | Show the kernel with a scripted camera path while Kennedy finishes the game. Stage 1 still goes ahead. |
| Bennett's column is too big | Toolchain not done by hour 3 | Kennedy takes the simulator. Bennett keeps the toolchain and Verilator. |
| Demo fumble at judging |  | Board flashed and running before judges arrive, backup video ready |
| DDR3 won't calibrate | Standalone test not passing by hour 6 | Cut it. The chunk manager generates chunks procedurally through the same API, and DDR3 moves to the Next slide. |

**Cut order when behind.** Stage 3 stretch → pipelining → PS/2 standalone → VTRACE → textures (flat colors) → 8 lanes. The one-lane game at 160×120 is the floor.
