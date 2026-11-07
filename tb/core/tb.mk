# Core testbenches. Run from the repo root through `make check`.
# datapath.sv loads "program.mem" relative to the working directory, so the
# binaries run inside tb/core.

CORE_RTL := $(wildcard rtl/core/*.sv) rtl/mem/memory_arr.sv rtl/soc/uart.sv
CORE_TBS := datapath_tb program_mem_tb

TB_TARGETS += $(addprefix tb-core-,$(CORE_TBS))

$(addprefix tb-core-,$(CORE_TBS)): tb-core-%:
	@mkdir -p $(OBJ)
	$(VERILATOR) $(VL_TB) --top-module $* -Mdir $(OBJ)/core_$* $(CORE_RTL) tb/core/$*.sv
	cd tb/core && ../../$(OBJ)/core_$*/V$*
