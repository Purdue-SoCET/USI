# USI
Universal Serial Interface by Digital Design Subteam

### Modules
- top.sv: top level
- control_unit.sv: control unit that chooses protocol and control timing
- data_buffer.sv: split data buffer for full-duplex (size needs to be changed to a paramater)
- datapath.sv: shift registers for data in and out
- reg_map.sv: register map for configuring the USI (see docs folder)
- wrapper.sv: FPGA wrapper for validation
- Individual protocol modules are used

### Testbenching
If you are using gtkwave, you can run "make sim {module name}" and it will save and load in the waves folder. More info in the Makefile.

### Future Plans
- Fix I2C (currently not supported in the control unit and probably need to make a few changes in the datapath: use the START state for the address + R/W bit and implement inout logic)
- Top level verification
- FPGA validation

### Email jklutho@purdue.edu if you have questions
