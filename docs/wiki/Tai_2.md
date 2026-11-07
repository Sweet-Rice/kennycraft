# Tai\_2 · ISA spec and agent prompts

One prompt per stage for Tai's agent sessions, each pasted into a fresh session that can read the design doc as a GitHub wiki. The Interfaces section lists the custom opcodes but leaves their exact encodings and masking behavior open, so the first two sections pin those down and every prompt treats them as the spec.

## 1 · ISA v1.0

The core runs RV32I + Zmmul plus 12 custom instructions in three opcode spaces. This section is the encoding source of truth. It is part of Interfaces v1.0 and freezes with the Interfaces section (Shared tab) (D13).

### Base ISA

| Group | Behavior |
| --- | --- |
| RV32I (all 37 user instructions except FENCE, ECALL, EBREAK) | Standard, per the RISC-V unprivileged spec |
| Zmmul (MUL, MULH, MULHSU, MULHU) | Standard. opcode 0x33, funct7 0000001, funct3 000 to 011 |
| DIV, DIVU, REM, REMU (funct3 100 to 111 with funct7 0000001) | Illegal |
| FENCE, FENCE.I | No-op |
| ECALL, EBREAK, every CSR instruction | Illegal (there is no Zicsr) |
| Misaligned load or store (LW/SW not 4-aligned, LH/LHU/SH not 2-aligned) | Illegal |
| Fetch outside instruction memory | Illegal |
| Load or store to an unmapped region (address bits 31:28 = 0x7 to 0xF) | Loads return 0, stores are dropped, no error |

"Illegal" always means set ERR.ILLEGAL, latch the PC into ERR\_PC and halt until reset.

### Custom instruction formats

R-type fields are funct7 \[31:25\] · rs2 \[24:20\] · rs1 \[19:15\] · funct3 \[14:12\] · rd \[11:7\] · opcode \[6:0\]. DIF and DELSE use the standard B-type immediate (PC-relative, ±4 KiB, bit 0 always 0). Fields marked 0 are emitted as 0 by the assembler and ignored by the decoder.

| Instruction | opcode | funct3 | funct7 | rd | rs1 | rs2 | Assembler (`.insn`) | Example hex |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| LANEID rd | 0x0B | 000 | 0 | rd | 0 | 0 | `.insn r 0x0B, 0, 0, rd, x0, x0` | a0 → `0x0000050B` |
| LMASK rs1 | 0x0B | 001 | 0 | 0 | rs1 | 0 | `.insn r 0x0B, 1, 0, x0, rs1, x0` | a1 → `0x0005900B` |
| BALLOT rd, rs1 | 0x0B | 011 | 0 | rd | rs1 | 0 | `.insn r 0x0B, 3, 0, rd, rs1, x0` | a0, a1 → `0x0005B50B` |
| MASKGET rd | 0x0B | 101 | 0 | rd | 0 | 0 | `.insn r 0x0B, 5, 0, rd, x0, x0` | a0 → `0x0000550B` |
| MASKSET rs1 | 0x0B | 110 | 0 | 0 | rs1 | 0 | `.insn r 0x0B, 6, 0, x0, rs1, x0` | a1 → `0x0005E00B` |
| MASKALL | 0x0B | 111 | 0 | 0 | 0 | 0 | `.insn r 0x0B, 7, 0, x0, x0, x0` | `0x0000700B` |
| VSET field, rs1 | 0x2B | 000 | field 0 to 7 | 0 | rs1 | 0 | `.insn r 0x2B, 0, field, x0, rs1, x0` | 3, a1 → `0x0605802B` |
| VTRACE rd, rs1 | 0x2B | 001 | 0 | rd | rs1 (step cap) | 0 | `.insn r 0x2B, 1, 0, rd, rs1, x0` | a0, a1 → `0x0005952B` |
| VGET rd, field | 0x2B | 010 | field 0 or 1 | rd | 0 | 0 | `.insn r 0x2B, 2, field, rd, x0, x0` | a0, 1 → `0x0200252B` |
| DIF rs1, label | 0x5B | 000 | B-type imm | B-type imm | rs1 | 0 | `.insn b 0x5B, 0, rs1, x0, label` | a1, +16 → `0x0005885B` |
| DELSE label | 0x5B | 001 | B-type imm | B-type imm | 0 | 0 | `.insn b 0x5B, 1, x0, x0, label` | +8 → `0x0000145B` |
| DENDIF | 0x5B | 010 | 0 | 0 | 0 | 0 | `.insn r 0x5B, 2, 0, x0, x0, x0` | `0x0000205B` |

### Illegal custom encodings

