module urbana_usi_uart_top #(
    parameter int unsigned FIFO_SIZE = 256,
    parameter int unsigned UART_DIVISOR = 217,
    parameter int unsigned HEARTBEAT_HALF_PERIOD_CYCLES = 12_500_000,
    parameter int unsigned BUS_TIMEOUT_CYCLES = 1024
)(
    input  logic clk_100mhz,
    input  logic btn_reset,
    input  logic uart_rx,
    output logic uart_tx,
    output logic led_heartbeat,
    output logic led_ready,
    output logic led_error,
    output logic spi_sclk,
    output logic spi_cs_n,
    output logic spi_mosi,
    input  logic spi_miso
);
    localparam int HEARTBEAT_BITS = (HEARTBEAT_HALF_PERIOD_CYCLES > 1) ?
        $clog2(HEARTBEAT_HALF_PERIOD_CYCLES) : 1;

    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    logic [1:0] reset_sync;
    logic reset_n;
    logic [HEARTBEAT_BITS-1:0] heartbeat_count;
    logic clk_25mhz;
    logic clock_locked;
    logic reset_request;
    logic spi_loopback;
    bus_protocol_if bpif();

    assign bpif.is_burst = 1'b0;
    assign bpif.burst_type = 2'b00;
    assign bpif.burst_length = 8'd0;
    assign bpif.secure_transfer = 1'b0;

    generate
        if (FIFO_SIZE < 8) begin : INVALID_FIFO_SIZE
            $error("%m: FIFO_SIZE must leave at least four TX bytes in the reset split");
        end
        if (HEARTBEAT_HALF_PERIOD_CYCLES < 1) begin : INVALID_HEARTBEAT
            $error("%m: HEARTBEAT_HALF_PERIOD_CYCLES must be at least one");
        end
    endgenerate

    // Hold the design in reset while the button is pressed
    // or the generated clock is not locked.
    assign reset_request = btn_reset || !clock_locked;

    initial reset_sync = 2'b11;

    always_ff @(posedge clk_25mhz or posedge reset_request) begin
        if (reset_request)
            reset_sync <= 2'b11;
        else
            reset_sync <= {reset_sync[0], 1'b0};
    end

    assign reset_n = !reset_sync[1];

    always_ff @(posedge clk_25mhz or negedge reset_n) begin
        if (!reset_n) begin
            heartbeat_count <= '0;
            led_heartbeat <= 1'b0;
        end else if (heartbeat_count == HEARTBEAT_BITS'(HEARTBEAT_HALF_PERIOD_CYCLES - 1)) begin
            heartbeat_count <= '0;
            led_heartbeat <= !led_heartbeat;
        end else begin
            heartbeat_count <= heartbeat_count + 1'b1;
        end
    end

    usi_bus_exerciser #(
        .UART_DIVISOR(UART_DIVISOR),
        .BUS_TIMEOUT_CYCLES(BUS_TIMEOUT_CYCLES),
        .TEST_MODE(2), // 1 = UART, 2 = SPI loopback
        .SPI_DIVISOR(100)
    ) exerciser (
        .CLK(clk_25mhz), .nRST(reset_n),
        .bus_addr(bpif.addr), .bus_wdata(bpif.wdata), .bus_strobe(bpif.strobe),
        .bus_wen(bpif.wen), .bus_ren(bpif.ren),
        .bus_rdata(bpif.rdata), .bus_error(bpif.error),
        .bus_request_stall(bpif.request_stall),
        .ready(led_ready), .fault(led_error)
    );

    USI #(.FIFO_SIZE(FIFO_SIZE), .CLKDIV_BITS(16)) usi (
        .bpif(bpif), .CLK(clk_25mhz), .nRST(reset_n),
        .uart_rx(uart_rx), .uart_tx(uart_tx),
        .uart_cts(1'b1), .uart_rts(),
        .spi_miso(spi_loopback), .spi_mosi(spi_loopback),
        .spi_sclk(), .spi_cs(),
        .i2c_sda(), .i2c_scl()
    );

    clk_wiz_25mhz clock_generator (
        .clk_in1(clk_100mhz),
        .clk_out1(clk_25mhz),
        .resetn(!btn_reset),
        .locked(clock_locked)
    );
endmodule
