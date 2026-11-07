# fpga-tools MCP entry point (the MCP runs build/build.tcl). The real flow is
# fpga/build.tcl; set KC_TARGET in the MCP server environment to pick a target.
source [file join [file dirname [file normalize [info script]]] .. fpga build.tcl]
