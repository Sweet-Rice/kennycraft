## Standalone DDR3 test (KC_TARGET=ddr_test), Arty A7-100T.
## The ddr3_* pins, their I/O standards and the bank 34 internal VREF come
## from the MIG IP's own XDC (rtl/ddr/mig/mig_ddr3.tcl).

set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports clk];          #IO_L12P_T1_MRCC_35 Sch=gclk[100]
create_clock -period 10.000 -name sys_clk [get_ports clk];

set_property -dict { PACKAGE_PIN C2  IOSTANDARD LVCMOS33 } [get_ports ck_rst];       #IO_L16P_T2_35 Sch=ck_rst
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports uart_rxd_out]; #IO_L19N_T3_VREF_16 Sch=uart_rxd_out
set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports {led[0]}];     #IO_L24N_T3_35 Sch=led[4]
set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports {led[1]}];     #IO_25_35 Sch=led[5]
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports {led[2]}];     #IO_L24P_T3_A01_D17_14 Sch=led[6]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports {led[3]}];     #IO_L24N_T3_A00_D16_14 Sch=led[7]

## Slow, asynchronous board I/O: button in, LEDs and UART out.
set_false_path -from [get_ports ck_rst]
set_false_path -to [get_ports {led[*]}]
set_false_path -to [get_ports uart_rxd_out]

## The 50 MHz core clock and the MIG ui_clk only meet in ddr_bridge's XPM
## FIFOs and synchronizer. Both derive from the 100 MHz input, so without this
## Vivado times them as synchronous (4 ns requirement). The XPM gray-pointer
## set_bus_skew constraints still apply. Same lines as the DDR3 block of
## fpga/arty.xdc.
set_clock_groups -asynchronous \
  -group [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *u_bridge/clk}]] \
  -group [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *u_bridge/ui_clk}]]

set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
