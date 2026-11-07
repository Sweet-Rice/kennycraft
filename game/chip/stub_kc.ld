/* stub_kc.ld — Bennett's kc.ld + a PROPOSED GPUMEM region for the rasterizer (mesh pool and
   command lists). 0x7000_0000 currently "reads 0 and drops writes" (issue #2): needs Tai. */
ENTRY(_start)
MEMORY {
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 32K
    DMEM (rw)  : ORIGIN = 0x10000100, LENGTH = 0x5F00   /* up to the lane stacks at 0x1000_6000 */
    GPUMEM (rw): ORIGIN = 0x70000000, LENGTH = 256K     /* PROPOSED: mesh pool + command lists (rasterizer) */
}
SECTIONS {
    .text : { *(.text.start) *(.text*) } > IMEM
    .rodata : { *(.rodata*) *(.srodata*) } > DMEM
    .data : { *(.data*) *(.sdata*) } > DMEM
    .gpumem (NOLOAD) : { *(.gpumem*) } > GPUMEM
    .bss : { __bss_start = .; *(.bss*) *(.sbss*) *(COMMON) . = ALIGN(4); __bss_end = .; } > DMEM
}
