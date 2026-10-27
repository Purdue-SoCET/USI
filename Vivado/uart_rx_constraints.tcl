namespace eval ::urbana_rx {
    proc apply {} {
        set meta [get_cells -quiet -hierarchical -filter {NAME =~ *uart_fsm/rx_meta_reg}]
        set sync [get_cells -quiet -hierarchical -filter {NAME =~ *uart_fsm/rx_sync_reg}]
        if {[llength $meta] != 1 || [llength $sync] != 1} {
            error "Cannot identify both UART RX synchronizer flops; inspect the synthesized hierarchy."
        }
        set_property ASYNC_REG TRUE [concat $meta $sync]
        set meta_d [get_pins -of_objects $meta -filter {REF_PIN_NAME == D}]
        if {[llength $meta_d] != 1} {
            error "Cannot identify UART RX first-stage D pin."
        }
        set_false_path -from [get_ports uart_rx] -to $meta_d
        puts "INFO: UART RX synchronizer marked; only external RX -> first-stage D is excepted."
    }
}
::urbana_rx::apply
