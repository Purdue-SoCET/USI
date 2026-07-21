# ==============================================================================
# Usage Instructions:
#	make help					-view this menu
#	make sim <module name>		-run testbench simulation
#	make wave <module name>		-run testbench simulation and open waveform
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

clean:
	@rm -rf obj_dir/ build/