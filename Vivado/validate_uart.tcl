namespace eval ::urbana_validation {
    proc check {report_dir} {
        file mkdir $report_dir
        set expected_ports {clk_100mhz btn_reset uart_rx uart_tx led_heartbeat led_ready led_error}
        if {[lsort [get_ports]] ne [lsort $expected_ports]} {
            error "UART board top must expose exactly seven board pins. Select urbana_usi_uart_top."
        }
        foreach {port pin standard} {
            clk_100mhz N15 LVCMOS33
            btn_reset J2 LVCMOS25
            uart_rx B16 LVCMOS33
            uart_tx A16 LVCMOS33
            led_heartbeat C13 LVCMOS33
            led_ready C14 LVCMOS33
            led_error D14 LVCMOS33
        } {
            if {[get_property PACKAGE_PIN [get_ports $port]] ne $pin ||
                [get_property IOSTANDARD [get_ports $port]] ne $standard} {
                error "Wrong/missing pin constraint for $port; expected $pin/$standard."
            }
        }
        set clock [get_clocks -quiet clk_100mhz]
        if {[llength $clock] != 1 || [llength [get_clocks]] != 1} {
            error "Expected exactly one constrained 100 MHz clock."
        }
        if {abs([get_property PERIOD $clock] - 10.0) > 0.001} {
            error "clk_100mhz must have a 10 ns period."
        }

        report_timing_summary -delay_type min_max -report_unconstrained \
            -check_timing_verbose -file [file join $report_dir timing_summary.rpt]
        report_utilization -file [file join $report_dir utilization.rpt]
        report_route_status -file [file join $report_dir route_status.rpt]
        report_drc -file [file join $report_dir drc.rpt]
        report_cdc -details -file [file join $report_dir cdc.rpt]
        set pulse_warnings [get_msg_config -count -severity {CRITICAL WARNING}]
        report_pulse_width -warn_on_violation -file [file join $report_dir pulse_width.rpt]
        if {[get_msg_config -count -severity {CRITICAL WARNING}] > $pulse_warnings} {
            error "Pulse-width report raised a critical warning; inspect pulse_width.rpt."
        }

        foreach name {no_clock unconstrained_internal_endpoints} {
            set result [check_timing -override_defaults [list $name] -return_string]
            set handle [open [file join $report_dir ${name}.rpt] w]
            puts $handle $result
            close $handle
            set pattern [format {checking\s+%s\s+\(([0-9]+)\)} $name]
            if {![regexp -nocase $pattern $result -> count]} {
                if {$name eq "no_clock"} {
                    set pattern {There are\s+([0-9]+)\s+register/latch pins with no clock}
                } else {
                    set pattern {There are\s+([0-9]+)\s+pins that are not constrained for maximum delay}
                }
                if {![regexp -nocase $pattern $result -> count]} {
                    error "Cannot interpret $name report; review it before generating a bitstream."
                }
            }
            if {$count != 0} {
                error "$name reports $count endpoints; inspect $report_dir."
            }
        }
        foreach analysis {setup hold} {
            set path [get_timing_paths -$analysis -max_paths 1]
            if {[llength $path] != 1} {
                error "No unique worst $analysis timing path found."
            }
            set slack [get_property SLACK $path]
            if {![string is double -strict $slack] ||
                [regexp -nocase {inf|nan} $slack] || $slack < 0.0} {
                error "UART $analysis timing failed or unconstrained: slack=$slack ns."
            }
            puts "INFO: UART worst $analysis slack: $slack ns"
        }
        puts "INFO: UART board-pin, clock, coverage, setup, hold and pulse-width checks passed."
    }
}
if {![info exists ::urbana_uart_report_dir]} {
    set ::urbana_uart_report_dir [file normalize [file join [file dirname [info script]] .. build urbana uart reports]]
}
::urbana_validation::check $::urbana_uart_report_dir
