module urbana_top #(
    parameter int unsigned FIFO_SIZE = 256,
    parameter int unsigned SPI_DIVISOR = 100,
    parameter int unsigned HEARTBEAT_HALF_PERIOD_CYCLES = 12_500_000,
    parameter logic [31:0] TX_WORD = 32'h00000000,
    parameter logic [31:0] EXPECTED_RX_WORD = 32'h00001234
) (
    input  logic       clk_100mhz,
    input  logic       btn_reset,
    output logic       spi_sclk,
    output logic       spi_cs_n,
    output logic       spi_mosi,
    input  logic       spi_miso,
    output logic       led_heartbeat,
    output logic       led_ready,
    output logic       led_error,
    output logic [7:0] display_segments,
    output logic [3:0] display_digit_enable
);
    localparam int HEARTBEAT_BITS = (HEARTBEAT_HALF_PERIOD_CYCLES > 1) ?
        $clog2(HEARTBEAT_HALF_PERIOD_CYCLES) : 1;

    logic clk_25mhz, clock_locked, reset_request, reset_n;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    logic [1:0] reset_sync = 2'b11;
    logic [HEARTBEAT_BITS-1:0] heartbeat_count, heartbeat_count_n;
    logic led_heartbeat_n;
    logic [31:0] received_word;
    bus_protocol_if bpif();

    generate
        if (FIFO_SIZE < 8) begin : INVALID_FIFO_SIZE
            $error("%m: FIFO_SIZE must provide four bytes per FIFO after reset");
        end
        if (HEARTBEAT_HALF_PERIOD_CYCLES < 1) begin : INVALID_HEARTBEAT
            $error("%m: HEARTBEAT_HALF_PERIOD_CYCLES must be positive");
        end
    endgenerate

    assign bpif.is_burst = 1'b0;
    assign bpif.burst_type = 2'b00;
    assign bpif.burst_length = 8'd0;
    assign bpif.secure_transfer = 1'b0;

    clk_wiz_25mhz clock_generator (
        .clk_in1(clk_100mhz),
        .clk_out1(clk_25mhz),
        .resetn(!btn_reset),
        .locked(clock_locked)
    );

    assign reset_request = btn_reset || !clock_locked;
    always_ff @(posedge clk_25mhz or posedge reset_request) begin
        if (reset_request)
            reset_sync <= 2'b11;
        else
            reset_sync <= {reset_sync[0], 1'b0};
    end
    assign reset_n = !reset_sync[1];

    always_comb begin
        heartbeat_count_n = heartbeat_count + 1'b1;
        led_heartbeat_n = led_heartbeat;
        if (heartbeat_count == HEARTBEAT_BITS'(HEARTBEAT_HALF_PERIOD_CYCLES - 1)) begin
            heartbeat_count_n = '0;
            led_heartbeat_n = !led_heartbeat;
        end
    end
    always_ff @(posedge clk_25mhz or negedge reset_n) begin
        if (!reset_n) begin
            heartbeat_count <= '0;
            led_heartbeat <= 1'b0;
        end else begin
            heartbeat_count <= heartbeat_count_n;
            led_heartbeat <= led_heartbeat_n;
        end
    end

    bus_exercise #(
        .SPI_DIVISOR(SPI_DIVISOR),
        .TX_WORD(TX_WORD),
        .EXPECTED_RX_WORD(EXPECTED_RX_WORD)
    ) exerciser (
        .CLK(clk_25mhz), .nRST(reset_n),
        .bus_addr(bpif.addr), .bus_wdata(bpif.wdata),
        .bus_strobe(bpif.strobe), .bus_wen(bpif.wen), .bus_ren(bpif.ren),
        .bus_rdata(bpif.rdata), .bus_error(bpif.error),
        .received_word(received_word), .ready(led_ready), .fault(led_error)
    );

    USI #(.FIFO_SIZE(FIFO_SIZE), .CLKDIV_BITS(16)) usi (
        .bpif(bpif), .CLK(clk_25mhz), .nRST(reset_n),
        .uart_rx(1'b1), .uart_tx(), .uart_cts(1'b1), .uart_rts(),
        .spi_miso(spi_miso), .spi_mosi(spi_mosi),
        .spi_sclk(spi_sclk), .spi_cs(spi_cs_n),
        .i2c_sda(), .i2c_scl()
    );

    seven_segment_display display_driver (
        .CLK(clk_25mhz), .nRST(reset_n),
        .display_value(received_word[15:0]),
        .display_segments(display_segments),
        .display_digit_enable(display_digit_enable)
    );
endmodule
