
`timescale 1ns/1ps

module tb_usi_fsm;

  // clock/reset
  logic clk;
  logic n_rst;

  // inputs
  logic enable;
  logic tx_req;
  logic rx_activity;
  logic [1:0] mode;

  logic uart_done, uart_err;
  logic i2c_done,  i2c_err;
  logic spi_done,  spi_err;

  // outputs
  logic usi_busy;
  logic engines_off;
  logic latch_mode;
  logic uart_en;
  logic i2c_en;
  logic spi_en;

  // DUT
  usi_fsm dut (
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

  // -------------------------
  // Clock gen: 100 MHz
  // -------------------------
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // -------------------------
  // Helpers
  // -------------------------
  task automatic clear_engine_flags();
    uart_done = 0; uart_err = 0;
    i2c_done  = 0; i2c_err  = 0;
    spi_done  = 0; spi_err  = 0;
  endtask

  task automatic idle_inputs();
    enable      = 0;
    tx_req      = 0;
    rx_activity = 0;
    mode        = 2'b00;
    clear_engine_flags();
  endtask

  task automatic apply_reset();
    n_rst = 0;
    repeat (3) @(posedge clk);
    n_rst = 1;
    @(posedge clk);
  endtask

  // Start a transaction (one-cycle request pulse)
  task automatic start_req(input logic use_tx_req, input logic [1:0] m);
    mode = m;
    @(negedge clk);
    if (use_tx_req) begin
      tx_req = 1;
      rx_activity = 0;
    end else begin
      tx_req = 0;
      rx_activity = 1;
    end
    enable = 1;
    @(posedge clk);
    @(negedge clk);
    tx_req = 0;
    rx_activity = 0;
  endtask

  // Pulse an engine done/err for one cycle
  task automatic pulse_uart_done();
    @(negedge clk); uart_done = 1;
    @(posedge clk);
    @(negedge clk); uart_done = 0;
  endtask

  task automatic pulse_uart_err();
    @(negedge clk); uart_err = 1;
    @(posedge clk);
    @(negedge clk); uart_err = 0;
  endtask

  task automatic pulse_i2c_done();
    @(negedge clk); i2c_done = 1;
    @(posedge clk);
    @(negedge clk); i2c_done = 0;
  endtask

  task automatic pulse_i2c_err();
    @(negedge clk); i2c_err = 1;
    @(posedge clk);
    @(negedge clk); i2c_err = 0;
  endtask

  task automatic pulse_spi_done();
    @(negedge clk); spi_done = 1;
    @(posedge clk);
    @(negedge clk); spi_done = 0;
  endtask

  task automatic pulse_spi_err();
    @(negedge clk); spi_err = 1;
    @(posedge clk);
    @(negedge clk); spi_err = 0;
  endtask

  // Wait until engine enable goes high (with timeout)
  task automatic wait_for_engine(
    input string name,
    input int unsigned max_cycles,
    input logic expect_uart,
    input logic expect_i2c,
    input logic expect_spi
  );
    int unsigned k;
    for (k = 0; k < max_cycles; k++) begin
      @(posedge clk);
      if ((uart_en === expect_uart) &&
          (i2c_en  === expect_i2c)  &&
          (spi_en  === expect_spi)  &&
          (usi_busy === 1'b1)) begin
        $display("[%0t] Entered %s (uart_en=%0b i2c_en=%0b spi_en=%0b busy=%0b)",
                 $time, name, uart_en, i2c_en, spi_en, usi_busy);
        return;
      end
    end
    $fatal(1, "[%0t] TIMEOUT waiting for %s", $time, name);
  endtask

  // Wait for return to idle (busy=0 and engines_off=1)
  task automatic wait_for_idle(input int unsigned max_cycles);
    int unsigned k;
    for (k = 0; k < max_cycles; k++) begin
      @(posedge clk);
      if (usi_busy === 1'b0 && engines_off === 1'b1 &&
          uart_en === 1'b0 && i2c_en === 1'b0 && spi_en === 1'b0) begin
        $display("[%0t] Returned to IDLE", $time);
        return;
      end
    end
    $fatal(1, "[%0t] TIMEOUT waiting for IDLE", $time);
  endtask

  // Simple sanity assertion each cycle
  always @(posedge clk) begin
    if (n_rst) begin
      // At most one engine enabled at a time
      if ((uart_en + i2c_en + spi_en) > 1) begin
        $fatal(1, "[%0t] ERROR: multiple engines enabled!", $time);
      end

      // If engines_off is asserted, no engine should be enabled
      if (engines_off && (uart_en || i2c_en || spi_en)) begin
        $fatal(1, "[%0t] ERROR: engines_off=1 while engine enabled!", $time);
      end

      // In DISPATCH, latch_mode should be high (your FSM does that)
      // Not perfect to detect DISPATCH without peeking state, but we can at least
      // check that latch_mode never asserts while an engine is enabled:
      if (latch_mode && (uart_en || i2c_en || spi_en)) begin
        $fatal(1, "[%0t] ERROR: latch_mode asserted while engine enabled!", $time);
      end
    end
  end

  // -------------------------
  // Main stimulus
  // -------------------------
  initial begin
    idle_inputs();
    apply_reset();

    // After reset, should be idle-ish
    if (!(usi_busy == 0 && engines_off == 1)) begin
      $fatal(1, "[%0t] Not idle after reset (busy=%0b off=%0b)", $time, usi_busy, engines_off);
    end

    // 1) UART transaction (tx_req)
    $display("\n--- TEST 1: UART tx_req -> uart_done ---");
    start_req(/*use_tx_req=*/1, /*mode=*/2'b00);

    // Expected: IDLE -> DISPATCH (busy=1 latch_mode=1) -> UART_ENGINE (uart_en=1)
    // We don't peek state; just wait to see uart_en become 1.
    wait_for_engine("UART_ENGINE", 10, 1, 0, 0);

    // finish
    pulse_uart_done();
    wait_for_idle(10);

    // 2) I2C transaction (rx_activity) ends in err
    $display("\n--- TEST 2: I2C rx_activity -> i2c_err ---");
    start_req(/*use_tx_req=*/0, /*mode=*/2'b01);
    wait_for_engine("I2C_ENGINE", 10, 0, 1, 0);

    pulse_i2c_err();
    wait_for_idle(10);

    // 3) SPI transaction (tx_req) ends in done
    $display("\n--- TEST 3: SPI tx_req -> spi_done ---");
    start_req(/*use_tx_req=*/1, /*mode=*/2'b10);
    wait_for_engine("SPI_ENGINE", 10, 0, 0, 1);

    pulse_spi_done();
    wait_for_idle(10);

    // 4) Invalid mode should safely exit back to idle
    $display("\n--- TEST 4: Invalid mode -> RETURN_IDLE -> IDLE ---");
    start_req(/*use_tx_req=*/1, /*mode=*/2'b11);

    // In your FSM: DISPATCH sees invalid mode and goes RETURN_IDLE then IDLE.
    // So it should NEVER enable any engine.
    repeat (5) @(posedge clk);
    if (uart_en || i2c_en || spi_en) begin
      $fatal(1, "[%0t] ERROR: engine enabled on invalid mode!", $time);
    end
    wait_for_idle(10);

    // 5) enable low should ignore requests
    $display("\n--- TEST 5: enable=0 blocks dispatch ---");
    mode = 2'b00;
    @(negedge clk);
    enable = 0;
    tx_req = 1;
    @(posedge clk);
    @(negedge clk);
    tx_req = 0;

    repeat (5) @(posedge clk);
    if (usi_busy) begin
      $fatal(1, "[%0t] ERROR: usi_busy asserted even though enable=0!", $time);
    end
    if (!(engines_off && !uart_en && !i2c_en && !spi_en)) begin
      $fatal(1, "[%0t] ERROR: outputs not idle with enable=0", $time);
    end

    $display("\nALL TESTS PASSED ✅");
    $finish;
  end

endmodule