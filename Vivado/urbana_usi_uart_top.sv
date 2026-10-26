module urbana_usi_uart_top #(
    parameter int unsigned FIFO_SIZE = 256,
    parameter int unsigned UART_DIVISOR = 868,
    parameter int unsigned HEARTBEAT_HALF_PERIOD_CYCLES = 50_000_000,
    parameter int unsigned BUS_TIMEOUT_CYCLES = 1024
)(
    input  logic clk_100mhz,
    input  logic btn_reset,
    input  logic uart_rx,
    output logic uart_tx,
    output logic led_heartbeat,
    output logic led_ready,
    output logic led_error
);
    localparam int HEARTBEAT_BITS = (HEARTBEAT_HALF_PERIOD_CYCLES > 1) ?
        $clog2(HEARTBEAT_HALF_PERIOD_CYCLES) : 1;

    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    logic [1:0] reset_sync;
    logic reset_n;
    logic [HEARTBEAT_BITS-1:0] heartbeat_count;
    bus_protocol_if bpif();

    generate
        if (FIFO_SIZE < 8) begin : INVALID_FIFO_SIZE
            $error("%m: FIFO_SIZE must leave at least four TX bytes in the reset split");
        end
        if (HEARTBEAT_HALF_PERIOD_CYCLES < 1) begin : INVALID_HEARTBEAT
            $error("%m: HEARTBEAT_HALF_PERIOD_CYCLES must be at least one");
        end
    endgenerate

    initial reset_sync = 2'b11;
    always @(posedge clk_100mhz or posedge btn_reset) begin
        if (btn_reset)
            reset_sync <= 2'b11;
        else
            reset_sync <= {reset_sync[0], 1'b0};
    end
    assign reset_n = !reset_sync[1];

    always_ff @(posedge clk_100mhz or negedge reset_n) begin
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
        .BUS_TIMEOUT_CYCLES(BUS_TIMEOUT_CYCLES)
    ) exerciser (
        .CLK(clk_100mhz), .nRST(reset_n),
        .bus_addr(bpif.addr), .bus_wdata(bpif.wdata), .bus_strobe(bpif.strobe),
        .bus_wen(bpif.wen), .bus_ren(bpif.ren),
        .bus_rdata(bpif.rdata), .bus_error(bpif.error),
        .bus_request_stall(bpif.request_stall),
        .ready(led_ready), .fault(led_error)
    );

    USI #(.FIFO_SIZE(FIFO_SIZE), .CLKDIV_BITS(16)) usi (
        .bpif(bpif), .CLK(clk_100mhz), .nRST(reset_n),
        .uart_rx(uart_rx), .uart_tx(uart_tx),
        .uart_cts(1'b1), .uart_rts(),
        .spi_miso(1'b0), .spi_mosi(), .spi_sclk(), .spi_cs(),
        .i2c_sda(), .i2c_scl()
    );
endmodule