- custom-0 (0x0B) with funct3 010 or 100, or funct7 ≠ 0.
- custom-1 (0x2B) with funct3 011 to 111, VTRACE with funct7 ≠ 0, or VGET with funct7 ≥ 2 (field 2 is reserved for the fog stretch).
- custom-2 (0x5B) with funct3 011 to 111.
- Any custom instruction in a build where its unit is absent (custom-1 before Stage 2).

### Width with LANES < 8

The mask, BALLOT and MASKGET are LANES bits wide, zero-extended to 32. MASKALL sets every one of the LANES bits. MASKSET keeps rs1\[LANES-1:0\]. With LANES = 1, LANEID always returns 0.

## 2 · Masking semantics v1.0

One LANES-bit active mask M decides which lanes an instruction affects. Lane i is active when M\[i\] = 1. Reset sets M = 0x01, empties the divergence stack and sets PC = 0. The simulator and the RTL implement these rules exactly, and every rule has a test.

### Terms

- **Scalar lane.** The lowest-numbered active lane, or lane 0 when M = 0. Any instruction that needs one value reads it from here.
- **Uniform check.** Compares a per-lane result across active lanes only. With M = 0 there is nothing to compare and the check passes.
- **Halt.** Set the ERR bit, latch the PC into ERR\_PC, stop fetching, light the error LED. Only reset clears it.

### What each instruction class does

| Class | Active lanes | Inactive lanes | Shared state and checks |
| --- | --- | --- | --- |
| ALU, LUI, AUIPC, MUL family, LANEID | Write rd | rd unchanged | None |
| Loads | Access memory and write rd | No memory access, rd unchanged | Lane accesses run in ascending lane order |
| Stores | Write memory | No memory access | Ascending lane order, so on equal addresses the highest active lane wins |
| MMIO loads and stores | One bus access per active lane | None | Side effects happen once per active lane. Reading UART\_RX with 8 lanes active pops 8 bytes, so touch MMIO only with M = 0x01 |
| BEQ, BNE, BLT, BGE, BLTU, BGEU | Compare | Ignored | Uniform check on the taken/not-taken outcome. Disagreement halts with ERR.DIVERGE. With M = 0 the outcome is lane 0's |
| JAL | Write the link register | Link unchanged | PC update is shared |
| JALR | Write the link register | Link unchanged | Target comes from the scalar lane. Uniform check on the target address, mismatch halts with ERR.DIVERGE |
| BALLOT rd, rs1 | Contribute bit i = (rs1 ≠ 0) | Contribute 0 | rd is written in every lane, active or not |
| MASKGET rd | Write M | Write M | rd is written in every lane |
| LMASK rs1 | Lane stays active only if rs1 ≠ 0 | Stays inactive | M = M & {rs1ᵢ ≠ 0} |
| MASKSET rs1 | No register write | No register write | M = scalar lane's rs1\[LANES-1:0\]. This can wake inactive lanes, whose registers may hold stale values |
| MASKALL | No register write | No register write | M = all ones |
| VSET field, rs1 | Ray state field = rs1 | Ray state unchanged | None |
| VTRACE rd, rs1 | Ray walks, rd = result | Ray state and rd unchanged | Step cap = scalar lane's rs1\[7:0\]. A cap of 0 or M = 0 finishes at once with no writes. The core stalls until every active ray is done |
| VGET rd, field | Write rd | rd unchanged | None |
| x0 | Never written | Never written | None |

### Divergence stack

Eight entries of {saved, else}, each LANES bits, plus a pointer. Exact behavior:

```c
DIF rs1, L:   if (sp == 8) halt(DIVSTACK);
              t = M & lanes_where(rs1 != 0);
              push({ .saved = M, .else = M & ~t });
              M = t;
              if (t == 0) PC = L; else PC += 4;

DELSE L:      if (sp == 0) halt(DIVSTACK);
              M = top.else;
              if (M == 0) PC = L; else PC += 4;

DENDIF:       if (sp == 0) halt(DIVSTACK);
              M = top.saved;  pop();  PC += 4;
```

- DIF's label points at its DELSE, or at DENDIF when there is no else. DELSE's label points at DENDIF.
- DENDIF restores the mask from before DIF. Any LMASK or MASKSET inside the if or else body is undone there.
- A DIF reached with M = 0 pushes {0, 0} and skips straight to DENDIF, so nesting inside an empty body stays balanced.
- Uniform branches stay legal inside bodies. They are checked against the body's mask.

### Mask loops

The DDA walk uses `while (ballot(p)) { ...; lmask(p); }` with the mask saved before and restored after. When the last lane drops out, M becomes 0, BALLOT still writes 0 into every lane, the loop branch reads lane 0 and exits. Function calls with M = 0 are not allowed, because JAL would not write the return address in any lane.

### Errors

