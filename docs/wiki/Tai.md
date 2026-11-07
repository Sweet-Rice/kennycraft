# Tai

GPU/CPU hardware. Owner · Tai.

## My stages

| Stage | Builds | Done when | Needs first |
| --- | --- | --- | --- |
| Stage 0 · one lane, the whole game | VGA, framebuffer, palette, Zmmul, UART RX FIFO and TX, MMIO, address decoder, hex-initialized memories, reset at 0x0000. From hour 3, brings the game up on the board with Kennedy (keys, swap timing). Runs the DDR3 agent (P2b) from hour 0 and merges the chunk store by hour 5 (D14). | A kernel frame on the board by hour 3. The game plays by hour 5, loading chunks from DDR3. | Interfaces v1.0. Bennett's hex images by hour 2. A VGA test pattern and constraints file ready before the event (D11). |
| Stage 1 · eight lanes | LANES = 8. Register files, active mask, lane-control instructions, lane-serial LSU, uniform-branch detector, divergence stack (Tai\_2 section 2). Bring-up ladder in the GPU Core section (Tai tab). Starts the VTRACE agent at hour 5. | The same game on 8 lanes at about 8 fps, every per-instruction test green in Verilator. | Custom instructions in the simulator by hour 5. VTRACE port list frozen by hour 5. |
| Stage 2 · VTRACE | Integrates the VTRACE agent's module into the multi-cycle core, world × 4. Starts the pipelining agent at hour 10. | t\_vtrace green on the board, about 35 fps measured with CYCLES. | Stage 1 green. The VTRACE module passing its own testbench. |
| Pipelined core | Reviews and integrates the pipelining agent's core, with VTRACE as one more stall. | The pipelined core runs the game on the board at 320×240, about 20 fps. | Stage 2 done. The agent's core matching the multi-cycle trace. |
| Stage 3 · stretch | Stretches in the order below. | Each stretch passes make check on the board, or it is reverted before hour 21. | Pipelined core in, or skipped. |

## Agent workstreams (D10)

|  | VTRACE agent | Pipelining agent |
| --- | --- | --- |
| Runs | Hour 5 to about 11 | Hour 10 to about 14 |
| Touches only | vtrace.sv and its testbench | The core's pipeline stages, forwarding and stall logic |
| Correctness check | Fixed rays against Kennedy's C reference | Retired-instruction trace matches the multi-cycle core exactly |
| Interface | The frozen VTRACE port list (start, busy, done, per-lane ray state in, results out) | Treats VTRACE as one more multi-cycle instruction that stalls until done |

- Tai does all integration. Neither agent edits the other's files.
- The pipelining agent can drive Vivado through an MCP to iterate on timing reports. Forwarding across 8 lanes is where timing will be hardest.
- Tai reads what each agent writes closely enough to explain it to a judge.

## Stretch order

1. **Fog accumulator in VTRACE.** Each step adds the cell's fog density to an accumulator that comes back with the hit. About an hour of RTL, and it gives volumetric fog.
2. **Two-level traversal.** A coarse occupancy grid (one bit per 8×8×8 chunk) lets rays skip whole empty chunks in one step. This is the voxel version of a hardware acceleration structure.
3. **Shadow rays for god rays.** At each fog sample, a ray toward the sun decides whether that point is lit. Worth it only if 1 and 2 leave enough frame rate.
4. **Separate CPU and GPU.** Two core instances, a doorbell register the CPU writes to launch the GPU, GPU priority on shared memory, a double-buffered camera block, and block edits queued until the GPU is idle. Pick this over 2 and 3 if the pitch story matters more than the visuals.

**Why not a BVH.** The voxel grid is already an acceleration structure, and DDA through it is close to optimal. A BVH over voxels would be slower per ray and would need rebuilding on every block edit. Two-level traversal gets the same empty-space skipping without either cost.

## CPU Core

**Owner · Tai · Status · Exists (multi-cycle RV32I), needs Stage 0 additions**

This is the Stage 0 baseline and the control path the GPU inherits. Per D7, it is the same RTL as the GPU with `LANES = 1`.

### What exists today

Multi-cycle RV32I with an FSM-driven datapath, verified across the base ISA.

- Tai · link the repo here, credited in the README as "inspired by" (D11)
- Tai · fill in test count, LUTs, Fmax from the last build
- Tai · confirm LB/LBU/LH/LHU/SB/SH work (the world, textures and framebuffer are all byte-addressed)

### State machine

