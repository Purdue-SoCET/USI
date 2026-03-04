`timescale 1ns/1ps
module tb_i2c_ctrl;

  localparam int CLK_HALF = 5;

  logic clk,rst_n;

  logic i2c_en,start,scl_tick;
  logic [6:0] addr7;
  logic rw;
  logic [7:0] tx_data;
  logic tx_data_valid;

  logic start_bit_det,parity_error,stop_error;

  logic start_bit_en,stop_bit_en,rx_enable,tx_enable,serial_clk,msb_first;
  logic [1:0] parity_mode;
  logic [2:0] data_bits;
  logic [7:0] data_out;

  logic busy,done,ack_error;

  int i;

  initial clk = 1'b0;
  always #CLK_HALF clk = ~clk;

  i2c_ctrl u_ctrl (
    .clk(clk),.rst_n(rst_n),
    .i2c_en(i2c_en),
    .start(start),
    .scl_tick(scl_tick),
    .addr7(addr7),
    .rw(rw),
    .tx_data(tx_data),
    .tx_data_valid(tx_data_valid),

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
    .done(done),
    .ack_error(ack_error)
  );

  initial begin
    rst_n = 1'b0;
    i2c_en = 1'b0;
    start = 1'b0;
    scl_tick = 1'b0;
    addr7 = 7'h00;
    rw = 1'b0;
    tx_data = 8'h00;
    tx_data_valid = 1'b0;

    start_bit_det = 1'b0;
    parity_error = 1'b0;
    stop_error = 1'b0;

    repeat(4) @(negedge clk);
    rst_n = 1'b1;
    repeat(2) @(negedge clk);

    // TEST1 ACK then ACK
    i2c_en = 1'b1;
    addr7 = 7'h55;
    rw = 1'b0;
    tx_data = 8'hA5;
    tx_data_valid = 1'b1;

    @(negedge clk);
    start = 1'b1;
    @(posedge clk);
    start = 1'b0;

    wait(busy == 1'b1);
    wait(start_bit_en == 1'b1);

    for (i = 0; i < 8; i++) begin
      @(negedge clk); scl_tick = 1'b1;
      @(negedge clk); scl_tick = 1'b0;
      if (!tx_enable) begin $display("FAIL: tx_enable low during addr"); $finish; end
    end

    @(negedge clk);
    parity_error = 1'b0;
    repeat(2) @(negedge clk);
    if (!rx_enable) begin $display("FAIL: rx_enable low during addr ack"); $finish; end

    for (i = 0; i < 8; i++) begin
      @(negedge clk); scl_tick = 1'b1;
      @(negedge clk); scl_tick = 1'b0;
      if (!tx_enable) begin $display("FAIL: tx_enable low during data"); $finish; end
    end

    @(negedge clk);
    parity_error = 1'b0;
    repeat(2) @(negedge clk);
    if (!rx_enable) begin $display("FAIL: rx_enable low during data ack"); $finish; end

    wait(stop_bit_en == 1'b1);
    wait(done == 1'b1);
    @(negedge clk);

    if (ack_error) begin
      $display("FAIL: ack_error set on ACK flow");
      $finish;
    end
    $display("PASS TEST1");

    // TEST2 NACK on address
    repeat(4) @(negedge clk);

    addr7 = 7'h2A;
    rw = 1'b0;
    tx_data = 8'h5A;
    tx_data_valid = 1'b1;

    @(negedge clk);
    start = 1'b1;
    @(posedge clk);
    start = 1'b0;

    for (i = 0; i < 8; i++) begin
      @(negedge clk); scl_tick = 1'b1;
      @(negedge clk); scl_tick = 1'b0;
    end

    @(negedge clk);
    parity_error = 1'b1;
    repeat(3) @(negedge clk);

    wait(stop_bit_en == 1'b1);
    wait(done == 1'b1);
    @(negedge clk);

    if (!ack_error) begin
      $display("FAIL: ack_error not set on NACK");
      $finish;
    end
    $display("PASS TEST2");

    $display("ALL I2C CTRL TESTS PASS");
    $finish;
  end

endmodule
