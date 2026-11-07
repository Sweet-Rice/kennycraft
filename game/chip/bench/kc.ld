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
