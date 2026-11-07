# Generate and read the 7-series MIG for the Arty A7-100T DDR3L (module
# mig_ddr3). Source this from a fpga/**/sources.tcl after fpga/build.tcl has
# created the in-memory project and set $root and $out.
#
# Project file provenance (never hand-tuned, D14):
#   mig_ddr3.prj = digilent_arty_mig.prj with only ModuleName (mig_ddr3) and
#   TargetFPGA (xc7a35ti-csg324/-1L -> xc7a100t-csg324/-1) changed.
#   digilent_arty_mig.prj, verbatim from Digilent:
#     https://github.com/Digilent/Arty/blob/c7c65d2d66b8b21c8ccd772440992ef01a7e1959/Resources/Arty_MIG_DDR3/mig.prj
#   digilent_vivado_boards_arty_a7_100_E0_mig.prj, verbatim from Digilent, kept
#   for reference only (AXI port, 100 MHz single-ended sys clock on E3):
#     https://github.com/Digilent/vivado-boards/blob/d8d43ed9f3f7e367ee3de82782ed601d88305677/new/board_files/arty-a7-100/E.0/1.1/mig.prj
#
# Resulting controller: native UI, 4:1 PHY, tCK 3000 ps (333 MHz DDR, ui_clk
# 83.33 MHz), sys_clk_i 166.67 MHz and clk_ref_i 200 MHz both "No Buffer"
# (driven by rtl/ddr/ddr_clk.sv), sys_rst active low, app_addr 28 bits in
# 16-bit words, 128-bit app data. The IP's own XDC places and standardizes the
# ddr3_* pins, so the top level only needs ports with those names.

set mig_dir [file join $out ip]
file delete -force [file join $mig_dir mig_ddr3]
file mkdir $mig_dir
create_ip -name mig_7series -vendor xilinx.com -library ip -module_name mig_ddr3 -dir $mig_dir
file copy -force [file join $root rtl/ddr/mig/mig_ddr3.prj] [file join $mig_dir mig_ddr3 mig_ddr3.prj]
set_property CONFIG.XML_INPUT_FILE mig_ddr3.prj [get_ips mig_ddr3]
set_property GENERATE_SYNTH_CHECKPOINT false [get_files mig_ddr3.xci]
generate_target {synthesis implementation} [get_ips mig_ddr3]
