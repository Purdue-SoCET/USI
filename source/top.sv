module top(
    input logic CLK, nRST,
    bus_protocol_if.peripheral_vital bpif,
    input logic load,
    input logic send,
    input logic [7:0] data_in,
    input logic rx_line,
    input logic spi_miso,
    output logic tx_out,
    output logic spi_mosi,
    output logic serial_clk,
    output logic [3:0] spi_cs_n,
    output logic [7:0] data_out,
    output logic [7:0] buffer_occupancy
);

    logic [1:0]  mode_sel;
    logic [31:0] clkdiv;
    logic [31:0] configuration;
    logic [31:0] tx_data;
    logic [31:0] error_reg;

    logic ctrl_unit_error;
    logic [31:0] buffer_read;

    logic push, pop;

    logic uart_en, spi_en, i2c_en;
    logic done;
    logic usi_busy;

    logic [7:0] spi_data_out;
    logic [7:0] i2c_data_out;
    logic [7:0] uart_rx_data_out;

    logic push_rx_fifo;

    logic start_bit_det;
    logic parity_error;
    logic stop_error;

    logic start_bit_en;
    logic stop_bit_en;
    logic rx_enable;
    logic tx_enable;
    logic msb_first;
    logic [1:0] parity_mode;

    assign ctrl_unit_error = 1'b0;

    assign start_bit_en = 1'b1;
    assign stop_bit_en  = 1'b1;
    assign rx_enable    = 1'b0;
    assign tx_enable    = send;
    assign msb_first    = configuration[0];
    assign parity_mode  = configuration[2:1];

    assign serial_clk = 1'b0;
    assign spi_mosi   = 1'b0;
    assign spi_cs_n   = 4'b1111;

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
        .serial_in(rx_line),
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
        .serial_out(tx_out),
        .data_in(uart_rx_data_out)
    );

    //TO FIX LATER

  /*  control_unit CONTROL_UNIT (
        .clk(CLK),
        .n_rst(nRST),
        .enable(send),
        .mode_sel(mode_sel),
        .done(done),
        .uart_en(uart_en),
        .spi_en(spi_en),
        .i2c_en(i2c_en),
        .usi_busy(usi_busy)
    );

    */

endmodule