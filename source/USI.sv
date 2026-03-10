module USI(
    input logic CLK, nRST,
    bus_protocol_if.peripheral_vital bpif
);

    // reg_map signals
    logic [1:0]  mode_sel;
    logic [31:0] clkdiv;
    logic [31:0] parameters;
    logic [31:0] tx_data;
    logic [31:0] error_reg;

    logic        ctrl_unit_error;
    logic [31:0] buffer_read;

    // data_buffer signals
    logic [7:0] data_in;
    logic [31:0] buffer_write;
    logic push;
    logic pop;
    logic clear;
    logic load;
    logic send;
    logic [7:0] data_out;
    logic [31:0] buffer_read;
    logic [7:0] buffer_occupancy;

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

    data_buffer FIFO (
        .CLK(CLK),
        .nRST(nRST),
        .mode_sel(mode_sel),
        .data_in(data_in),
        .buffer_write(buffer_write),
        .push(push),
        .pop(pop),
        .clear(clear),
        .load(load),
        .send(send),
        .data_out(data_out),
        .buffer_read(buffer_read),
        .buffer_occupancy(buffer_occupancy)
    );

endmodule