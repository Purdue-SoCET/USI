namespace eval ::urbana_project {
    variable script_dir [file dirname [file normalize [info script]]]
    variable synth_run
    variable impl_run

    proc configure {} {
        variable script_dir
        variable synth_run
        variable impl_run
        set repo_dir [file normalize [file join $script_dir ..]]
        if {[llength [info commands get_projects]] == 0} {
            error "Run configure_uart.tcl in Vivado."
        }
        if {[llength [get_projects -quiet]] == 0} {
            open_project [file join $script_dir USI.xpr]
        }
        if {![string equal -nocase [file normalize [get_property DIRECTORY [current_project]]] $script_dir]} {
            error "Open the USI project in this repository's Vivado directory first."
        }
        if {[get_property PART [current_project]] ne "xc7s50csga324-1"} {
            error "Expected the Urbana xc7s50csga324-1 device."
        }
        if {[current_design -quiet] ne ""} { close_design }
        set rtl_files {}
        foreach name {bus_protocol_if usi_datapath split_fifo shift_register register_map control_unit uart spi USI} {
            lappend rtl_files [file join $repo_dir source ${name}.sv]
        }
        lappend rtl_files [file join $script_dir usi_bus_exerciser.sv] \
            [file join $script_dir urbana_usi_uart_top.sv]
        set xdc_file [file join $script_dir urbana_uart.xdc]
        set simulation_files [list [file join $repo_dir testbench uart_peer.sv] \
            [file join $repo_dir testbench urbana_usi_uart_tb.sv]]
        foreach path [concat $rtl_files [list $xdc_file] $simulation_files \
                [list [file join $script_dir uart_rx_constraints.tcl] [file join $script_dir validate_uart.tcl]]] {
            if {![file isfile $path]} { error "Missing source: $path" }
        }

        foreach fileset {sources_1 constrs_1 sim_1} {
            set previous [get_files -quiet -of_objects [get_filesets $fileset]]
            if {[llength $previous] != 0} { remove_files -fileset $fileset $previous }
        }
        add_files -fileset sources_1 -norecurse $rtl_files
        add_files -fileset constrs_1 -norecurse $xdc_file
        add_files -fileset sim_1 -norecurse $simulation_files
        set_property top urbana_usi_uart_top [get_filesets sources_1]
        set_property top_auto_set false [get_filesets sources_1]
        set_property top urbana_usi_uart_tb [get_filesets sim_1]
        set_property top_auto_set false [get_filesets sim_1]
        set_property xsim.simulate.runtime 10ms [get_filesets sim_1]
        set_property target_language Verilog [current_project]
        update_compile_order -fileset sources_1
        update_compile_order -fileset sim_1

        set suffix ""
        set index 1
        while {[llength [get_runs -quiet uart_synth${suffix}]] != 0 ||
               [llength [get_runs -quiet uart_impl${suffix}]] != 0} {
            set suffix _$index
            incr index
        }
        set synth_run uart_synth${suffix}
        set impl_run uart_impl${suffix}
        create_run $synth_run -part xc7s50csga324-1 \
            -flow [get_property FLOW [get_runs synth_1]] \
            -strategy [get_property STRATEGY [get_runs synth_1]] \
            -constrset constrs_1
        if {[get_property SRCSET [get_runs $synth_run]] ne "sources_1"} {
            error "The new synthesis run must use sources_1."
        }
        create_run $impl_run -part xc7s50csga324-1 \
            -flow [get_property FLOW [get_runs impl_1]] \
            -strategy [get_property STRATEGY [get_runs impl_1]] \
            -constrset constrs_1 -parent_run $synth_run
        set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs $impl_run]
        set_property STEPS.OPT_DESIGN.TCL.PRE [file join $script_dir uart_rx_constraints.tcl] [get_runs $impl_run]
        # Validate implementation even when the GUI stops after routing.
        set_property STEPS.ROUTE_DESIGN.TCL.POST [file join $script_dir validate_uart.tcl] [get_runs $impl_run]
        set_property STEPS.WRITE_BITSTREAM.TCL.PRE [file join $script_dir validate_uart.tcl] [get_runs $impl_run]
        current_run -synthesis [get_runs $synth_run]
        current_run -implementation [get_runs $impl_run]
        puts "INFO: UART GUI project configured: urbana_usi_uart_top, seven board pins, 100 MHz."
        puts "INFO: Sources reference the repository; the full imported Urbana.xdc is no longer active."
        puts "INFO: Fresh runs: $synth_run / $impl_run; original runs retained."
    }
}
::urbana_project::configure
