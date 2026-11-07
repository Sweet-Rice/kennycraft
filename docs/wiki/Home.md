# KennyCraft

An 8-lane SIMD GPU grown from Tai's multi-cycle RV32I core, running a voxel Minecraft on one Arty A7-100T. HackUTD 2026, Nov 7–8.

| Page | Owner | What's in it |
| --- | --- | --- |
| [[Shared]] | All | Overview, decisions D1–D15, stages, interfaces (memory map, MMIO, chunks), verification, schedule and risks |
| [[Tai]] | Tai | CPU core, GPU core, VTRACE, memory and display, DDR3 chunk store |
| [[Tai_2]] | Tai | ISA v1.0, masking semantics v1.0, agent prompts P0–P10 |
| [[Kenny]] | Kennedy | Engine, tile rendering kernel, game loop, chunk API, pitch |
| [[Bennett]] | Bennett | Toolchain, gpu.h, simulator, Verilator harness, make targets, arena allocator |

Tai_2 wins wherever pages disagree. Frozen sections change only through a change request in [[Shared]] → Decisions.

Live source: [KennyCraft Design Doc](https://claude.ai/artifact/Y86Tmar6oFqLZj4tQnExi1). These pages are a snapshot exported from it.