Planning numbers. Tai replaces them with the real ones, and we re-measure with the CYCLES register.

| State | Does | Cycles |
| --- | --- | --- |
| FETCH | Send PC to instruction BRAM | 1 |
| DECODE | Instruction arrives, decode, read registers | 1 |
| EXECUTE | ALU, branch compare, address generation, multiply | 1 (2 for MUL) |
| MEM | Load or store through the LSU | 2+ |
| WRITEBACK | Write rd, update PC | 1 |

| Instruction class | Planning CPI |
| --- | --- |
| ALU, LUI, AUIPC | 4 |
| Branch, JAL, JALR | 4 |
| MUL family | 5 |
| Load | 5 |
| Store | 4 |
| Custom lane-control | 4 |

### Stage 0 additions

- [ ] **Zmmul.** MUL, MULH, MULHSU, MULHU on DSP48E1 slices (about 4 per 32×32 multiplier). Register the output, so MUL takes one extra EXECUTE cycle.
- [ ] DIV/DIVU/REM/REMU decode as illegal (raises ERR.ILLEGAL). The compiler never emits them with `rv32i_zmmul`.
- [ ] **Address decoder** on address bits 31:28, per the memory map.
- [ ] **Instruction memory** as BRAM initialized with $readmemh from kc\_imem.hex. Data memory gets kc\_dmem.hex the same way (.rodata and .data, including the 1/x table).
- [ ] **Reset vector** 0x0000\_0000, straight into \_start.
- [ ] **UART** at 1 Mbaud. 50 MHz gives exactly 50 clocks per bit. Add a 16-byte RX FIFO so key presses aren't dropped while a frame renders.
- [ ] **MMIO block** with the registers from the Interfaces section (Shared tab).
- [ ] **Error halt.** An illegal instruction or misaligned access (Tai\_2 section 1) sets ERR.ILLEGAL, latches ERR\_PC, stops the FSM and lights an LED.
- [ ] **CYCLES counter**, free-running.
- [ ] Fast rebuild. Run write\_mem\_info once on the implemented design so updatemem can patch new kc\_imem.hex and kc\_dmem.hex into the last bitstream in seconds (Toolchain section (Bennett tab)).

### Clocking

| Clock | Source | Used by |
| --- | --- | --- |
| 100 MHz | Board oscillator | MMCM input |
| 50 MHz | MMCM | Core, memories (port A), UART, VTRACE |
| 25 MHz | MMCM | VGA timing, framebuffer port B, palette |
| 166.67 MHz | Second MMCM (rtl/ddr/ddr\_clk.sv) | MIG system clock |
| 200 MHz | Second MMCM | MIG reference clock (input delay calibration) |
| About 81 MHz | MIG user clock output | DDR3 side of the chunk engine. Crosses to 50 MHz through async FIFOs. |

Framebuffers are dual-clock BRAM, which handles the crossing for pixel data. FB\_SWAP, VSYNC and FRAME\_COUNT cross with two-flop synchronizers.

### Module hierarchy

```
top
├── clk_gen          MMCM, 50 MHz core, 25 MHz pixel
├── core #(LANES)    CPU when LANES = 1, GPU when LANES = 8
│   ├── control_fsm  shared PC, decode, mask, divergence stack
│   ├── lane[LANES]  regfile, ALU, multiplier, branch compare
│   └── lsu          serializes memory ops across active lanes
├── imem             32 KB, from kc_imem.hex
├── dmem             32 KB
├── world_remap      window origin and slot-valid, between core/VTRACE and world_mem
├── world_mem        4 copies, 4-bit wide, the 64 x 32 x 64 window
├── chunk_engine      DDR3 <-> window slot copies, MMIO 0x2C to 0x3C
│   ├── ddr_clk      MMCM, 166.67 MHz and 200 MHz for MIG
│   └── mig_ddr3     Xilinx MIG, 256 MB DDR3L
├── tex_mem, palette
├── framebuffer ×2, vga_timing, vga_out
├── uart             RX FIFO, TX
├── mmio
└── vtrace           Stage 2
```

### Pipelining plan (later)

Entry criteria. Stage 1 renders pixel-exact against the simulator and make check is green. The pipelining agent starts at hour 10 (D10, prompt P8 in Tai\_2). If its core doesn't match the multi-cycle trace by hour 14, pipelining becomes the "Next" slide in the pitch.

