namespace eval ::urbana_rebuild {
    variable script_dir [file dirname [file normalize [info script]]]

    proc run {} {
        variable script_dir
        source [file join $script_dir configure_uart.tcl]
        set synth_run $::urbana_project::synth_run
        set impl_run $::urbana_project::impl_run
        launch_runs $synth_run -jobs 4
        wait_on_run $synth_run
        if {[get_property PROGRESS [get_runs $synth_run]] ne "100%" ||
            ![string match {*Complete*} [get_property STATUS [get_runs $synth_run]]]} {
            error "UART synthesis did not complete; inspect the $synth_run log."
        }
        launch_runs $impl_run -to_step write_bitstream -jobs 4
        wait_on_run $impl_run
        if {[get_property PROGRESS [get_runs $impl_run]] ne "100%" ||
            ![string match {*Complete*} [get_property STATUS [get_runs $impl_run]]]} {
            error "UART implementation/bitstream did not complete; inspect the $impl_run log."
        }
        set bit_file [file join [get_property DIRECTORY [get_runs $impl_run]] urbana_usi_uart_top.bit]
        if {![file isfile $bit_file]} { error "Completed run has no expected UART bitstream: $bit_file" }
        set output_dir [file normalize [file join $script_dir .. build urbana uart]]
        file mkdir $output_dir
        set result_file [file join $output_dir urbana_usi_uart_top.bit]
        file copy -force $bit_file $result_file
        puts "INFO: UART bitstream ready: $result_file"
        puts "INFO: Hardware Manager -> Program Device, then select that file."
        puts "INFO: Test from Windows: py tools/uart_board_test.py --port COM5 (use your board's COM port)."
    }
}
::urbana_rebuild::run
