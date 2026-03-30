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

    assign ctrl_unit_error = 1'b0;

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

    control_unit CONTROL_UNIT (
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

    spi_ctrl SPI_INST (
        .clk(CLK),
        .n_rst(nRST),
        .spi_en(spi_en),
        .tx_data(tx_data[7:0]),
        .miso(spi_miso),
        .mosi(spi_mosi),
        .sclk(serial_clk),
        .cs_n(spi_cs_n),
        .data_out(spi_data_out),
        .done(done)
    );

    i2c_ctrl I2C_INST (
        .clk(CLK),
        .n_rst(nRST),
        .i2c_en(i2c_en),
        .tx_data(tx_data[7:0]),
        .data_out(i2c_data_out),
        .done(done)
    );

    uart_tx_fsm_8n1 UART_TX_INST (
        .clk(CLK),
        .n_rst(nRST),
        .tx_enable(uart_en),
        .tx_data(tx_data[7:0]),
        .tx_out(tx_out),
        .done(done)
    );

    uart_rx_fsm_8n1 UART_RX_INST (
        .clk(CLK),
        .n_rst(nRST),
        .rx_enable(uart_en),
        .rx_line(rx_line),
        .rx_byte_out(uart_rx_data_out),
        .push_rx_fifo(push_rx_fifo)
    );

endmodule

