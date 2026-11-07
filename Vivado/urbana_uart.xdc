# 100 MHz system clock, our clock wizard will generate 25Mhz
set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33} [get_ports clk_100mhz]
create_clock -period 10.000 -name clk_100mhz [get_ports clk_100mhz]

# BTN0 — active-high reset button
set_property -dict {PACKAGE_PIN J2 IOSTANDARD LVCMOS25} [get_ports btn_reset]

# USB-UART connection
set_property -dict {PACKAGE_PIN B16 IOSTANDARD LVCMOS33} [get_ports uart_rx]
set_property -dict {PACKAGE_PIN A16 IOSTANDARD LVCMOS33} [get_ports uart_tx]

# status LEDs
set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS33} [get_ports led_heartbeat]
set_property -dict {PACKAGE_PIN C14 IOSTANDARD LVCMOS33} [get_ports led_ready]
set_property -dict {PACKAGE_PIN D14 IOSTANDARD LVCMOS33} [get_ports led_error]

set_property -dict {DRIVE 8 SLEW SLOW} \
    [get_ports {led_heartbeat led_ready led_error uart_tx}]

# initialize four onboard seven segment displays
set_property -dict {PACKAGE_PIN G6 IOSTANDARD LVCMOS25} [get_ports {display_digit_enable[0]}]
set_property -dict {PACKAGE_PIN H6 IOSTANDARD LVCMOS25} [get_ports {display_digit_enable[1]}]
set_property -dict {PACKAGE_PIN C3 IOSTANDARD LVCMOS25} [get_ports {display_digit_enable[2]}]
set_property -dict {PACKAGE_PIN B3 IOSTANDARD LVCMOS25} [get_ports {display_digit_enable[3]}]

# Segment outputs are active low: 0 lights the segment.
# Bit order: [0]=A, [1]=B, [2]=C, [3]=D,
#            [4]=E, [5]=F, [6]=G, [7]=decimal point.
set_property -dict {PACKAGE_PIN E6 IOSTANDARD LVCMOS25} [get_ports {display_segments[0]}]
set_property -dict {PACKAGE_PIN B4 IOSTANDARD LVCMOS25} [get_ports {display_segments[1]}]
set_property -dict {PACKAGE_PIN D5 IOSTANDARD LVCMOS25} [get_ports {display_segments[2]}]
set_property -dict {PACKAGE_PIN C5 IOSTANDARD LVCMOS25} [get_ports {display_segments[3]}]
set_property -dict {PACKAGE_PIN D7 IOSTANDARD LVCMOS25} [get_ports {display_segments[4]}]
set_property -dict {PACKAGE_PIN D6 IOSTANDARD LVCMOS25} [get_ports {display_segments[5]}]
set_property -dict {PACKAGE_PIN C4 IOSTANDARD LVCMOS25} [get_ports {display_segments[6]}]
set_property -dict {PACKAGE_PIN B5 IOSTANDARD LVCMOS25} [get_ports {display_segments[7]}]

# ============================================================
# FPGA configuration voltage
# ============================================================
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# ============================================================
# Timing exceptions
# ============================================================

# BTN0 asynchronously asserts reset; the synchronizer clocks release.
set_false_path -from [get_ports btn_reset]

# These outputs have no synchronous external receiver.
set_false_path -to [get_ports {led_heartbeat led_ready led_error uart_tx}]

# Any UART RX timing exception should target only the first
# synchronizer stage and use the actual synthesized register name.