| Topic | Plan |
| --- | --- |
| Stages | Classic 5-stage IF / ID / EX / MEM / WB |
| Data hazards | Forward EX → EX and MEM → EX. Stall 1 cycle on load-use. |
| Branches | Resolve in EX, flush 2. Predict not-taken. |
| MUL | 2-cycle, stall the pipe |
| Serialized LSU | Stalls the whole pipe for (active lanes + 1) cycles |
| Mask changes | Treat LMASK, MASKSET, MASKALL, DIF, DELSE and DENDIF like taken branches and flush behind them. Simple and correct. |
| Expected gain | CPI from about 4 to about 1.3, roughly 3× frame rate |

## GPU Core

**Owner · Tai · Status · Draft**

### What changes from the CPU

| Shared (one copy) | Replicated (× 8 lanes) | New |
| --- | --- | --- |
| PC, fetch, decode | Register file (32 × 32-bit) | Active mask |
| Control FSM | ALU | Divergence stack |
| Divergence stack | Multiplier | BALLOT reduction |
| LSU sequencer | Branch comparator | Uniform-branch detector |
|  | Address generator | Lane-serial LSU |

```
            ┌──────────── shared control ────────────┐
   imem ──► │ PC → fetch → decode → FSM │ mask │ div │
            └───────────────┬────────────────────────┘
                            │ same instruction, every lane
      ┌──────┬──────┬───────┼──────┬──────┬──────┬──────┐
     lane0 lane1  lane2   lane3  lane4  lane5  lane6  lane7
     regs   regs   regs   regs   regs   regs   regs   regs
     ALU    ALU    ALU    ALU    ALU    ALU    ALU    ALU
      └──────┴──────┴───────┼──────┴──────┴──────┴──────┘
                            ▼
                 LSU (one lane at a time) ──► memory map
```

### Register files

- 8 × (32 × 32-bit), 2 read ports, 1 write port, in LUT RAM (distributed RAM), not BRAM.
- Write enable for lane n = `wb_en & (mask[n] | uniform_write) & (rd != 0)`.
- Check LUT usage in the first Stage 1 utilization report and record it in the Actual utilization table (Memory & Display section).

### SIMD state machine

| State | Does |
| --- | --- |
| FETCH | Same as CPU |
| DECODE | Decode once, read all 8 register files in parallel |
| EXECUTE | 8 ALUs in parallel. For branches, 8 comparators feed the uniform check. Mask and divergence instructions update the mask here. |
| MEM | LSU walks the set bits of the mask, one lane at a time |
| WRITEBACK | All active lanes (or all lanes for uniform writes) write rd |

### Lane-serial LSU

- A priority encoder picks the next active lane.
- Issue lane n's address while lane n−1's load data comes back, so N active lanes take about N + 1 cycles.
- Loaded values land in a per-lane result register and are written back together in WRITEBACK.
- A store to the world region writes the same address in all four world copies.
- World ports are owned by the core except while VTRACE is busy (the core is stalled then anyway).

### Divergence

Three mechanisms, from cheapest to most general.

**1 · Uniform branches with a detector (always on).** Ordinary RISC-V branches are fine as long as every active lane agrees, which covers loops over pixel groups, function calls and anything driven by BALLOT. If lanes disagree, hardware halts with ERR.DIVERGE and the PC. This is the safety net that catches compiler-generated per-lane branches.

**2 · Divergence stack for if/else.**

Stack entry = {saved mask (8 bits), else mask (8 bits)}. 8 entries, 3-bit pointer plus overflow detection.

Walkthrough. Mask starts at 0xFF, and the condition is true on lanes 0, 1 and 4.

| Instruction | Stack top | Mask after | Notes |
| --- | --- | --- | --- |
| DIF cond, L\_else | {0xFF, 0xEC} | 0x13 | Then-mask nonzero, no jump |
| ...then body... |  | 0x13 | Only lanes 0, 1, 4 write |
| L\_else: DELSE L\_end | {0xFF, 0xEC} | 0xEC | Else-mask nonzero, no jump |
| ...else body... |  | 0xEC | Lanes 2, 3, 5, 6, 7 write |
| L\_end: DENDIF | popped | 0xFF | Back to the original mask |

If the condition is false everywhere, DIF jumps straight to DELSE, which sets the else mask. If it's true everywhere, DELSE finds an empty else mask and jumps to DENDIF. No lane ever executes a body with an empty mask, which is what keeps loops inside a body from spinning forever.

**3 · Mask loops for data-dependent loops (the DDA walk).**

