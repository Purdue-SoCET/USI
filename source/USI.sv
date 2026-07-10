module USI #(
    parameter unsigned RX_FIFO_SIZE = 16, // must be equal to 2^n
    parameter unsigned TX_FIFO_SIZE = 16  // must be equal to 2^n
)(
    bus_protocol_if.peripheral_vital bpif,
    input logic CLK,
    input logic nRST,
    input logic uart_rx,
    output logic uart_tx,
    input logic spi_miso,
    output logic spi_mosi,
    output logic spi_sclk,
    output logic spi_cs,
    inout wire i2c_sda,
    inout wire i2c_scl
);
    logic [31:0] rx_rdata, rx_wdata, tx_rdata, tx_wdata;
    logic [31:0] clkdiv;
    logic [1:0] mode_sel;
    logic [7:0] uart_config;
    logic [7:0] spi_config;
    logic i2c_config;
    logic [9:0] i2c_addr;
    logic [31:0] i2c_t_low, i2c_t_high;
    logic rx_REN, rx_WEN, tx_REN, tx_WEN;
    logic [$clog2(RX_FIFO_SIZE+1)-1:0] rx_count;
    logic [$clog2(TX_FIFO_SIZE+1)-1:0] tx_count;
    logic tx_overrun, tx_underrun;
    logic rx_overrun, rx_underrun;
    logic tx_full, tx_empty;
    logic rx_full, rx_empty;
    logic tx_flush, tx_clear_overrun, tx_clear_underrun;
    logic rx_flush, rx_clear_overrun, rx_clear_underrun;

// Register Map
    register_map #(
        .RX_FIFO_SIZE(RX_FIFO_SIZE),
        .TX_FIFO_SIZE(TX_FIFO_SIZE)
    ) reg_map (
        .bpif(bpif),
        .CLK(CLK),
        .nRST(nRST),
        .tx_overrun(tx_overrun),
        .tx_underrun(tx_underrun),
        .rx_overrun(rx_overrun),
        .rx_underrun(rx_underrun),
        .tx_full(tx_full),
        .tx_empty(tx_empty),
        .rx_full(rx_full),
        .rx_empty(rx_empty),
        .tx_count(tx_count),
        .rx_count(rx_count),
        .rx_rdata(rx_rdata),
        .mode_sel(mode_sel),
        .clkdiv(clkdiv),
        .tx_wdata(tx_wdata),
        .uart_config(uart_config),
        .spi_config(spi_config),
        .i2c_config(i2c_config),
        .i2c_addr(i2c_addr),
        .i2c_t_low(i2c_t_low),
        .i2c_t_high(i2c_t_high),
        .tx_WEN(tx_WEN),
        .rx_REN(rx_REN),
        .tx_clear_overrun(tx_clear_overrun),
        .tx_clear_underrun(tx_clear_underrun),
        .rx_clear_overrun(rx_clear_overrun),
        .rx_clear_underrun(rx_clear_underrun),
        .tx_flush(tx_flush),
        .rx_flush(rx_flush)
    );

// Data Buffer FIFOs
    asym_fifo #(
        .READ_BYTES(4),
        .WRITE_BYTES(1),
        .DEPTH_BYTES(RX_FIFO_SIZE)
    ) rx_fifo (
        .CLK(CLK),
        .nRST(nRST),
        .WEN(rx_WEN),
        .REN(rx_REN),
        .clear_underrun(rx_clear_underrun),
        .clear_overrun(rx_clear_overrun),
        .flush(rx_flush),
        .wdata(rx_wdata),
        .full(rx_full),
        .empty(rx_empty),
        .underrun(rx_underrun),
        .overrun(rx_overrun),
        .count(rx_count),
        .rdata(rx_rdata)
    );

    asym_fifo #(
        .READ_BYTES(1),
        .WRITE_BYTES(4),
        .DEPTH_BYTES(TX_FIFO_SIZE)
    ) tx_fifo (
        .CLK(CLK),
        .nRST(nRST),
        .WEN(tx_WEN),
        .REN(tx_REN),
        .clear_underrun(tx_clear_underrun),
        .clear_overrun(tx_clear_overrun),
        .flush(tx_flush),
        .wdata(tx_wdata),
        .full(tx_full),
        .empty(tx_empty),
        .underrun(tx_underrun),
        .overrun(tx_overrun),
        .count(tx_count),
        .rdata(tx_rdata)
    );


endmodule