| ERR bit | Cause |
| --- | --- |
| 0 · DIVERGE | A branch outcome or JALR target disagrees across active lanes |
| 1 · DIVSTACK | DIF with 8 entries on the stack, or DELSE/DENDIF with an empty stack |
| 2 · ILLEGAL | Any illegal case in section 1 |

### Tests for these rules (also in the Verification section)

| Test | Checks |
| --- | --- |
| t\_mask\_zero | Mask loop exits cleanly when the last lane drops out, BALLOT writes 0 everywhere |
| t\_mmio\_lanes | A UART\_RX read under M = 0x03 pops two bytes, in lane order |
| t\_jalr\_uniform | A JALR with lane-dependent targets halts with ERR.DIVERGE and the right ERR\_PC |
| t\_div\_nested\_lmask | LMASK inside a then-body is undone by DENDIF |
| t\_divstack\_overflow | Nine nested DIFs halt with ERR.DIVSTACK |
| t\_illegal | DIV, ECALL, a CSR read, a misaligned LW and VGET field 2 each halt with ERR.ILLEGAL |

## 3 · How to run these prompts

Each prompt runs in its own fresh agent session, started in the repo, with the preamble pasted first and the stage prompt right after it. Tai reviews every diff before it merges, and nothing merges until `make check` is green.

### Assumed setup (edit if the repo differs)

| Thing | Where |
| --- | --- |
| Design doc | GitHub wiki, one page per tab: Shared, Tai, Tai\_2, Kenny, Bennett |
| RTL | `rtl/` (`core/`, `soc/`, `display/`, `vtrace/`, `top.sv`, `kc_isa_pkg.sv`) |
| Verilator testbenches | `tb/` |
| Software, tests, linker script | `sw/` (`gpu.h`, `crt0.S`, `kc.ld`, `tests/t_*.S`), owned by Bennett |
| Instruction simulator | `sim/`, owned by Bennett |
| Vivado | `fpga/` (`arty.xdc`, `build.tcl`), part xc7a100tcsg324-1 |
| Make targets | `make sim`, `make vl`, `make check`, `make board` (Bennett tab, Make targets) |

### Preamble (paste first in every session)

```text
You are working in the KennyCraft repo. KennyCraft is an 8-lane SIMD GPU grown from a multi-cycle RV32I core, running a voxel Minecraft on an Arty A7-100T (xc7a100tcsg324-1). The design doc is this repo's GitHub wiki. Before writing any code, read the wiki pages this prompt names, plus Tai_2 sections 1 and 2 (ISA and masking semantics). Tai_2 wins wherever pages disagree.

Rules for this session.
1. SystemVerilog only, synthesizable in Vivado, lint clean in Verilator with -Wall.
2. Multi-cycle unless this prompt says otherwise. No pipeline registers, no forwarding, no hazard logic.
3. Touch only the files this prompt lists. If another file needs a change, stop and say which file and why.
4. Never change an opcode, encoding, MMIO offset, memory-map address or frozen port list. If the spec looks wrong or ambiguous, stop and ask. Do not pick an interpretation silently.
5. Keep the LANES parameter on every module that has per-lane state, even when this stage only uses LANES = 1.
6. Done means every check in this prompt passes. Run each check yourself and paste its real output. Never report a check as passing without running it.
7. Commit in small steps with clear messages. Do not push.
8. End with a short report. What you built, files touched, checks run and their results, open questions, and LUT, FF, BRAM, DSP and timing numbers if you ran Vivado.
```

## 4 · Prompts · Stage 0

Five sessions. P0 runs Friday night. P1, P2 and P2b (the DDR3 agent, D14) run side by side from hour 0. P3 joins them for the first frame by hour 3, and P2b's chunk store merges by hour 5.

### P0 · ISA package and encoding check (Friday night)

```text
Goal. Turn Tai_2 sections 1 and 2 into code that every later session imports, so no one hand-types an opcode again.

Read. Tai_2 sections 1 and 2. Shared page, Interfaces section. Bennett page, gpu.h.

Build.
1. rtl/kc_isa_pkg.sv. localparams for the three custom opcodes, every funct3, the VSET and VGET field numbers, the ERR bit positions, and the MMIO offsets. Add a function is_illegal(instr) covering every illegal case in Tai_2 section 1, with a LANES-independent interface.
2. tb/isa/test_encoding.cpp (Verilator). Feed every row of the Tai_2 encoding table through a small decode module that uses the package, and check opcode, funct3, funct7, rd, rs1 and B-type immediates against the example hex column.
3. sw/tests/encoding.S. Assemble every custom instruction with the .insn lines from the table. A script compares the objdump bytes against the same example hex.

Touch only. rtl/kc_isa_pkg.sv, rtl/isa_decode_check.sv, tb/isa/*, sw/tests/encoding.S, scripts/check_encoding.py.

Done when.
- Every example hex in Tai_2 matches both the assembler output and the decode module.
- is_illegal returns 1 for each case in the Illegal custom encodings list and 0 for every legal row.
- If any example hex in Tai_2 is wrong, stop and report it. Do not change the table.
```