```c
uint32_t saved = mask_get();
while (ballot(walking)) {      // uniform, BALLOT writes every lane
    /* one DDA step on every active lane */
    lmask(still_walking);      // finished lanes drop out
}
mask_set(saved);
```

When the last lane drops out the mask becomes 0, BALLOT still writes 0 into every lane, the branch reads lane 0, and the loop exits cleanly.

### Where GCC can hurt us

GCC doesn't know masks exist. These are the failure modes and the rules that prevent them.

| Problem | What happens | Rule |
| --- | --- | --- |
| GCC turns a per-lane `if` or `min()` into a branch | Detector fires with a PC | Use the branchless `sel()` helper or GPU\_IF. Check `objdump` on the kernel once. |
| GCC moves plain arithmetic across a mask change | Fewer lanes get the value than you expected | Pin values with `gpu_keep(x)` before changing the mask |
| A value computed under a partial mask is read under a wider one | Lanes that were off see stale data | That's the semantics. Keep it in mind when restoring masks. |
| Spills to the stack | Each spill serializes over 8 lanes | Keep the kernel small and use `-O2`. Look at the stack size in the map file. |

The simulator catches all of these before hardware does.

### BALLOT

`result = {24'b0, (rs1_nonzero[7:0] & mask)}`, broadcast to every lane's rd.

### Performance model (multi-cycle)

Rough numbers, so we know what to expect and what to cut. The method is here so anyone can redo it with real CPI and step counts.

Assumptions. CPI 4. Average ray 30 DDA steps. About 120 instructions per pixel group for ray setup, shading and the pixel write. Software DDA about 15 instructions per step plus one serialized world load (9 cycles). VTRACE v1 at 2 cycles per step. 50 MHz.

| Configuration | Cycles per 8-pixel group | Groups per frame | Frame rate |
| --- | --- | --- | --- |
| Stage 1, software DDA, 160×120 | (120 + 30 × 15) × 4 + 30 × 9 ≈ 2,550 | 2,400 | about 8 fps |
| Stage 2, VTRACE, 160×120 | 120 × 4 + 30 × 2 + 50 ≈ 600 | 2,400 | about 35 fps |
| Stage 2, VTRACE, 320×240 | ≈ 600 | 9,600 | about 9 fps |
| Pipelined + VTRACE, 320×240 | ≈ 250 | 9,600 | about 20 fps |

Takeaway. Instruction count dominates, not memory. VTRACE is the big win, then pipelining. Measure the real steps-per-ray with CYCLES as soon as the kernel runs on the simulator.

### Stage 1 bring-up ladder

Each rung passes on the simulator and in Verilator (trace diff) before the next one starts.

- [ ] Core parameterized by `LANES`. `LANES = 1` passes every existing CPU test unchanged.
- [ ] `LANES = 8` with the mask stuck at 0x01 gives identical results to `LANES = 1`.
- [ ] LANEID and MASKALL. Test `t_laneid` passes.
- [ ] Lane-serial LSU with the full mask. Test `t_lsu_order` passes.
- [ ] LMASK, MASKGET, MASKSET, BALLOT. Tests `t_mask`, `t_ballot`, `t_maskgetset` pass.
- [ ] Uniform-branch detector. Test `t_branch_uniform` passes.
- [ ] Divergence stack. Tests `t_divstack`, `t_divskip` pass.
- [ ] Render kernel (software DDA) matches the simulator pixel for pixel.

### Pipelining notes specific to the GPU

- Mask and divergence stack are read in ID and written in EX. Flushing behind every mask-changing instruction (CPU Core section) keeps that correct.
- The uniform-branch detector moves to EX next to branch resolution.
- The serialized LSU is the main stall source. A banked per-lane stack region would remove spill serialization if it shows up in profiles.

## VTRACE Ray Unit

**Owner · Tai, RTL by the VTRACE agent (D10, D12) · Status · Draft · Stage 2**

Hardware Amanatides & Woo voxel traversal. One VTRACE instruction walks every active lane's ray until it hits something, the way RT cores do on RTX cards.

### Per-lane state

| Register | Width |
| --- | --- |
| cell x, y, z | 7 bits each, signed, so leaving the world is detectable |
| tMax x, y, z | 32 (Q16.16) |
| tDelta x, y, z | 32 (Q16.16) |
| step signs | 3 |
| done, hit, face axis, face sign, block type, steps, t\_hit | per the result format |

### One step

