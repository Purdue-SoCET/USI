namespace eval ::urbana {
    variable script_dir [file dirname [file normalize [info script]]]

    proc usage {} {
        puts {Usage: vivado -mode batch -nojournal -nolog -source Vivado/build.tcl}
        puts {              -tclargs [-target blink|uart] [-part xc7s50csga324-1]}
        puts {                       [-out DIRECTORY] [-bus-if FILE] [-bus-source FILE] [-help]}
        puts {Default target: blink; default output: <repo>/build/urbana/<target>}
        puts {UART defaults to source/bus_protocol_if.sv. -bus-if selects an alternate interface.}
        puts {Repeat -bus-source for any package/dependency files required before that interface.}
        puts {Relative file/output paths are resolved from the calling working directory.}
    }

    proc main {arguments} {
        variable script_dir
        set repo_dir [file normalize [file join $script_dir ..]]
        set part xc7s50csga324-1
        set target blink
        set output_dir ""
        set bus_if_file ""
        set bus_sources {}

        for {set i 0} {$i < [llength $arguments]} {incr i} {
            set option [lindex $arguments $i]
            switch -- $option {
                -help - --help {
                    usage
                    return
                }
                -part - -out - -target - -bus-if - -bus-source {
                    incr i
                    if {$i >= [llength $arguments] || [lindex $arguments $i] eq ""} {
                        error "Missing value for $option; use -help for usage."
                    }
                    set value [lindex $arguments $i]
                    switch -- $option {
                        -part { set part $value }
                        -target { set target $value }
                        -out { set output_dir [file normalize $value] }
                        -bus-if { set bus_if_file [file normalize $value] }
                        -bus-source { lappend bus_sources [file normalize $value] }
                    }
                }
                default {
                    error "Unknown option '$option'; use -help for usage."
                }
            }
        }

        if {$target ni {blink uart}} {
            error "Unknown target '$target'; choose blink or uart."
        }
        if {$target eq "blink" && ($bus_if_file ne "" || [llength $bus_sources] != 0)} {
            error "Bus interface options apply only to -target uart."
        }
        if {[llength $bus_sources] != 0 && $bus_if_file eq ""} {
            error "-bus-source requires -bus-if so that exactly one interface is selected."
        }
        if {$output_dir eq ""} {
            set output_dir [file join $repo_dir build urbana $target]
        }
        if {![string match "xc7s50csga324-*" $part]} {
            error "These pin constraints require an XC7S50-CSGA324 part, got '$part'."
        }
        if {[llength [info commands synth_design]] == 0} {
            error "Run this script inside Vivado. Plain tclsh supports -help only."
        }
        if {[llength [get_parts -quiet $part]] != 1} {
            error "Part '$part' is unavailable. Check the part name and Spartan-7 device installation."
        }

        if {$target eq "blink"} {
            set top urbana_blink
            set rtl_files [list [file join $repo_dir fpga urbana_blink.sv]]
            set xdc_file [file join $repo_dir fpga urbana_blink.xdc]
        } else {
            set top urbana_usi_uart_top
            set xdc_file [file join $script_dir urbana_uart.xdc]
            if {$bus_if_file eq ""} {
                set bus_if_file [file join $repo_dir source bus_protocol_if.sv]
                puts "INFO: Using repository production bus interface; the SoC bus adapter is not exercised."
            } else {
                puts "INFO: Using supplied bus interface: $bus_if_file"
            }
            set rtl_files [concat $bus_sources [list $bus_if_file]]
            foreach name {usi_datapath split_fifo shift_register register_map control_unit uart spi USI} {
                lappend rtl_files [file join $repo_dir source ${name}.sv]
            }
            lappend rtl_files [file join $script_dir usi_bus_exerciser.sv] \
                [file join $script_dir urbana_usi_uart_top.sv]
        }
        foreach input_file [concat $rtl_files [list $xdc_file]] {
            if {![file isfile $input_file]} {
                error "Required input is missing: $input_file"
            }
        }

        file mkdir $output_dir
        set previous_dir [pwd]
        set result_code [catch {
            cd $output_dir
            create_project -in_memory -part $part
            set_property target_language Verilog [current_project]

            puts "INFO: Building Urbana $target target for $part"
            puts "INFO: Output directory: $output_dir"
            set include_dirs {}
            foreach rtl_file $rtl_files {
                lappend include_dirs [file dirname $rtl_file]
            }
            set_property include_dirs [lsort -unique $include_dirs] [current_fileset]
            read_verilog -sv $rtl_files
            read_xdc $xdc_file
            synth_design -top $top -part $part
            if {$target eq "uart"} {
                source [file join $script_dir uart_rx_constraints.tcl]
            }
            write_checkpoint -force [file join $output_dir post_synth.dcp]
            report_utilization -file [file join $output_dir utilization_synth.rpt]

            opt_design
            place_design
            phys_opt_design
            route_design

            write_checkpoint -force [file join $output_dir post_route.dcp]
            if {$target eq "uart"} {
                set ::urbana_uart_report_dir [file join $output_dir reports]
                source [file join $script_dir validate_uart.tcl]
            } else {
                report_utilization -file [file join $output_dir utilization_route.rpt]
                report_route_status -file [file join $output_dir route_status.rpt]
                report_drc -file [file join $output_dir drc.rpt]
                report_timing_summary -delay_type min_max -report_unconstrained \
                    -check_timing_verbose -file [file join $output_dir timing_summary.rpt]
                if {[llength [get_clocks -quiet clk_100mhz]] != 1} {
                    error "Expected the constrained 100 MHz clock; inspect the XDC and timing report."
                }
                foreach analysis {setup hold} {
                    set path [get_timing_paths -$analysis -max_paths 1]
                    if {[llength $path] == 0} {
                        error "No $analysis timing paths found; inspect timing_summary.rpt."
                    }
                    set slack [get_property SLACK $path]
                    if {![string is double -strict $slack] ||
                        [regexp -nocase {inf|nan} $slack] || $slack < 0.0} {
                        error "Routed $analysis timing failed (slack $slack ns); inspect timing_summary.rpt."
                    }
                    puts "INFO: Worst $analysis slack: $slack ns"
                }
            }

            # Vivado's bitstream DRCs remain enabled, including I/O constraints.
            set bit_file [file join $output_dir ${top}.bit]
            write_bitstream -force $bit_file
            puts "INFO: Bitstream generated: $bit_file"
            if {$target eq "uart"} {
                puts "INFO: UART: 115200 8N1, no flow control; reset sends USI followed by newline, then four-byte echo."
                puts "INFO: LEDs: LED0 heartbeat, LED1 ready, LED2 sticky error (reset to recover)."
            } else {
                puts "INFO: Program with Vivado Hardware Manager; LED0 blinks at 1 Hz."
            }
        } result options]
        cd $previous_dir
        if {$result_code != 0} {
            return -options $options $result
        }
    }
}

if {![info exists argv]} {
    set argv {}
}
::urbana::main $argv
