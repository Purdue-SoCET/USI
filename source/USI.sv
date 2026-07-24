module USI #(
    parameter unsigned RX_FIFO_SIZE = 16, // must be equal to 2^n
    parameter unsigned TX_FIFO_SIZE = 16, // must be equal to 2^n
    parameter int CLKDIV_BITS = 16 // 16 bits for largest clock divisor to get slowest frequency (300 baudrate)
)(
    bus_protocol_if.peripheral_vital bpif,
    input logic CLK,
    input logic nRST,
    input logic uart_rx,
    output logic uart_tx,
    input logic uart_cts,
    output logic uart_rts,
    input logic spi_miso,
    output logic spi_mosi,
    output logic spi_sclk,
    output logic spi_cs,
    inout wire i2c_sda,
    inout wire i2c_scl
);
    logic [31:0] rx_rdata, rx_wdata, tx_rdata, tx_wdata;
    logic [CLKDIV_BITS:0] clkdiv;
    logic [1:0] mode_sel;
    logic [2:0] uart_config;
    logic [7:0] spi_config;
    logic i2c_config;
    logic [9:0] i2c_addr;
    logic [CLKDIV_BITS-1:0] i2c_t_low, i2c_t_high;
    logic rx_REN, rx_WEN, tx_REN, tx_WEN;
    logic [$clog2(RX_FIFO_SIZE+1)-1:0] rx_count;
    logic [$clog2(TX_FIFO_SIZE+1)-1:0] tx_count;
    logic tx_overrun, tx_underrun;
    logic rx_overrun, rx_underrun;
    logic tx_full, tx_empty;
    logic rx_full, rx_empty;
    logic tx_flush, tx_clear_overrun, tx_clear_underrun;
    logic rx_flush, rx_clear_overrun, rx_clear_underrun;
    logic serial_in, serial_out;
    logic [1:0] mode_active;
    logic uart_tx_load;
    logic [7:0] uart_tx_data;
    logic uart_tx_shift_en;
    logic uart_tx_REN;
    logic uart_rx_shift_en;
    logic uart_rx_WEN;
    logic uart_tx_active;
    logic uart_rx_active;

    logic spi_active;

    logic i2c_active;

    logic tx_parallel_load;
    logic [7:0] tx_parallel_in;
    logic tx_shift_en;
    logic tx_shift_in;
    logic msb_first;
    logic rx_shift_en;
    logic clkdiv_en;
    logic clkdiv_count;

// Register Map
    register_map #(
        .RX_FIFO_SIZE(RX_FIFO_SIZE),
        .TX_FIFO_SIZE(TX_FIFO_SIZE),
        .CLKDIV_BITS(CLKDIV_BITS)
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

// Control Unit
    control_unit control_unit (
        .CLK(CLK),
        .nRST(nRST),
        .mode_sel(mode_sel),

        .uart_tx_load(uart_tx_load),
        .uart_tx_data(uart_tx_data),
        .uart_tx_shift_en(uart_rx_shift_en),
        .uart_tx_REN(uart_tx_REN),
        .uart_rx_shift_en(uart_rx_shift_en),
        .uart_rx_WEN(uart_rx_WEN),
        .uart_tx_active(uart_tx_active),
        .uart_rx_active(uart_rx_active),

        .spi_active(spi_active),
        .i2c_active(i2c_active),

        .mode_active(mode_active),
        .tx_parallel_load(tx_parallel_load),
        .tx_parallel_in(tx_parallel_in),
        .tx_shift_en(tx_shift_en),
        .tx_shift_in(tx_shift_in),
        .tx_REN(tx_REN),
        .msb_first(msb_first),
        .rx_shift_en(rx_shift_en),
        .rx_WEN(rx_WEN)
    );
    assign spi_active = 1'b0;
    assign i2c_active = 1'b0;

// Clock Divider
    socetlib_counter #(
        .NBITS(16)
    ) clk_divider (
        .CLK(CLK),
        .nRST(nRST),
        .clear(),
        .count_enable(clkdiv_en),
        .overflow_val(clkdiv),
        .count_out(clkdiv_count),
        .overflow_flag(serial_tick)
    );

// Shift Registers
    shift_register tx_sr (
        .CLK(CLK),
        .nRST(nRST),
        .parallel_load(tx_parallel_load),
        .parallel_in(tx_parallel_in),
        .shift_en(tx_shift_en),
        .msb_first(msb_first),
        .shift_in(tx_shift_in),
        .shift_out(serial_out),
        .parallel_out()
    );

    shift_register rx_sr (
        .CLK(CLK),
        .nRST(nRST),
        .parallel_load(1'b0),
        .parallel_in(8'b0),
        .shift_en(rx_shift_en),
        .msb_first(msb_first),
        .shift_in(serial_in),
        .shift_out(),
        .parallel_out(rx_wdata)
    );

// Protocol Wrappers
    // uart uart_wrapper (
    //     .CLK(CLK),
    //     .nRST(nRST),
    //     .uart_en(uart_en),
    //     .serial_tick(serial_tick),
    //     .uart_rx(uart_rx),
    //     .parity_mode(uart_config[1:0]),
    //     .flow_control_en(uart_config[2]),
    //     .uart_cts(uart_cts),
    //     .rx_fifo_full()
    // )

    assign uart_tx = (mode_active == 2'b01) ? serial_out : 1'b1;
    assign spi_mosi = (mode_active == 2'b10) ? serial_out : spi_config[0];
    assign i2c_sda = 1'b0; //(mode_active == 2'b11 && sda_en) ? sda_out : 1'bz;
    always_comb begin
        unique case(mode_active)
            2'b00: serial_in = 1'b0;
            2'b01: serial_in = uart_rx;
            2'b10: serial_in = spi_miso;
            2'b11: serial_in = i2c_sda;
        endcase
    end

endmodule
