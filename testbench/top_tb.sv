`timescale 1ns/1ps

module tb_top;
  logic clk;
  logic n_rst;
  logic enable;
  logic tx_req;
  logic rx_activity;
  logic [1:0] mode;
  logic uart_done;
  logic uart_err;
  logic i2c_done;
  logic i2c_err;
  logic spi_done;
  logic spi_err;
  logic usi_busy;
  logic engines_off;
  logic latch_mode;
  logic uart_en;
  logic i2c_en;
  logic spi_en;
  // DUT
  top dut (
    .clk(clk),
    .n_rst(n_rst),
    .enable(enable),
    .tx_req(tx_req),
    .rx_activity(rx_activity),
    .mode(mode),
    .uart_done(uart_done),
    .uart_err(uart_err),
    .i2c_done(i2c_done),
    .i2c_err(i2c_err),
    .spi_done(spi_done),
    .spi_err(spi_err),
    .usi_busy(usi_busy),
    .engines_off(engines_off),
    .latch_mode(latch_mode),
    .uart_en(uart_en),
    .i2c_en(i2c_en),
    .spi_en(spi_en)
  );

  // Clock generation
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  // Main stimulus
  initial begin
    // Initialize everything
    n_rst       = 1'b0;
    enable      = 1'b0;
    tx_req      = 1'b0;
    rx_activity = 1'b0;
    mode        = 2'b00;
    uart_done   = 1'b0;
    uart_err    = 1'b0;
    i2c_done    = 1'b0;
    i2c_err     = 1'b0;
    spi_done    = 1'b0;
    spi_err     = 1'b0;

    // Reset
    @(negedge clk);
    n_rst = 1'b0;
    @(negedge clk);
    n_rst = 1'b1;

    // -----------------------------------
    // 1) IDLE -> DISPATCH -> UART_ENGINE -> RETURN_IDLE -> IDLE
    // -----------------------------------
    @(negedge clk);
    enable = 1'b1;
    tx_req = 1'b1;
    mode   = 2'b00;

    @(negedge clk);
    tx_req = 1'b0;   // request only needs to be seen once

    @(negedge clk);
    uart_done = 1'b1;

    @(negedge clk);
    uart_done = 1'b0;
    enable    = 1'b0;

    // -----------------------------------
    // 2) IDLE -> DISPATCH -> I2C_ENGINE -> RETURN_IDLE -> IDLE
    // -----------------------------------
    @(negedge clk);
    enable      = 1'b1;
    rx_activity = 1'b1;
    mode        = 2'b01;

    @(negedge clk);
    rx_activity = 1'b0;

    @(negedge clk);
    i2c_done = 1'b1;

    @(negedge clk);
    i2c_done = 1'b0;
    enable   = 1'b0;

    // -----------------------------------
    // 3) IDLE -> DISPATCH -> SPI_ENGINE -> RETURN_IDLE -> IDLE
    // -----------------------------------
    @(negedge clk);
    enable = 1'b1;
    tx_req = 1'b1;
    mode   = 2'b10;

    @(negedge clk);
    tx_req = 1'b0;

    @(negedge clk);
    spi_done = 1'b1;

    @(negedge clk);
    spi_done = 1'b0;
    enable   = 1'b0;

    // -----------------------------------
    // 4) Optional: invalid mode goes to RETURN_IDLE
    // -----------------------------------
    @(negedge clk);
    enable = 1'b1;
    tx_req = 1'b1;
    mode   = 2'b11;

    @(negedge clk);
    tx_req  = 1'b0;
    enable  = 1'b0;

    repeat (3) @(negedge clk);

    $finish;
  end

  // Monitor
  initial begin
    $monitor("T=%0t | state=%0d | en=%b tx_req=%b rx_act=%b mode=%b | uart_done=%b i2c_done=%b spi_done=%b | usi_busy=%b engines_off=%b latch_mode=%b uart_en=%b i2c_en=%b spi_en=%b",
              $time, dut.state, enable, tx_req, rx_activity, mode,
              uart_done, i2c_done, spi_done,
              usi_busy, engines_off, latch_mode, uart_en, i2c_en, spi_en);
  end

endmodule