### P1 · Display path (hour 0 to 3, parallel with P2)

```text
Goal. Everything from the framebuffer to the VGA pins, with a simple core-side port, so the core only has to write bytes.

Read. Tai page, Memory & Display section and CPU Core, Clocking. Shared page, Interfaces, Memory map, MMIO and Pixel byte.

Build.
1. rtl/display/clk_gen.sv. MMCM from the 100 MHz board clock to 50 MHz (core) and 25 MHz (pixel), with a locked output that holds both domains in reset until lock.
2. rtl/display/vga_timing.sv. 640x480 at 60 Hz with the exact porch and sync numbers from the VGA timing table. Sync active low.
3. rtl/display/framebuffer.sv. Two 320x240 byte buffers (76,800 bytes each) as true dual-clock BRAM. Port A on the 50 MHz side for the core, port B on the 25 MHz side for scan-out. A front-select bit picks which buffer scans out. The core always writes and reads the back buffer.
4. Swap logic. A write of 1 to FB_SWAP sets swap_pending. At the first pixel clock of vblank the select bit flips and swap_pending clears. FB_SWAP, VSYNC and FRAME_COUNT cross into the 50 MHz domain through two-flop synchronizers.
5. FB_MODE 0 reads (vy>>1)*320+(hx>>1). FB_MODE 1 reads (vy>>2)*320+(hx>>2). Delay hsync, vsync and blank by the BRAM plus palette latency so pixels line up.
6. rtl/display/palette.sv. 256 x 12-bit RGB444, written from the core side at 0x6000_0000 (one entry per 32-bit store, low 12 bits), read on the pixel side.
7. Core-side port, all on the 50 MHz clock. fb_we, fb_re, fb_addr[16:0], fb_wdata[7:0], fb_rdata[7:0] with 1-cycle read latency. pal_we, pal_addr[7:0], pal_wdata[11:0]. swap_req, swap_pending, vblank, frame_count[31:0], fb_mode.
8. fpga/arty.xdc. Pmod VGA pins for the two adjacent Pmod headers. Leave a TODO naming which header pair, and stop to ask if the Digilent Pmod VGA pinout is not in the repo.

Touch only. rtl/display/*, tb/display/*, fpga/arty.xdc (VGA and clock pins only).

Done when.
- Verilator test writes a known pattern through the core-side port, runs two frames, captures the VGA pins into a PPM, and the PPM matches the expected image pixel for pixel in both FB_MODEs.
- A swap requested mid-frame takes effect at the next vblank, never mid-frame.
- Lint clean. Report the BRAM36 count, which should be 38 for the framebuffers plus 1 for the palette.
```

### P2 · Core additions (hour 0 to 3, parallel with P1)

```text
Goal. Turn Tai's existing multi-cycle RV32I core into the Stage 0 core. Zmmul, hex-initialized memories, the address decoder, UART, MMIO and error halts.

Read. Tai page, CPU Core (What exists today, State machine, Stage 0 additions, Module hierarchy). Shared page, Interfaces (Memory map, Data memory layout, MMIO). Tai_2 sections 1 and 2. Read rtl/core/ in full before changing it.

Build.
1. Use rtl/kc_isa_pkg.sv from P0 for every opcode and field constant.
2. Zmmul on DSP48E1. Register the product, so MUL family instructions spend 2 cycles in EXECUTE. DIV and REM decode as illegal.
3. rtl/soc/decoder.sv on address bits 31:28 per the memory map. Regions with no hardware yet (world, textures) are BRAM stubs of the right size so software can run. Unmapped regions read 0 and drop writes.
4. imem 32 KB and dmem 32 KB as BRAM loaded with $readmemh from kc_imem.hex and kc_dmem.hex (paths are parameters). Reset vector 0x0000_0000.
5. rtl/soc/uart.sv. 1 Mbaud 8N1 at 50 MHz (exactly 50 clocks per bit). 16-byte RX FIFO, TX with a busy flag.
6. rtl/soc/mmio.sv. Every register in the MMIO table with the stated access types, including ERR (write 1 to clear), ERR_PC, CYCLES (free-running), LEDS and FB_MODE. Connect FB_SWAP, VSYNC, FRAME_COUNT and FB_MODE to the P1 core-side port signal names.
7. Error halt per Tai_2 section 2. Illegal instructions and misaligned accesses set ERR.ILLEGAL, latch ERR_PC, stop fetching and drive an error LED.
8. Keep the core parameterized by LANES with LANES = 1 (D7). Do not add any per-lane logic yet.

Touch only. rtl/core/*, rtl/soc/*, rtl/mem/*, tb/core/*.

Done when.
- Every existing CPU test still passes in Verilator.
- t_zmmul, t_uart and t_illegal pass on the simulator and in Verilator with identical traces (make vl).
- Report the CPI of each instruction class measured with CYCLES, so the planning table on the Tai page can be replaced with real numbers.
```

