module top(
    input logic CLK, nRST,
    bus_protocol_if.peripheral_vital bpif
);

    logic [1:0]  mode_sel;
    logic [31:0] clkdiv;
    logic [31:0] configuration;
    logic [31:0] tx_data;
    logic [31:0] error_reg;
    logic        ctrl_unit_error;
    logic [31:0] buffer_read;

    logic push;
    logic pop;

    logic load;
    logic send;
    logic [7:0] data_in;
    logic [7:0] data_out;
    logic [7:0] buffer_occupancy;

    reg_map REG_MAP (
        .bpif(bpif),
        .CLK(CLK),
        .nRST(nRST),
        .ctrl_unit_error(ctrl_unit_error),
        .buffer_read(buffer_read),
        .mode_sel(mode_sel),
        .clkdiv(clkdiv),
        .configuration(configuration),
        .tx_data(tx_data),
        .error_reg(error_reg),
        .push(push),
        .pop(pop)
    );

    data_buffer DATA_BUFFER (
        .CLK(CLK),
        .nRST(nRST),
        .mode_sel(mode_sel),
        .data_in(data_in),
        .buffer_write(tx_data),
        .push(push),
        .pop(pop),
        .clear(1'b0),
        .load(load),
        .send(send),
        .data_out(data_out),
        .buffer_read(buffer_read),
        .buffer_occupancy(buffer_occupancy)
    );

endmodule