`timescale 1ns/1ps
module tb_spi_ctrl;

  localparam int CLK_HALF = 5;
  localparam int WORD_W   = 8;

  logic clk;
  logic rst_n;

  logic spi_en;
  logic start;
  logic sclk_tick;
  logic tx_data_valid;
  logic [7:0] tx_data;

  logic start_bit_det;
  logic parity_error;
  logic stop_error;

  logic start_bit_en;
  logic stop_bit_en;
  logic rx_enable;
  logic tx_enable;
  logic serial_clk;
  logic msb_first;
  logic [1:0] parity_mode;
  logic [2:0] data_bits;
  logic [7:0] data_out;

  logic busy;
  logic done;

  logic serial_in;
  logic serial_out;
  logic [7:0] data_in;

  int i;
  logic [7:0] exp;
  logic [7:0] got;

  // clock
  initial clk = 1'b0;
  always #CLK_HALF clk = ~clk;

  // DUT: control
  spi_ctrl u_ctrl (
    .clk(clk),
    .rst_n(rst_n),
    .spi_en(spi_en),
    .start(start),
    .sclk_tick(sclk_tick),
    .tx_data_valid(tx_data_valid),
    .tx_data(tx_data),

    .start_bit_det(start_bit_det),
    .parity_error(parity_error),
    .stop_error(stop_error),

    .start_bit_en(start_bit_en),
    .stop_bit_en(stop_bit_en),
    .rx_enable(rx_enable),
    .tx_enable(tx_enable),
    .serial_clk(serial_clk),
    .msb_first(msb_first),
    .parity_mode(parity_mode),
    .data_bits(data_bits),
    .data_out(data_out),

    .busy(busy),
    .done(done)
  );

  // DUT: shared datapath
  datapath u_dp (
    .clk(clk),
    .n_rst(rst_n),

    .serial_in(serial_in),
    .serial_out(serial_out),

    .start_bit_en(start_bit_en),
    .stop_bit_en(stop_bit_en),
    .rx_enable(rx_enable),
    .serial_clk(serial_clk),
    .tx_enable(tx_enable),
    .msb_first(msb_first),
    .parity_mode(parity_mode),
    .data_bits(data_bits),

    .data_out(data_out),
    .data_in(data_in),

    .start_bit_det(start_bit_det),
    .parity_error(parity_error),
    .stop_error(stop_error)
  );

  initial begin
    // init
    rst_n = 1'b0;
    spi_en = 1'b0;
    start = 1'b0;
    sclk_tick = 1'b0;
    tx_data_valid = 1'b0;
    tx_data = 8'h00;
    serial_in = 1'b0;

    // reset
    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    spi_en = 1'b1;

    
    // TEST 1: TX = A5, MSB first
    // expected serial_out: 1 0 1 0 0 1 0 1
    exp = 8'hA5;
    tx_data = exp;
    tx_data_valid = 1'b1;

    @(negedge clk);
    start = 1'b1;
    @(posedge clk);
    start = 1'b0;

    got = 8'h00;

    // sample 8 bits, on each tick capture serial_out into got[7-i]
    for (i = 0; i < WORD_W; i++) begin
      @(negedge clk);
      sclk_tick = 1'b1;
      @(negedge clk);
      got[7-i] = serial_out;
      sclk_tick = 1'b0;
    end

    // wait done pulse
    wait (done == 1'b1);
    @(negedge clk);

    if (got !== exp) begin
      $display("FAIL: TX exp=%h got=%h", exp, got);
      $finish;
    end else begin
      $display("PASS: TX exp=%h got=%h", exp, got);
    end

    tx_data_valid = 1'b0;
    repeat (5) @(negedge clk);

    $display("ALL TESTS PASS");
    $finish;
  end

endmodule