```c
if (tMaxX < tMaxY && tMaxX < tMaxZ) { t = tMaxX; x += sx; tMaxX += tDeltaX; axis = 0; }
else if (tMaxY < tMaxZ)             { t = tMaxY; y += sy; tMaxY += tDeltaY; axis = 1; }
else                                { t = tMaxZ; z += sz; tMaxZ += tDeltaZ; axis = 2; }
if (x, y, z outside 0..63 / 0..31 / 0..63)  → done, hit = 0
else if (world[x, y, z] != air)             → done, hit = 1, t_hit = t
```

- tMax additions saturate at 0x7FFF\_FFFF. A ray with a zero direction component gets tDelta = 0x7FFF\_FFFF from the kernel and never steps on that axis.
- The start cell is never tested.
- Stops when every active lane is done or the step cap (scalar rs1) is reached.

### v1 timing (multi-cycle)

Two cycles per step. STEP computes the next cell and issues the world address. CHECK reads the block type and decides. All 8 lanes step in parallel, each on its own BRAM port.

**v2 later.** One step per cycle by stepping speculatively. The check lags one cycle behind, and on a hit the unit rolls back to the previous cell, which it keeps in a register.

### World addressing

Address = {y\[4:0\], z\[5:0\], x\[5:0\]}, 17 bits, into a 4-bit-wide memory. Copy n serves lanes 2n (port A) and 2n + 1 (port B). These addresses are window-relative. world\_remap adds WIN\_ORIGIN and returns air for invalid slots, so VTRACE itself doesn't change for chunks (D14).

### Port list (Frozen with the Interfaces section (Shared tab))

```verilog
module vtrace #(parameter int LANES = 8) (
  input  logic             clk,
  input  logic             rst,
  // VSET: write one field for all active lanes
  input  logic             cfg_we,
  input  logic [2:0]       cfg_field,
  input  logic [LANES-1:0] lane_mask,
  input  logic [31:0]      cfg_data   [LANES],
  // VTRACE
  input  logic             start,       // one-cycle pulse
  input  logic [7:0]       max_steps,
  output logic             busy,
  output logic             done,        // one-cycle pulse
  // results, valid after done, read by VTRACE rd and VGET
  output logic [15:0]      result     [LANES],
  output logic [16:0]      hit_cell   [LANES],
  output logic [31:0]      t_hit      [LANES],
  // world read ports, one per lane, 1-cycle read latency
  output logic [16:0]      world_addr [LANES],
  input  logic [3:0]       world_data [LANES]
);
```

The top level muxes each world copy's two ports between the core and VTRACE using `busy`.

### Standalone test

