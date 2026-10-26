# Real Digital Urbana V2I1 master constraints:
# https://www.realdigital.org/downloads/1f07b1146ec59e165634a5b6c782a17d.txt
# UART net names in the master file use the USB bridge's perspective:
# UART_TXD/B16 is FPGA RX; UART_RXD/A16 is FPGA TX.

set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33} [get_ports clk_100mhz]
create_clock -period 10.000 -name clk_100mhz [get_ports clk_100mhz]
set_property -dict {PACKAGE_PIN J2 IOSTANDARD LVCMOS25} [get_ports btn_reset]
set_property -dict {PACKAGE_PIN B16 IOSTANDARD LVCMOS33} [get_ports uart_rx]
set_property -dict {PACKAGE_PIN A16 IOSTANDARD LVCMOS33} [get_ports uart_tx]

set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS33} [get_ports led_heartbeat]
set_property -dict {PACKAGE_PIN C14 IOSTANDARD LVCMOS33} [get_ports led_ready]
set_property -dict {PACKAGE_PIN D14 IOSTANDARD LVCMOS33} [get_ports led_error]
set_property -dict {DRIVE 8 SLEW SLOW} [get_ports {led_heartbeat led_ready led_error uart_tx}]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# The reset button feeds only the asynchronous reset-synchronizer presets.
set_false_path -from [get_ports btn_reset]
# UART TX and the human-visible LEDs have no external 100 MHz capture clock.
set_false_path -to [get_ports {led_heartbeat led_ready led_error uart_tx}]
# The external UART RX -> first-flop-D exception and ASYNC_REG properties are
# applied after synthesis by build.tcl, where the exact cells can be checked.