### P2b · DDR3 chunk store (hour 0 to 5, parallel with P1 and P2)

```text
Goal. The DDR3 chunk store from D14, proven on the board in a standalone design and handed to Tai to merge by hour 5. DDR3 holds 65,536 chunks of 16 x 32 x 16 blocks (4 KB each) and is reached only through a chunk copy engine. Nothing else touches it, and there is no cache (D15).

Read. Shared page, Decisions (D14, D15) and Interfaces (Memory map, MMIO, Chunks). Tai page, DDR3 Chunk Store and Memory & Display. Kenny page, Chunk API. Tai_2 section 2 (MMIO rows).

Build.
1. rtl/ddr/mig/. Generate the 7-series MIG for the Arty A7-100T's 256 MB DDR3L (16-bit) from Digilent's published MIG project file. Do not hand-tune timing parameters. If the project file is not in the repo, stop and ask.
2. rtl/ddr/ddr_clk.sv. A second MMCM from the 100 MHz board clock giving 166.67 MHz (MIG system clock) and 200 MHz (MIG reference clock).
3. Async FIFOs (XPM) for commands, read data and write data between the MIG user clock (about 81 MHz) and the 50 MHz core clock.
4. rtl/ddr/chunk_engine.sv on the 50 MHz side. A command queue of depth 8 fed by CHUNK_CMD. LOAD reads 256 x 128-bit transfers from DDR3 address (cz*256 + cx)*4096 and writes the 8,192 blocks into slot (cx mod 4, cz mod 4) of all four world copies. STORE reads that slot from copy 0 and writes it back. Pause while VTRACE busy is high. CHUNK_DONE increments once per finished command.
5. rtl/ddr/world_remap.sv between every world requester (core, VTRACE) and world_mem. Physical x = (x + WIN_ORIGIN.x) mod 64, same for z. Reads in a slot whose SLOT_VALID bit is 0 return 0. The chunk engine bypasses the remap and writes physical addresses.
6. The registers DDR_STATUS, CHUNK_CMD, CHUNK_DONE, SLOT_VALID and WIN_ORIGIN at the offsets in the Interfaces MMIO table. A CHUNK_CMD write while the queue is full stalls the core until there is room.
7. rtl/ddr/ddr_model.sv. A behavioral stand-in for the MIG user interface (an array plus a fixed latency) so Verilator and Bennett's simulator can run the chunk engine without the real controller.
8. fpga/ddr_test/. A standalone bitstream that waits for calibration, writes a pattern into 64 chunks spread across all 256 MB, reads them back, and reports pass or fail on the LEDs and over UART.

Touch only. rtl/ddr/*, tb/ddr/*, fpga/ddr_test/*, and the DDR3 pin and constraint lines in fpga/arty.xdc.

Done when.
- Hardware. The standalone test calibrates and passes on the board with timing met.
- Verilator. chunk_engine with ddr_model passes t_chunk_roundtrip, t_slot_valid and t_ring.
- Report LUT, FF and BRAM used by MIG plus the engine, and the measured time for one chunk LOAD.
- Gate. If calibration does not pass on the board by hour 6, stop and report. Per D14 the chunk manager then generates chunks procedurally through the same API.
```

### P3 · Top level and first kernel frame (hour 2 to 3)

```text
Goal. Wire P1 and P2 into one bitstream, get Bennett's make board flow working, and put Kennedy's first kernel frame on the monitor by hour 3.

Read. Tai page, CPU Core (Module hierarchy, Stage 0 additions, last bullet on fast rebuilds). Bennett page, Build and Make targets.

Build.
1. rtl/top.sv per the module hierarchy. clk_gen, core, imem, dmem, decoder, mmio, uart, display. Add the DDR3 chunk store from P2b once it passes its board test (by hour 5, D14). Keep the port list Tai published at hour 1 unchanged, because Bennett's Verilator harness depends on it.
2. fpga/build.tcl. Full synthesis and implementation for xc7a100tcsg324-1, timing report, utilization report, bitstream. After implementation, run write_mem_info so updatemem can patch new kc_imem.hex and kc_dmem.hex into the bitstream without a rebuild.
3. Confirm make board (Bennett) patches and programs in under a minute.

Touch only. rtl/top.sv, fpga/*.

Done when.
- Timing met at 50 MHz core and 25 MHz pixel.
- make board puts Kennedy's plain C render on the monitor at 160x120, and the same frame from make vl matches it.
- Fill the Stage 0 row of the Actual utilization table on the Tai page.
```

