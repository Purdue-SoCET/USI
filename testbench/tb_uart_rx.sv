`timescale 1ns/1ps

module tb_uart_rx_fsm_8n1;

  parameter int DATA_BITS = 8;

  logic clk;
  logic rst_n;
  logic rx_line;
  logic baud_tick;
  logic half_bit_tick;
  logic uart_en;
  logic done;
  logic err;
  logic baud_wait;
  logic half_bit_timer_en;
  logic sample_rx_en;
  logic [DATA_BITS-1:0] rx_byte_out;
  logic push_rx_fifo;

  // DUT
  uart_rx_fsm_8n1 #(
    .DATA_BITS(DATA_BITS)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .rx_line(rx_line),
    .baud_tick(baud_tick),
    .half_bit_tick(half_bit_tick),
    .uart_en(uart_en),
    .done(done),
    .err(err),
    .baud_wait(baud_wait),
    .half_bit_timer_en(half_bit_timer_en),
    .sample_rx_en(sample_rx_en),
    .rx_byte_out(rx_byte_out),
    .push_rx_fifo(push_rx_fifo)
  );

  initial begin
    $dumpfile("wave_rx.vcd");
    $dumpvars(0, tb_uart_rx_fsm_8n1);
end

  // clock
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  // monitor
  initial begin
    $monitor("T=%0t state=%0d rst_n=%b rx_line=%b half_tick=%b baud_tick=%b done=%b err=%b push=%b bit_cnt=%0d rx_sr=%b rx_byte_out=%b",
             $time, dut.state, rst_n, rx_line, half_bit_tick, baud_tick,
             done, err, push_rx_fifo, dut.bit_cnt, dut.rx_sr, rx_byte_out);
  end

  initial begin
    // -------------------------
    // Initialize
    // -------------------------
    rst_n         = 1'b0;
    rx_line       = 1'b1;   // idle line high
    baud_tick     = 1'b0;
    half_bit_tick = 1'b0;

    // Reset
    @(negedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // =========================================================
    // TEST 1: Valid 8N1 frame
    // Byte = 8'b1010_0101
    // UART sends LSB first: 1,0,1,0,0,1,0,1
    // =========================================================

    // IDLE -> START_ALIGN
    @(negedge clk);
    rx_line = 1'b0;   // start bit begins

    // START_ALIGN -> START_CHECK
    @(negedge clk);
    half_bit_tick = 1'b1;
    @(negedge clk);
    half_bit_tick = 1'b0;

    // keep start bit low for valid check
    @(negedge clk);
    rx_line = 1'b0;

    // DATA bits, one per baud_tick
    // bit0 = 1
    @(negedge clk);
    rx_line   = 1'b1;
    baud_tick = 1'b1;
    @(negedge clk);
    baud_tick = 1'b0;

    // bit1 = 0
    @(negedge clk);
    rx_line   = 1'b0;
    baud_tick = 1'b1;
    @(negedge clk);
    baud_tick = 1'b0;

    // bit2 = 1
    @(negedge clk);
    rx_line   = 1'b1;
    baud_tick = 1'b1;
    @(negedge clk);
    baud_tick = 1'b0;

    // bit3 = 0
    @(negedge clk);
    rx_line   = 1'b0;
    baud_tick = 1'b1;
    @(negedge clk);
    baud_tick = 1'b0;

    // bit4 = 0
    @(negedge clk);
    rx_line   = 1'b0;
    baud_tick = 1'b1;
    @(negedge clk);
    baud_tick = 1'b0;

    // bit5 = 1
    @(negedge clk);
    rx_line   = 1'b1;
    baud_tick = 1'b1;
    @(negedge clk);
    baud_tick = 1'b0;

    // bit6 = 0
    @(negedge clk);
    rx_line   = 1'b0;
    baud_tick = 1'b1;
    @(negedge clk);
    baud_tick = 1'b0;

    // bit7 = 1
    @(negedge clk);
    rx_line   = 1'b1;
    baud_tick = 1'b1;
    @(negedge clk);
    baud_tick = 1'b0;

    // STOP bit = 1
    @(negedge clk);
    rx_line   = 1'b1;
    baud_tick = 1'b1;
    @(negedge clk);
    baud_tick = 1'b0;

    // observe PUSH -> IDLE
    @(negedge clk);
    @(negedge clk);

    // =========================================================
    // TEST 2: False start
    // IDLE -> START_ALIGN -> START_CHECK -> IDLE
    // =========================================================
    @(negedge clk);
    rx_line = 1'b0;   // start edge seen

    @(negedge clk);
    half_bit_tick = 1'b1;
    @(negedge clk);
    half_bit_tick = 1'b0;

    // line goes back high before start check
    @(negedge clk);
    rx_line = 1'b1;

    @(negedge clk);
    @(negedge clk);

    // =========================================================
    // TEST 3: Framing error
    // valid start + 8 bits + bad stop bit = 0
    // =========================================================

    // start bit
    @(negedge clk);
    rx_line = 1'b0;

    @(negedge clk);
    half_bit_tick = 1'b1;
    @(negedge clk);
    half_bit_tick = 1'b0;

    @(negedge clk);
    rx_line = 1'b0;

    // send 8 data bits: 1100_0011
    // LSB first = 1,1,0,0,0,0,1,1

    // bit0 = 1
    @(negedge clk);
    rx_line   = 1'b1;
    baud_tick = 1'b1;
    @(negedge clk);
    baud_tick = 1'b0;

    // bit1 = 1
    @(negedge clk);
    rx_line   = 1'b1;
    baud_tick = 1'b1;
    @(negedge clk);
    baud_tick = 1'b0;

    // bit2 = 0
    @(negedge clk);
    rx_line   = 1'b0;
    baud_tick = 1'b1;
    @(negedge clk);
    baud_tick = 1'b0;

    // bit3 = 0
    @(negedge clk);
    rx_line   = 1'b0;
    baud_tick = 1'b1;
    @(negedge clk);
    baud_tick = 1'b0;

    // bit4 = 0
    @(negedge clk);
    rx_line   = 1'b0;
    baud_tick = 1'b1;
    @(negedge clk);
    baud_tick = 1'b0;

    // bit5 = 0
    @(negedge clk);
    rx_line   = 1'b0;
    baud_tick = 1'b1;
    @(negedge clk);
    baud_tick = 1'b0;

    // bit6 = 1
    @(negedge clk);
    rx_line   = 1'b1;
    baud_tick = 1'b1;
    @(negedge clk);
    baud_tick = 1'b0;

    // bit7 = 1
    @(negedge clk);
    rx_line   = 1'b1;
    baud_tick = 1'b1;
    @(negedge clk);
    baud_tick = 1'b0;

    // bad stop bit = 0, should go to ERROR
    @(negedge clk);
    rx_line   = 1'b0;
    baud_tick = 1'b1;
    @(negedge clk);
    baud_tick = 1'b0;

    // back to idle line high
    @(negedge clk);
    rx_line = 1'b1;

    @(negedge clk);
    @(negedge clk);

    $finish;
  end

endmodule
