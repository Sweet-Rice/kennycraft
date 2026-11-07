# KennyCraft

An 8-lane SIMD GPU grown from a multi-cycle RV32I core, running a voxel Minecraft on one Arty A7-100T. HackUTD 2026.

The design doc is the [GitHub wiki](https://github.com/Sweet-Rice/kennycraft/wiki). Tai_2 wins wherever pages disagree.

## Layout

| Path | What |
| --- | --- |
| `rtl/` | SystemVerilog (`core/`, `soc/`, `mem/`, `display/`, `ddr/`, `top.sv`) |
| `tb/` | Verilator testbenches; each `tb/<area>/tb.mk` registers its targets with `make check` |
| `fpga/` | `arty.xdc`, `build.tcl` (non-project Vivado flow), per-target `sources.tcl` |
| `build/` | `build.tcl` entry and `summarize.py` for the fpga-tools MCP build contract |
| `prompts/` | Stage agent prompts (preamble plus prompt, from Tai_2) |

## Checks

```sh
make check                                     # every registered Verilator testbench and lint target
vivado -mode batch -source fpga/build.tcl      # KC_TARGET=<name> picks fpga/<name>/sources.tcl
```

## Credits

The Stage 0 CPU core is inspired by Tai's [RISC-V-Core-progression](https://github.com/Sweet-Rice/RISC-V-Core-progression) multicycle RV32I core (D11).

## Software

Put xPack `riscv-none-elf-gcc` 12+ on `PATH` (fallback: `riscv64-unknown-elf-gcc`).
Run `make sw` or `make sw PROG="sw/game.c sw/kernel.c"` from the repository root.
Outputs are under ignored `out/`: ELF, map, disassembly, and two 8192-word hex images.
The build probes `rv32i_zmmul`, falling back to `rv32im`. Avoid division/remainder in chip code.
The data image includes the 0x100-byte reserved shared-state prefix.

`sw/gpu.h`, `sw/kc.ld`, `sw/crt0.S`, and `sw/arena.{h,c}` are verbatim Bennett wiki sources.
The default integer-only bring-up program displays a gradient and W/A/S/D-controlled square.
UART_STATUS bit 1 means TX **busy**, so transmission waits for it to clear.

The arena is linked into every chip program with `KC_CHIP`; game logic must use it only with mask 1.

`make arena-host` compiles the same arena without `KC_CHIP` using host C11.
`arena_reset()` preserves the boot-time high-water mark. Requests round up to 4 bytes;
overflow aborts on the host and lights LEDs 1010 then halts on the chip.

## Verilator harness

Install Verilator, SDL3 and pkg-config (`brew install verilator sdl3 pkg-config`).
`make vl-fixture` builds `out/vl/kcvl` and opens a 640×480 SDL3 window.
For a finite headless run:

```sh
make vl-fixture RUN_ARGS="--headless --frames 5 --keys tb/harness/fixture/keys.txt"
```

Every swap writes `out/frames/frame_00001.png`, etc.; subsequent runs remove only
`frame_*.png` in the selected `--png-dir`. PNGs use native 320×240 or 160×120 sizes.
The window uses nearest-neighbor scaling. W/A/S/D, arrows, Space, J/K and 1–9
produce the wiki down/up bytes; Escape/window close exits. Live input is held
until a frame boundary. `--record FILE` records those boundaries; `--keys FILE`
replays `<frame> 0x<byte>` entries (`#` comments supported; frame 0 is after reset).

Run control: `--frames N`, `--max-cycles N`, `--expect-pass`, and
`--expect-err NAME[@PC]`. Exit codes: 0 success/quit, 1 failed expectation,
2 timeout, 3 unexpected hardware ERR, 4 jump-to-self halt, 5 setup/usage.
`--trace FILE` needs retire probes; `--expect-err` needs ERR probes. The no-CPU
fixture deliberately provides neither. `--vcd FILE --vcd-window START:END`
captures an inclusive core-cycle range, excluding the 20 reset cycles.

`--palette-hex FILE` loads RGB444 readmemh entries before observed palette writes.
All RTL names are isolated in ports/probes headers and Verilator configuration.
Production binding awaits the published RTL top and its confirmed hierarchy.
