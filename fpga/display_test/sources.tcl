# Standalone display pattern bitstream (KC_TARGET=display_test). Sourced by
# fpga/build.tcl from the repo root.
read_verilog -sv [glob rtl/display/*.sv] fpga/display_test/display_test.sv
read_xdc fpga/arty.xdc
set top display_test
