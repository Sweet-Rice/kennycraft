/* Linker script for the tb/core test programs (until Bennett's kc.ld lands).
   Code at the reset vector 0x0000_0000 in imem; data from 0x1000_0100 in dmem,
   above the camera block and the reserved shared state (Shared page, Data
   memory layout). __bss_start/__bss_end bound .bss for the wiki crt0. The
   RISC-V GCC here links with --gc-sections by default, hence the KEEPs. */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    IMEM (rx) : ORIGIN = 0x00000000, LENGTH = 32K
    DMEM (rw) : ORIGIN = 0x10000100, LENGTH = 32K - 0x100
}

SECTIONS {
    .text : { KEEP(*(.text.start)) *(.text*) } > IMEM
    .data : { KEEP(*(.rodata*)) KEEP(*(.data*)) KEEP(*(.sdata*)) } > DMEM
    .bss (NOLOAD) : {
        . = ALIGN(4);
        __bss_start = .;
        KEEP(*(.sbss*)) KEEP(*(.bss*))
        . = ALIGN(4);
        __bss_end = .;
    } > DMEM
    /DISCARD/ : { *(.note*) *(.riscv.attributes) *(.comment) }
}
