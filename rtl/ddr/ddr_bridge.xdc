## Clock-crossing constraints for rtl/ddr/ddr_bridge.sv, instantiated as
## u_bridge. Read this file in every sources.tcl that builds the bridge.
##
## The core clock and the MIG ui_clk (clk_pll_i, MIG MMCM feedback) both derive
## from the 100 MHz input, so Vivado would time their crossings as synchronous
## paths. They only meet in the bridge's XPM FIFOs and calibration
## synchronizer, so the two clocks are asynchronous groups. fpga/build.tcl's
## non-project flow does not load the XPM macros' own constraint scripts
## (report_exceptions / report_bus_skew show none), so the gray-pointer bus
## skew limits that xpm_cdc_gray would add are restated here: at most the
## faster clock's period (ui_clk, 12 ns).

set_clock_groups -asynchronous \
  -group [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *u_bridge/u_cmd_fifo/*wr_pntr_cdc_inst/src_gray_ff_reg*/C}]] \
  -group [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *u_ddr3_infrastructure/gen_mmcm.mmcm_i/CLKFBOUT}]]

set_bus_skew -from [get_cells -hier -filter {NAME =~ *u_bridge/u_cmd_fifo/*wr_pntr_cdc_inst/src_gray_ff_reg*}]   -to [get_cells -hier -filter {NAME =~ *u_bridge/u_cmd_fifo/*wr_pntr_cdc_inst/dest_graysync_ff_reg[0]*}]   12.0
set_bus_skew -from [get_cells -hier -filter {NAME =~ *u_bridge/u_cmd_fifo/*rd_pntr_cdc_inst/src_gray_ff_reg*}]   -to [get_cells -hier -filter {NAME =~ *u_bridge/u_cmd_fifo/*rd_pntr_cdc_inst/dest_graysync_ff_reg[0]*}]   12.0
set_bus_skew -from [get_cells -hier -filter {NAME =~ *u_bridge/u_wdata_fifo/*wr_pntr_cdc_inst/src_gray_ff_reg*}] -to [get_cells -hier -filter {NAME =~ *u_bridge/u_wdata_fifo/*wr_pntr_cdc_inst/dest_graysync_ff_reg[0]*}] 12.0
set_bus_skew -from [get_cells -hier -filter {NAME =~ *u_bridge/u_wdata_fifo/*rd_pntr_cdc_inst/src_gray_ff_reg*}] -to [get_cells -hier -filter {NAME =~ *u_bridge/u_wdata_fifo/*rd_pntr_cdc_inst/dest_graysync_ff_reg[0]*}] 12.0
set_bus_skew -from [get_cells -hier -filter {NAME =~ *u_bridge/u_rdata_fifo/*wr_pntr_cdc_inst/src_gray_ff_reg*}] -to [get_cells -hier -filter {NAME =~ *u_bridge/u_rdata_fifo/*wr_pntr_cdc_inst/dest_graysync_ff_reg[0]*}] 12.0
set_bus_skew -from [get_cells -hier -filter {NAME =~ *u_bridge/u_rdata_fifo/*rd_pntr_cdc_inst/src_gray_ff_reg*}] -to [get_cells -hier -filter {NAME =~ *u_bridge/u_rdata_fifo/*rd_pntr_cdc_inst/dest_graysync_ff_reg[0]*}] 12.0
