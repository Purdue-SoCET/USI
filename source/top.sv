module top(
    input logic CLK,
    input logic nRST,
    bus_protocol_if.peripheral_vital bpif,
    input logic serial_in,
    output logic serial_out,
    output logic serial_clk,
    output logic [31:0] spi_cs_n
);

    logic [1:0]  mode_sel;
    logic [31:0] clkdiv;
    logic [31:0] configuration;
    logic [31:0] tx_data;
    logic [31:0] error_reg;
    logic [7:0] data_in;
    logic [7:0] data_out;
    logic [7:0] buffer_occupancy;
    logic load;
    logic send;

    logic ctrl_unit_error;
    logic [31:0] buffer_read;

    logic push, pop;

    logic start_bit_det;
    logic parity_error;
    logic stop_error;

    logic start_bit_en;
    logic stop_bit_en;
    logic rx_enable;
    logic tx_enable;
    logic msb_first;
    logic [1:0] parity_mode;

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
        .buffer_write(bpif.wdata),
        .push(push),
        .pop(pop),
        .clear(1'b0),
        .load(load),
        .send(send),
        .data_out(data_out),
        .buffer_read(buffer_read),
        .buffer_occupancy(buffer_occupancy)
    );

    datapath DATAPATH (
        .clk(CLK),
        .n_rst(nRST),
        .serial_in(serial_in),
        .start_bit_en(start_bit_en),
        .stop_bit_en(stop_bit_en),
        .rx_enable(rx_enable),
        .serial_clk(serial_clk),
        .tx_enable(tx_enable),
        .msb_first(msb_first),
        .parity_mode(parity_mode),
        .data_out(data_out),
        .start_bit_det(start_bit_det),
        .parity_error(parity_error),
        .stop_error(stop_error),
        .serial_out(serial_out),
        .data_in(data_in)
    );

    control_unit CONTROL_UNIT (
        .clk(CLK),
        .n_rst(nRST),
        .mode_select(mode_sel),
        .clkdiv(clkdiv),
        .configuration(configuration),
        .start_bit_det(start_bit_det),
        .parity_error(parity_error),
        .stop_error(stop_error),
        .buffer_occupancy(buffer_occupancy),
        .ctrl_unit_error(ctrl_unit_error),
        .cs_n(spi_cs_n),
        .parity_mode(parity_mode),
        .start_bit_en(start_bit_en),
        .stop_bit_en(stop_bit_en),
        .rx_enable(rx_enable),
        .serial_clk(serial_clk),
        .tx_enable(tx_enable),
        .msb_first(msb_first),
        .load(load),
        .send(send)
    );

endmodule
