# ==============================================================================
# Usage Instructions:
#	make help					-view this menu
#	make sim <module name>		-run testbench simulation
#	make wave <module name>		-run testbench simulation and open waveform
#	make uart-smoke			    -run standalone UART integration tests (Verilator)
#	make clean					-remove simulation files
# ==============================================================================

ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))

$(eval $(ARGS):;@:)

.DEFAULT_GOAL := help

.PHONY: help

help:
	@awk 'NF==0{exit} /^#/{sub(/^# ?/,""); print}' Makefile | expand -t 4

sim:
	@fusesoc --cores-root . run --target sim_$(ARGS) socet:aft:USI:0.1.0

wave:
	@fusesoc --cores-root . run --target sim_$(ARGS) socet:aft:USI:0.1.0
	@gtkwave build/socet_aft_USI_0.1.0/sim_$(ARGS)-verilator/waveform.fst waves/$(ARGS).gtkw

UART_BUILD_DIR ?= build/usi_uart

.PHONY: uart-smoke
uart-smoke:
	verilator --binary --timing --assert --no-sched-zero-delay -Wno-TIMESCALEMOD --top-module usi_uart_tb --Mdir $(UART_BUILD_DIR) -f testbench/usi_uart.f
	$(UART_BUILD_DIR)/Vusi_uart_tb

clean:
	@rm -rf obj_dir/ build/