## 5 · Prompts · Stage 1

Two sessions, run back to back from hour 5. They cover the eight rungs of the Stage 1 bring-up ladder on the Tai page. Bennett's simulator must already implement every custom instruction, because it is the reference both sessions diff against.

### P4 · Lanes, mask register and lane-serial LSU (rungs 1 to 4)

```text
Goal. Make the Stage 0 core an 8-lane SIMD core with one shared control path, a mask register, LANEID, MASKALL and a lane-serial LSU, without breaking LANES = 1.

Read. Tai page, GPU Core (What changes from the CPU, Register files, SIMD state machine, Lane-serial LSU, Stage 1 bring-up ladder). Tai_2 sections 1 and 2, especially the class table. Shared page, Interfaces, Execution model.

Build.
1. Split rtl/core into shared control (PC, fetch, decode, FSM, mask) and rtl/core/lane.sv (32x32 register file in distributed RAM with 2 read and 1 write ports, ALU, multiplier, branch comparator, address generator). Instantiate LANES lanes.
2. Mask register, LANES bits, reset 1. Lane write enable is wb_en & (M[i] | uniform_write) & (rd != 0), where uniform_write is set only for BALLOT and MASKGET.
3. LANEID and MASKALL per Tai_2.
4. Scalar lane mux (lowest active lane, lane 0 when M = 0) feeding branch decisions and JALR targets for now. Branch uniform checking comes in P5, so for now take the scalar lane's outcome.
5. rtl/core/lsu.sv. A priority encoder walks active lanes in ascending order. Issue lane n's address while lane n-1's load data returns, so N active lanes take about N + 1 cycles. Loaded data lands in a per-lane holding register and all lanes write back together. Inactive lanes make no bus access. A store to the world region writes the same address in all four world copies.

Touch only. rtl/core/*, tb/core/*.

Done when, in this order, each one passing before you start the next.
- Rung 1. LANES = 1 passes every Stage 0 test with an unchanged trace.
- Rung 2. LANES = 8 with M stuck at 0x01 gives a trace identical to LANES = 1 on every test (tracediff).
- Rung 3. t_laneid passes on the simulator and in Verilator.
- Rung 4. t_lsu_order and t_mmio_lanes pass. Report LSU cycles for 1, 4 and 8 active lanes.
- Report LUT usage of the 8 register files.
```

### P5 · Mask control, uniform checks and divergence stack (rungs 5 to 8)

```text
Goal. Finish the Stage 1 GPU. LMASK, MASKGET, MASKSET, BALLOT, the uniform-branch and uniform-JALR checks, and the DIF / DELSE / DENDIF stack, all exactly as Tai_2 section 2 states them.

Read. Tai_2 sections 1 and 2 in full, including the divergence pseudocode and the mask-loop rule. Tai page, GPU Core (Divergence, Where GCC can hurt us, BALLOT). Shared page, Verification (per-instruction tests).

Build.
1. LMASK, MASKGET, MASKSET, BALLOT. BALLOT result is {0, rs1_nonzero & M} written to rd in every lane.
2. Uniform check on branch outcomes and JALR targets across active lanes. A mismatch halts with ERR.DIVERGE and ERR_PC. With M = 0 there is no check and lane 0 decides.
3. rtl/core/divstack.sv. 8 entries of {saved, else}, LANES bits each. Implement the pseudocode in Tai_2 section 2 line for line, including the DIVSTACK halts and the jump-on-empty cases. DIF and DELSE take the standard B-type immediate.
4. Add the six tests listed at the end of Tai_2 section 2 (also in the Verification section, Shared tab). Coordinate the file names with Bennett, who owns sw/tests and the simulator.

Touch only. rtl/core/*, tb/core/*, sw/tests/ (new test files only).

Done when, in order.
- Rung 5. t_mask, t_ballot, t_maskgetset, t_mask_zero pass.
- Rung 6. t_branch_uniform and t_jalr_uniform pass, and ERR_PC matches the faulting instruction.
- Rung 7. t_divstack, t_divskip, t_div_nested_lmask, t_divstack_overflow pass.
- Rung 8. Kennedy's 8-lane software DDA kernel matches the simulator pixel for pixel in make check, then on the board.
- Fill the Stage 1 row of the Actual utilization table, and report the measured fps from CYCLES.
```

## 6 · Prompts · Stage 2

P6 is the VTRACE agent from D10. It starts at hour 5 against the frozen port list and never touches the core. P7 plugs its module into the core once Stage 1 is green at hour 10.

### P6 · VTRACE agent (hour 5 to about 11)

