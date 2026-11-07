# Standalone DDR3 chunk store test (KC_TARGET=ddr_test). Sourced by
# fpga/build.tcl from the repo root with $root and $out set.
read_verilog -sv {
  rtl/ddr/ddr_clk.sv
  rtl/ddr/ddr_bridge.sv
  rtl/ddr/chunk_engine.sv
  fpga/ddr_test/ddr_test_uart_tx.sv
  fpga/ddr_test/ddr_test_top.sv
}
source rtl/ddr/mig/mig_ddr3.tcl
read_xdc fpga/ddr_test/ddr_test.xdc
read_xdc rtl/ddr/ddr_bridge.xdc
set top ddr_test_top
