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

## --- VGA (P1) ---
## Digilent Pmod VGA on two adjacent Pmod headers: J1 (R0-R3, B0-B3) on JB,
## J2 (G0-G3, HS, VS) on JC. Pins from Digilent's official Arty A7-100 Pmod VGA
## demo, copied in fpga/ref/Arty-A7-100-Pmod-VGA.xdc (source URL in its header).
## TODO(P1): confirm the header pair on the board. Assumed JB (J1) + JC (J2).
set_property -dict { PACKAGE_PIN E15 IOSTANDARD LVCMOS33 } [get_ports {vga_r[0]}]; #IO_L11P_T1_SRCC_15 Sch=jb_p[1]
set_property -dict { PACKAGE_PIN E16 IOSTANDARD LVCMOS33 } [get_ports {vga_r[1]}]; #IO_L11N_T1_SRCC_15 Sch=jb_n[1]
set_property -dict { PACKAGE_PIN D15 IOSTANDARD LVCMOS33 } [get_ports {vga_r[2]}]; #IO_L12P_T1_MRCC_15 Sch=jb_p[2]
set_property -dict { PACKAGE_PIN C15 IOSTANDARD LVCMOS33 } [get_ports {vga_r[3]}]; #IO_L12N_T1_MRCC_15 Sch=jb_n[2]
set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 } [get_ports {vga_b[0]}]; #IO_L23P_T3_FOE_B_15 Sch=jb_p[3]
set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports {vga_b[1]}]; #IO_L23N_T3_FWE_B_15 Sch=jb_n[3]
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports {vga_b[2]}]; #IO_L24P_T3_RS1_15 Sch=jb_p[4]
set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports {vga_b[3]}]; #IO_L24N_T3_RS0_15 Sch=jb_n[4]
set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 } [get_ports {vga_g[0]}]; #IO_L20P_T3_A08_D24_14 Sch=jc_p[1]
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports {vga_g[1]}]; #IO_L20N_T3_A07_D23_14 Sch=jc_n[1]
set_property -dict { PACKAGE_PIN V10 IOSTANDARD LVCMOS33 } [get_ports {vga_g[2]}]; #IO_L21P_T3_DQS_14 Sch=jc_p[2]
set_property -dict { PACKAGE_PIN V11 IOSTANDARD LVCMOS33 } [get_ports {vga_g[3]}]; #IO_L21N_T3_DQS_A06_D22_14 Sch=jc_n[2]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports vga_hs];      #IO_L22P_T3_A05_D21_14 Sch=jc_p[3]
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports vga_vs];      #IO_L22N_T3_A04_D20_14 Sch=jc_n[3]
## The 50 MHz core and 25 MHz pixel clocks come from the MMCM in
## rtl/display/clk_gen.sv; Vivado derives both from sys_clk above.
## --- end VGA (P1) ---

## Required for write_bitstream on Artix-7; otherwise DRC fails on bank voltage.
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
