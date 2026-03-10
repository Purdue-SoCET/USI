module USI(
    input logic CLK, nRST,
    bus_protocol_if.peripheral_vital bpif
);

    logic [1:0]  mode_sel;
    logic [31:0] clkdiv;
    logic [31:0] parameters;
    logic [31:0] tx_data;
    logic [31:0] error_reg;

    logic        ctrl_unit_error;
    logic [31:0] buffer_read;

    reg_map REG_MAP (
        .bpif(bpif),
        .CLK(CLK),
        .nRST(nRST),
        .ctrl_unit_error(ctrl_unit_error),
        .buffer_read(buffer_read),
        .mode_sel(mode_sel),
        .clkdiv(clkdiv),
        .parameters(parameters),
        .tx_data(tx_data),
        .error_reg(error_reg)
    );

endmodule