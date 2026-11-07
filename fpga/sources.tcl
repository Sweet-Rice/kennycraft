# Sources for the main KennyCraft bitstream (KC_TARGET=top). Sourced by
# fpga/build.tcl from the repo root. Stage 0 still builds the imported
# multicycle core with its hello-world program; P3 wires in display and SoC.
read_verilog -sv [glob rtl/core/*.sv] rtl/mem/memory_arr.sv rtl/soc/uart.sv rtl/top.sv
read_mem tb/core/program.mem
read_xdc fpga/arty.xdc
set top top
