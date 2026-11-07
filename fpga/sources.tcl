# Sources for the main KennyCraft bitstream (KC_TARGET=top). Sourced by
# fpga/build.tcl from the repo root. Stage 0 interim: kc_soc on the board
# clock with the hello-world program; P3 wires in clk_gen, display and DDR3.
read_verilog -sv rtl/kc_isa_pkg.sv
read_verilog -sv [glob rtl/core/*.sv] [glob rtl/mem/*.sv] [glob rtl/soc/*.sv] rtl/top.sv
read_mem tb/core/program.mem
read_xdc fpga/arty.xdc
set top top
