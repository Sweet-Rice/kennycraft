# KennyCraft non-project Vivado build.
#
#   KC_TARGET   which design to build (default "top"). "top" reads
#               fpga/sources.tcl; any other name reads fpga/<name>/sources.tcl.
#               A sources.tcl reads every RTL, IP and constraint file and sets
#               the variable `top` to the top module name.
#   FPGA_BUILD_OUT  output directory (the fpga-tools MCP sets it per job;
#               defaults to build/out/<target> for manual runs).
#
# Run from the repo root:  vivado -mode batch -source fpga/build.tcl
# The MCP enters through build/build.tcl, which sources this file.

set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
set part xc7a100tcsg324-1
set target [expr {[info exists ::env(KC_TARGET)] && $::env(KC_TARGET) ne "" ? $::env(KC_TARGET) : "top"}]
set out [expr {[info exists ::env(FPGA_BUILD_OUT)] ? $::env(FPGA_BUILD_OUT) : "$root/build/out/$target"}]
file mkdir $out

if {[info exists ::env(FPGA_ILA_PROBES_JSON)] && $::env(FPGA_ILA_PROBES_JSON) ni {{} {[]}}} {
    error "ILA probes are not supported by fpga/build.tcl yet"
}

create_project -in_memory -part $part
set sources [expr {$target eq "top" ? "fpga/sources.tcl" : "fpga/$target/sources.tcl"}]
if {![file exists $sources]} { error "No sources script for target '$target': $sources" }
set top ""
source $sources
if {$top eq ""} { error "$sources did not set top" }

synth_design -top $top -part $part
if {[info exists ::env(FPGA_FAIL_TIMING)] && $::env(FPGA_FAIL_TIMING)} {
    # Acceptance-only: every target's 100 MHz board clock port is `clk` (E3).
    create_clock -name sys_clk -period 0.5 [get_ports clk]
}
opt_design
place_design
phys_opt_design
route_design

report_timing_summary -report_unconstrained -check_timing_verbose -file $out/timing.rpt
report_utilization -file $out/utilization.rpt
check_timing -verbose -file $out/check_timing.rpt
write_checkpoint -force $out/routed.dcp
write_bitstream -force $out/top.bit

set log $out/build.log
if {![file exists $log]} {
    # Manual runs have no MCP log; summarize.py still needs one.
    close [open $log a]
}
exec python3 -I build/summarize.py $out false
puts "KC_BUILD_DONE target=$target out=$out"