```text
Goal. A standalone, multi-cycle hardware voxel ray walker (Amanatides & Woo DDA) for 8 lanes, matching the frozen port list exactly and proven against Kennedy's C reference.

Read. Tai page, VTRACE Ray Unit in full (Per-lane state, One step, v1 timing, World addressing, Port list, Standalone test). Shared page, Interfaces (Ray unit table, VSET fields, VTRACE result, VGET fields). Tai_2 section 2, the VSET, VTRACE and VGET rows.

Build.
1. rtl/vtrace/vtrace.sv with the port list from the Tai page, character for character. If the port list cannot work, stop and say why. Do not edit it.
2. Per-lane state as listed. cfg_we writes cfg_field from cfg_data only in lanes set in lane_mask.
3. On start, every lane in lane_mask walks. Two cycles per step. STEP picks the smallest tMax, moves the cell, adds tDelta with saturation at 0x7FFF_FFFF and issues world_addr. CHECK reads world_data and finishes the lane on a solid block (hit = 1) or on leaving 0..63 / 0..31 / 0..63 (hit = 0). The start cell is never tested.
4. Stop when every active lane is done or max_steps is reached. A max_steps of 0 or an empty lane_mask raises done on the next cycle with no state change. Inactive lanes' results never change.
5. result packs hit, face axis, face sign, block type and steps exactly as the VTRACE result table says. hit_cell packs x, y, z like VSET field 0. t_hit is Q16.16.
6. World address = {y[4:0], z[5:0], x[5:0]} with 1-cycle read latency.

Touch only. rtl/vtrace/*, tb/vtrace/*.

Done when.
- Verilator testbench with a seeded random 64x32x64 world and 10,000 random rays matches Kennedy's C reference (sw/ref/dda.c, called through DPI or as golden files) on result, hit_cell and t_hit for every ray.
- Edge cases pass. Axis-aligned rays, a zero direction component, rays starting on a block edge, rays leaving through each of the six faces, step cap reached, empty lane_mask, max_steps = 0.
- Out-of-context synthesis for xc7a100tcsg324-1 meets 50 MHz. Report LUT, FF and DSP counts.
```

### P7 · VTRACE integration (hour 10 to 12)

```text
Goal. Make VSET, VTRACE and VGET real instructions in the Stage 1 core, backed by four world copies, so Kennedy's VTRACE kernel runs on the board.

Read. Tai_2 sections 1 and 2 (custom-1 encodings, VSET, VTRACE and VGET masking rows). Tai page, VTRACE Ray Unit (Port list, World addressing) and Memory & Display (Block RAM budget). Shared page, Interfaces, Ray unit.

Build.
1. Decode custom-1. VSET drives cfg_we, cfg_field = funct7, cfg_data = each lane's rs1, lane_mask = M. VTRACE pulses start with max_steps = scalar lane rs1[7:0], stalls the FSM until done, then writes result to rd in active lanes. VGET reads hit_cell (field 0) or t_hit (field 1) into rd in active lanes. VGET field 2 and up is illegal.
2. rtl/mem/world_mem.sv. Four copies of 131,072 x 4 bits. Copy n serves lanes 2n (port A) and 2n+1 (port B). The core owns both ports except while busy is high, when VTRACE owns them. Core stores write all four copies at the same address, and core loads read copy 0.
3. Add the VTRACE module to rtl/top.sv.

Touch only. rtl/core/* (decode, FSM, writeback only), rtl/mem/world_mem.sv, rtl/top.sv, tb/core/*.

Done when.
- t_vtrace passes on the simulator, in Verilator and on the board with identical traces.
- Kennedy's VTRACE kernel produces the same pixels as the software DDA kernel in make check.
- Timing met at 50 MHz. Fill the Stage 2 row of the Actual utilization table and report fps from CYCLES at 160x120.
- If BRAM goes over 135 or timing fails, stop and report. The fallback is two world copies (Tai page, Block RAM budget), and that is Tai's call.
```

## 7 · Prompt · Pipelined core

The pipelining agent from D10 starts at hour 10, once Stage 1 is green. It builds a second core next to the multi-cycle one, so the working core is always one parameter away.

### P8 · Pipelining agent (hour 10 to about 14)

