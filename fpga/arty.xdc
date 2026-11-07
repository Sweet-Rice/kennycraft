## Arty A7-100T (xc7a100tcsg324-1) constraints for the main KennyCraft top.
## Pins from the Digilent Arty A7-100 master XDC. Sections are owned per the
## Stage 0 prompts: P1 adds VGA (and clock) lines, P2b adds DDR3 lines.
##
## Board mapping:
##   clk          -> 100 MHz system clock
##   ck_rst       -> RESET button (active low)
##   uart_rxd_out -> USB-UART bridge receiver; this is the FPGA's transmit line
##   led          -> LD4, driven by illegal_out

set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports clk];          #IO_L12P_T1_MRCC_35 Sch=gclk[100]
create_clock -period 10.000 -name sys_clk [get_ports clk];

set_property -dict { PACKAGE_PIN C2  IOSTANDARD LVCMOS33 } [get_ports ck_rst];       #IO_L16P_T2_35 Sch=ck_rst
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports uart_rxd_out]; #IO_L19N_T3_VREF_16 Sch=uart_rxd_out
set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports led];          #IO_L24N_T3_35 Sch=led[4]

## Required for write_bitstream on Artix-7; otherwise DRC fails on bank voltage.
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