- [ ] Verilator testbench with a random world and 10,000 random rays.
- [ ] Golden answers come from the same DDA in C (Kennedy's reference code), compared on result, hit\_cell and t\_hit.
- [ ] Edge cases. Axis-aligned rays, rays starting on a block edge, rays leaving each of the six faces, step cap reached.

### Kernel usage

```c
VSET(0, start_cell);
VSET(1, tmax_x);  VSET(2, tmax_y);  VSET(3, tmax_z);
VSET(4, tdel_x);  VSET(5, tdel_y);  VSET(6, tdel_z);
VSET(7, step_signs);
uint32_t r = vtrace(160);
int32_t  t = VGET(1);
```

## Memory & Display

**Owner · Tai · Status · Draft**

### Block RAM budget (Arty A7-100T has 135 BRAM36)

| Region | Size | BRAM36 | Notes |
| --- | --- | --- | --- |
| Instruction memory | 32 KB | 8 | Initialized from kc\_imem.hex |
| Data memory | 32 KB | 8 | Camera, game state, 1/x table, chunk bitmap, lane stacks |
| World window × 4 copies | 64 KB each (4 bits × 131,072 blocks) | 64 | Copy n serves lanes 2n and 2n + 1. Holds 4 × 4 chunks (D14). |
| Framebuffer × 2 | 76,800 B each | 38 | Dual-clock |
| Textures | 16 types × 3 faces × 16 × 16 × 4 bits | 2 | Top, side, bottom |
| Palette | 256 × 12 bits | 1 |  |
| DDR3 FIFOs | 2 × (128 bits × 512) | 4 | Chunk read and write data across clock domains |
| **Total** |  | **125 of 135** | Register files are LUT RAM. MIG itself uses LUTs, not BRAM. |

**If it doesn't fit or close timing.** Two world copies (VTRACE serves 4 lanes per cycle, half speed), or a 32 × 32 × 32 world.

### Actual utilization (fill in from Vivado)

| Build | LUTs | FFs | BRAM36 | DSP | Fmax | Date |
| --- | --- | --- | --- | --- | --- | --- |
| Stage 0 |  |  |  |  |  |  |
| Stage 1 |  |  |  |  |  |  |
| Stage 2 |  |  |  |  |  |  |

### VGA timing (640×480 at 60 Hz)

|  | Visible | Front porch | Sync | Back porch | Total |
| --- | --- | --- | --- | --- | --- |
| Horizontal (pixels) | 640 | 16 | 96 | 48 | 800 |
| Vertical (lines) | 480 | 10 | 2 | 33 | 525 |

Sync pulses are active low. The nominal pixel clock is 25.175 MHz. 25.0 MHz works on most displays and converters (Q5).

### Framebuffer scan-out

- FB\_MODE 0 (320×240). Read address = (vy >> 1) × 320 + (hx >> 1).
- FB\_MODE 1 (160×120). Read address = (vy >> 2) × 320 + (hx >> 2).
- Delay HSYNC, VSYNC and blank by the same number of cycles as the BRAM + palette read latency.
- Pixel byte → palette → RGB444 → Pmod VGA.

### Double buffering

- One select bit picks the front buffer. The CPU always writes the back buffer at 0x4000\_0000.
- Writing FB\_SWAP sets `swap_pending`. At the start of vblank the select bit flips and `swap_pending` clears.
- The game polls FB\_SWAP with mask 0x01 until it reads 0 before starting the next frame. MMIO is only touched with mask 0x01 (Tai\_2 section 2).

### Display chain

Arty → Pmod VGA (uses two adjacent Pmod headers, double check the pinout) → VGA-to-HDMI converter → portable monitor.

- [ ] Test the full chain with the existing VGA output before Saturday.
- [ ] Backup. VGA breakout plus resistor ladder on Pmod headers.

## DDR3 Chunk Store

**Owner · Tai, built by the DDR3 agent (P2b) · Status · Draft · Stage 0 (D14)**

DDR3 holds the whole 4,096 × 32 × 4,096 world as 65,536 chunks of 4 KB. The renderer never reads it. A chunk engine copies whole chunks between DDR3 and the 4 × 4-chunk BRAM window, which VTRACE traces exactly as before. Formats and registers are in Interfaces, Chunks (Shared tab).

### Blocks

| Block | Does |
| --- | --- |
| mig\_ddr3 | Xilinx 7-series MIG for the Arty's 256 MB DDR3L (16-bit). Generated from Digilent's published MIG project file, never hand-tuned. Raises calib\_done when the memory is trained. |
| ddr\_clk | Second MMCM from the 100 MHz board clock, giving 166.67 MHz and 200 MHz for MIG |
| Async FIFOs | Commands, read data and write data between the MIG user clock (about 81 MHz) and the 50 MHz core |
| chunk\_engine | 50 MHz side. Command queue depth 8, fed by CHUNK\_CMD. LOAD reads 256 transfers of 16 B and writes 8,192 blocks into the chunk's slot in all four world copies. STORE reads the slot from copy 0 and writes it back. Bumps CHUNK\_DONE once per command. |
| world\_remap | Sits between the core, VTRACE and world\_mem. Physical x = (x + WIN\_ORIGIN.x) mod 64, same for z. Reads in an invalid slot return air. The chunk engine bypasses it and writes physical addresses. |
| ddr\_model | Behavioral stand-in for the MIG user interface (an array with a fixed latency) for Verilator and the simulator, since MIG can't be simulated in Verilator |

### Port sharing

The chunk engine pauses while VTRACE is busy, because VTRACE uses every world port. It resumes the moment VTRACE finishes. Core loads and stores to the world still work as before, with the chunk engine yielding to them.

### Timing

One chunk LOAD is limited by BRAM writes at 4 bits per port per cycle. 8,192 blocks take about 164 µs, so a new edge of 4 chunks is about 0.7 ms. DDR3 could go about 50 times faster than that. A wider world write port (8 blocks per cycle) is the upgrade if it ever matters.

### Gate

- [ ] Standalone DDR3 test design calibrates and passes on the board
- [ ] chunk\_engine with ddr\_model passes t\_chunk\_roundtrip, t\_slot\_valid and t\_ring in Verilator
- [ ] Merged into top by hour 5

If the standalone test isn't passing by hour 6, cut it (D14). The chunk manager then generates chunks procedurally through the same API, and the game doesn't notice.
