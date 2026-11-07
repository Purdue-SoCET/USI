# 100 MHz oscillator. The Clock Wizard supplies the internal 25 MHz clock.
set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33} [get_ports clk_100mhz]
create_clock -period 10.000 -name clk_100mhz [get_ports clk_100mhz]

# BTN0, active-high user reset
set_property -dict {PACKAGE_PIN J2 IOSTANDARD LVCMOS25} [get_ports btn_reset]

# PMODA connections matching the user's wiring to Proton SPI1
set_property -dict {PACKAGE_PIN F14 IOSTANDARD LVCMOS33} [get_ports spi_mosi]
set_property -dict {PACKAGE_PIN F15 IOSTANDARD LVCMOS33} [get_ports spi_cs_n]
set_property -dict {PACKAGE_PIN H13 IOSTANDARD LVCMOS33} [get_ports spi_sclk]
set_property -dict {PACKAGE_PIN H14 IOSTANDARD LVCMOS33} [get_ports spi_miso]
set_property -dict {DRIVE 8 SLEW SLOW} [get_ports {spi_mosi spi_cs_n spi_sclk}]

# LD0 heartbeat, LD1 exact response matched, LD2 failure
set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS33} [get_ports led_heartbeat]
set_property -dict {PACKAGE_PIN C14 IOSTANDARD LVCMOS33} [get_ports led_ready]
set_property -dict {PACKAGE_PIN D14 IOSTANDARD LVCMOS33} [get_ports led_error]
set_property -dict {DRIVE 8 SLEW SLOW} [get_ports {led_heartbeat led_ready led_error}]

# Display 0 digit enables, active low
set_property -dict {PACKAGE_PIN G6 IOSTANDARD LVCMOS25} [get_ports {display_digit_enable[0]}]
set_property -dict {PACKAGE_PIN H6 IOSTANDARD LVCMOS25} [get_ports {display_digit_enable[1]}]
set_property -dict {PACKAGE_PIN C3 IOSTANDARD LVCMOS25} [get_ports {display_digit_enable[2]}]
set_property -dict {PACKAGE_PIN B3 IOSTANDARD LVCMOS25} [get_ports {display_digit_enable[3]}]

# Display segments [0:7] are A,B,C,D,E,F,G,DP, active low
set_property -dict {PACKAGE_PIN E6 IOSTANDARD LVCMOS25} [get_ports {display_segments[0]}]
set_property -dict {PACKAGE_PIN B4 IOSTANDARD LVCMOS25} [get_ports {display_segments[1]}]
set_property -dict {PACKAGE_PIN D5 IOSTANDARD LVCMOS25} [get_ports {display_segments[2]}]
set_property -dict {PACKAGE_PIN C5 IOSTANDARD LVCMOS25} [get_ports {display_segments[3]}]
set_property -dict {PACKAGE_PIN D7 IOSTANDARD LVCMOS25} [get_ports {display_segments[4]}]
set_property -dict {PACKAGE_PIN D6 IOSTANDARD LVCMOS25} [get_ports {display_segments[5]}]
set_property -dict {PACKAGE_PIN C4 IOSTANDARD LVCMOS25} [get_ports {display_segments[6]}]
set_property -dict {PACKAGE_PIN B5 IOSTANDARD LVCMOS25} [get_ports {display_segments[7]}]

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# BTN0 asynchronously asserts the reset synchronizer.
set_false_path -from [get_ports btn_reset]

# Human-visible outputs have no synchronous external receiver.
set_false_path -to [get_ports {led_heartbeat led_ready led_error display_segments[*] display_digit_enable[*]}]

# Keep SPI timing paths visible. SPI interface timing and the MISO capture
# stages should be reviewed using the final peer and routed timing reports.
