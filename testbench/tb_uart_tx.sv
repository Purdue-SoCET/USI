

module tb_uart_tx_fsm_8n1;

  parameter int DATA_BITS = 8;

  logic clk;
  logic rst_n;
  logic tx_req;
  logic [DATA_BITS-1:0] tx_data_in;
  logic baud_tick;

  logic pop_tx_fifo;
  logic baud_en;
  logic baud_wait;
  logic tx_out;
  logic uart_en;
  logic done;

  // DUT
  uart_tx_fsm_8n1 #(
    .DATA_BITS(DATA_BITS)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .tx_req(tx_req),
    .tx_data_in(tx_data_in),
    .baud_tick(baud_tick),
    .pop_tx_fifo(pop_tx_fifo),
    .baud_en(baud_en),
    .baud_wait(baud_wait),
    .tx_out(tx_out),
    .uart_en(uart_en),
    .done(done)
  );

  // clock
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  // optional monitor
  initial begin
    $monitor("T=%0t  state=%0d  rst_n=%b tx_req=%b baud_tick=%b tx_out=%b pop=%b baud_en=%b baud_wait=%b done=%b bit_cnt=%0d tx_sr=%b",
             $time, dut.state, rst_n, tx_req, baud_tick, tx_out, pop_tx_fifo,
             baud_en, baud_wait, done, dut.bit_cnt, dut.tx_sr);
  end

  initial begin
    // initialize
    rst_n      = 1'b0;
    tx_req     = 1'b0;
    tx_data_in = 8'b1010_0101;
    baud_tick  = 1'b0;

    // hold reset for a couple cycles
    @(negedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // -----------------------------
    // IDLE -> LOAD
    // -----------------------------
    @(negedge clk);
    tx_req = 1'b1;

    // -----------------------------
    // LOAD -> START
    // -----------------------------
    @(negedge clk);
    tx_req = 1'b0;

    // -----------------------------
    // START -> DATA
    // -----------------------------
    @(negedge clk);
    baud_tick = 1'b1;
    @(negedge clk);
    baud_tick = 1'b0;

    // -----------------------------
    // DATA state for 8 bits
    // -----------------------------
    repeat (8) begin
      @(negedge clk);
      baud_tick = 1'b1;
      @(negedge clk);
      baud_tick = 1'b0;
    end

    // -----------------------------
    // STOP -> DONE
    // -----------------------------
    @(negedge clk);
    baud_tick = 1'b1;
    @(negedge clk);
    baud_tick = 1'b0;

    // one more cycle to observe DONE -> IDLE
    @(negedge clk);
    @(negedge clk);

    $finish;
  end

endmodule