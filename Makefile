# KennyCraft top-level make.
#
# `make check` runs every target registered by a tb/<area>/tb.mk fragment.
# Each fragment appends its testbench and -Wall lint targets to TB_TARGETS,
# so areas never edit each other's rules. Bennett's sim, vl, board and keys
# targets (Bennett wiki page, Make targets) land here as they come up.

VERILATOR ?= verilator
VL_TB     ?= --binary --timing --build-jobs 0 --verilate-jobs 1 -Wno-fatal
VL_LINT   ?= --lint-only -Wall
OBJ       := obj_dir

TB_TARGETS :=
RISCV_PREFIX ?= $(CROSS)
include $(wildcard tb/*/tb.mk)

include mk/bench.mk

.PHONY: check clean $(TB_TARGETS)

check: $(TB_TARGETS) check-bench
	@echo "make check: $(words $(TB_TARGETS)) target(s) passed"

clean:
	rm -rf $(OBJ)
