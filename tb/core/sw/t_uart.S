/* t_uart: echo bytes (Shared page, Verification). The program first sleeps
   for 15,000 cycles (300 us) by polling CYCLES while the testbench sends a
   burst of 17 bytes, so the 16-byte RX FIFO fills and the 17th byte is
   dropped. Then it echoes every byte: wait for UART_STATUS.0 (RX available),
   read UART_RX, wait while UART_STATUS.1 (TX busy), store the byte to UART_TX. */
#include "kc_test.h"

    .section .text.start
    .globl _start
_start:
    li    s0, MMIO_BASE
    li    s1, 15000
1:  lw    t0, MMIO_CYCLES(s0)
    bltu  t0, s1, 1b
echo:
    lw    t0, MMIO_UART_STATUS(s0)
    andi  t0, t0, 1
    beqz  t0, echo
    lw    t1, MMIO_UART_RX(s0)
2:  lw    t0, MMIO_UART_STATUS(s0)
    andi  t0, t0, 2
    bnez  t0, 2b
    sb    t1, MMIO_UART_TX(s0)
    j     echo