```text
Goal. A 5-stage pipelined version of the 8-lane core that retires exactly the same instruction trace as the multi-cycle core, at 50 MHz or better. This rule overrides preamble rule 2 for this session only.

Read. Tai page, CPU Core (Pipelining plan) and GPU Core (Pipelining notes specific to the GPU, Lane-serial LSU, Divergence). Tai_2 sections 1 and 2. Read the multi-cycle core in rtl/core in full first. Its behavior is the specification.

Build.
1. rtl/core_pipe/ with the same module ports as rtl/core. A top-level parameter PIPELINED selects which one rtl/top.sv instantiates. Never edit rtl/core.
2. IF / ID / EX / MEM / WB. Forward EX to EX and MEM to EX for every lane. Stall 1 cycle on load-use.
3. Branches and JALR resolve in EX, predict not-taken, flush 2. The uniform check moves to EX next to branch resolution.
4. The mask and divergence stack are read in ID and written in EX. Treat LMASK, MASKSET, MASKALL, DIF, DELSE and DENDIF like taken branches and flush everything behind them.
5. MUL family is 2 cycles and stalls the pipe. The lane-serial LSU stalls the whole pipe for (active lanes + 1) cycles. VTRACE stalls the pipe from start until done.
6. ERR halts must report the PC of the faulting instruction, not a younger one in flight.
7. You may drive Vivado through the MCP to read timing reports. Forwarding muxes across 8 lanes are the likely critical path. Retime or add a register stage only if the trace still matches.

Touch only. rtl/core_pipe/*, the PIPELINED parameter line in rtl/top.sv, tb/core_pipe/*.

Done when.
- tracediff shows the pipelined and multi-cycle retired-instruction traces identical (pc, instr, mask, every lane's rd write) on every t_ test and on a 600-frame replay of a recorded play session.
- Every ERR test halts with the same ERR bit and ERR_PC on both cores.
- Timing met at 50 MHz on xc7a100tcsg324-1. Report WNS, the critical path, LUT and FF deltas against the multi-cycle core, measured CPI, and fps at 160x120 and 320x240.
- If the trace cannot be made identical by hour 14, stop and report the first mismatch. Tai decides whether to keep going.
```

## 8 · Prompts · Stage 3 stretch

Run these in order during the 15 to 21 window, one session each, and only on a green build. A stretch that is not green on the board by hour 21 gets reverted. Shadow rays and the separate CPU and GPU have no prompts yet. Write them only if P9 and P10 land early.

### P9 · Fog accumulator in VTRACE

```text
Goal. Volumetric fog for about an hour of RTL. Every VTRACE step through fog adds to a per-lane accumulator that the kernel reads back with VGET field 2.

Read. Tai page, VTRACE Ray Unit and Stretch order. Tai_2 sections 1 and 2. Kenny page, Rendering kernel (Shade step).

This changes a frozen interface. Before writing RTL, write the change request row for the Decisions section (Shared page) and stop until Tai confirms it. The proposed change follows.
- Fog is any air cell with y < FOG_Y. All eight VSET fields are taken, so FOG_Y is a module parameter (default 12) in v1.
- Each step taken through a fog cell adds the step's t increment (new t minus previous t, Q16.16) to fog_acc.
- VGET field 2 returns fog_acc (Q16.16) in active lanes. Field 2 stops being illegal. Fields 3 and up stay illegal.
- fog_acc clears on VTRACE start in active lanes.

Touch only. rtl/vtrace/*, the VGET decode lines in the core, kc_isa_pkg.sv, tb/vtrace/*.

Done when.
- The 10,000-ray testbench still matches on result, hit_cell and t_hit, and fog_acc matches an extended C reference within 1 LSB.
- t_vtrace passes, and a new t_vtrace_fog passes on the simulator (Bennett adds field 2 there) and in Verilator.
- Timing still met at 50 MHz and fps drops by under 5 percent.
```

### P10 · Two-level traversal

```text
Goal. Let rays skip whole empty 8x8x8 chunks in one step, the voxel version of a hardware acceleration structure, with results identical to the one-level walk.

Read. Tai page, VTRACE Ray Unit and Stretch order (Why not a BVH). Tai_2 section 2.

Build.
1. A coarse occupancy grid of 8 x 4 x 8 chunks (256 bits) in registers, one bit per chunk, set when any cell in the chunk is non-air.
2. Keep it current. On every core store to the world region, set the chunk's bit when the stored type is non-air. Clearing on removal is optional. A stale 1 only costs speed, never correctness, so a periodic rebuild is fine.
3. Rebuild the grid after reset by scanning the world once, or have startup code write each block through the normal store path.
4. In VTRACE, when the next cell's chunk bit is 0, advance the ray to the chunk boundary in one step using the same tMax and tDelta arithmetic, then continue one cell at a time inside occupied chunks.
5. steps in the result still counts cells, not chunk jumps, so the kernel's fog and shading do not change. Add a separate debug counter of actual iterations.

Touch only. rtl/vtrace/*, rtl/mem/world_mem.sv (store snooping only), tb/vtrace/*.

Done when.
- The 10,000-ray testbench gives bit-identical result, hit_cell and t_hit with and without the coarse grid.
- Report average iterations per ray before and after on the demo world, and the fps change on the board.
```
