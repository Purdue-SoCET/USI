# make sim {module name}
# Example: make sim datapath
# File -> write save file or use ctrl+s to save waveform format to waves/{module name}.gtkw

ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))

$(eval $(ARGS):;@:)

sim:
	fusesoc --cores-root . run --target sim_$(ARGS) socet:aft:USI:0.1.0
	gtkwave build/socet_aft_USI_0.1.0/sim_$(ARGS)-verilator/waveform.fst waves/$(ARGS).gtkw