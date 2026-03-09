// ============================================================
// tb_usi_wrapper_regs.sv
// ============================================================
`timescale 1ns/1ps

module tb_usi_wrapper_regs;

  logic clk;
  logic n_rst;

  logic wr_en;
  logic rd_en;
  logic [2:0] reg_addr;
  logic [31:0] wdata;
  logic [31:0] rdata;

  logic enable;
  logic rx_line;
  logic start_bit_det;
  logic parity_error;
  logic stop_error;
  logic [7:0] occupancy;

  logic usi_busy;
  logic engines_off;
  logic latch_mode;
  logic uart_en;
  logic i2c_en;
  logic spi_en;

  logic start_bit_en;
  logic stop_bit_en;
  logic rx_enable;
  logic tx_enable;
  logic serial_clk;
  logic msb_first;
  logic [1:0] parity_mode;
  logic [2:0] data_bits;
  logic [7:0] data_out;

  logic tx_out;
  logic [7:0] rx_byte_out;
  logic push_rx_fifo;
  logic [3:0] spi_cs_n;
  logic done;

  usi_wrapper_regs dut (
    .clk         (clk),
    .n_rst       (n_rst),
    .wr_en       (wr_en),
    .rd_en       (rd_en),
    .reg_addr    (reg_addr),
    .wdata       (wdata),
    .rdata       (rdata),
    .enable      (enable),
    .rx_line     (rx_line),
    .start_bit_det(start_bit_det),
    .parity_error(parity_error),
    .stop_error  (stop_error),
    .occupancy   (occupancy),
    .usi_busy    (usi_busy),
    .engines_off (engines_off),
    .latch_mode  (latch_mode),
    .uart_en     (uart_en),
    .i2c_en      (i2c_en),
    .spi_en      (spi_en),
    .start_bit_en(start_bit_en),
    .stop_bit_en (stop_bit_en),
    .rx_enable   (rx_enable),
    .tx_enable   (tx_enable),
    .serial_clk  (serial_clk),
    .msb_first   (msb_first),
    .parity_mode (parity_mode),
    .data_bits   (data_bits),
    .data_out    (data_out),
    .tx_out      (tx_out),
    .rx_byte_out (rx_byte_out),
    .push_rx_fifo(push_rx_fifo),
    .spi_cs_n    (spi_cs_n),
    .done        (done)
  );

  // ----------------------------------------------------------
  // Clock
  // ----------------------------------------------------------
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // ----------------------------------------------------------
  // Bus helper tasks
  // ----------------------------------------------------------
  task automatic reg_write(input logic [2:0] addr, input logic [31:0] data);
    begin
      @(posedge clk);
      wr_en     <= 1'b1;
      rd_en     <= 1'b0;
      reg_addr  <= addr;
      wdata     <= data;
      @(posedge clk);
      wr_en     <= 1'b0;
      reg_addr  <= 3'd0;
      wdata     <= 32'd0;
    end
  endtask

  task automatic reg_read(input logic [2:0] addr);
    begin
      @(posedge clk);
      rd_en     <= 1'b1;
      wr_en     <= 1'b0;
      reg_addr  <= addr;
      @(posedge clk);
      $display("[%0t] READ reg %0d = 0x%08h", $time, addr, rdata);
      rd_en     <= 1'b0;
      reg_addr  <= 3'd0;
    end
  endtask

  // ----------------------------------------------------------
  // UART RX stimulus task
  // Sends one UART byte LSB first
  // ----------------------------------------------------------
  task automatic uart_send_byte_on_rx(input logic [7:0] b);
    int i;
    begin
      start_bit_det <= 1'b1;
      @(posedge clk);
      start_bit_det <= 1'b0;

      // start bit
      rx_line <= 1'b0;
      repeat (5) @(posedge clk);

      // data bits
      for (i = 0; i < 8; i++) begin
        rx_line <= b[i];
        repeat (5) @(posedge clk);
      end

      // stop bit
      rx_line <= 1'b1;
      repeat (5) @(posedge clk);
    end
  endtask

  // ----------------------------------------------------------
  // Stimulus
  // ----------------------------------------------------------
  initial begin
    wr_en         = 1'b0;
    rd_en         = 1'b0;
    reg_addr      = 3'd0;
    wdata         = 32'd0;
    enable        = 1'b0;
    rx_line       = 1'b1;
    start_bit_det = 1'b0;
    parity_error  = 1'b0;
    stop_error    = 1'b0;
    occupancy     = 8'h05;
    n_rst         = 1'b0;

    repeat (4) @(posedge clk);
    n_rst   = 1'b1;
    enable  = 1'b1;

    // ------------------------------------------------------
    // SPI test
    // Reg1 mode = 01
    // Reg2 clock divider
    // Reg3 parameters = slave select in [3:0]
    // Reg4 write data -> trigger start
    // ------------------------------------------------------
    $display("\n==== SPI TEST ====");
    reg_write(3'd1, 32'h0000_0001); // SPI
    reg_write(3'd2, 32'h0000_0003); // divider
    reg_write(3'd3, 32'h0000_0002); // select slave 2
    reg_write(3'd4, 32'h0000_00A5); // TX data, starts transfer

    wait (spi_en);
    $display("[%0t] SPI enabled, spi_cs_n=%b data_out=0x%02h", $time, spi_cs_n, data_out);
    wait (done);
    @(posedge clk);
    reg_read(3'd6);

    // ------------------------------------------------------
    // I2C test
    // Reg1 mode = 10
    // Reg2 divider
    // Reg3 parameters = clock stretch in [0]
    // Reg5 address
    // Reg4 write data -> trigger start
    // ------------------------------------------------------
    $display("\n==== I2C TEST ====");
    reg_write(3'd1, 32'h0000_0002); // I2C
    reg_write(3'd2, 32'h0000_0004); // divider
    reg_write(3'd3, 32'h0000_0001); // clock stretch enable stored
    reg_write(3'd5, 32'h0000_0055); // 7-bit address
    parity_error = 1'b0;            // ACK okay in current i2c_ctrl interpretation
    reg_write(3'd4, 32'h0000_003C); // TX data, starts transfer

    wait (i2c_en);
    $display("[%0t] I2C enabled, addr written, data_out=0x%02h", $time, data_out);
    wait (done);
    @(posedge clk);
    reg_read(3'd6);

    // ------------------------------------------------------
    // UART TX test
    // Reg1 mode = 00
    // Reg2 divider
    // Reg3 parameters = stop/data bits
    // Reg4 write data -> trigger start
    // ------------------------------------------------------
    $display("\n==== UART TX TEST ====");
    reg_write(3'd1, 32'h0000_0000); // UART
    reg_write(3'd2, 32'h0000_0004); // divider
    reg_write(3'd3, 32'h0000_0007); // data bits config stored
    reg_write(3'd4, 32'h0000_0096); // TX data, starts transfer

    wait (uart_en);
    $display("[%0t] UART enabled", $time);
    wait (done);
    @(posedge clk);
    reg_read(3'd6);

    // ------------------------------------------------------
    // UART RX test
    // Trigger receive activity using start_bit_det and rx_line
    // ------------------------------------------------------
    $display("\n==== UART RX TEST ====");
    reg_write(3'd1, 32'h0000_0000); // UART
    reg_write(3'd2, 32'h0000_0004); // divider

    fork
      begin
        wait (uart_en);
        uart_send_byte_on_rx(8'h53);
      end
    join_none

    wait (push_rx_fifo);
    @(posedge clk);
    $display("[%0t] UART RX complete, rx_byte_out=0x%02h", $time, rx_byte_out);
    reg_read(3'd7);

    repeat (20) @(posedge clk);
    $display("\nAll tests completed.");
    $finish;
  end

  initial begin
    $monitor("[%0t] mode? uart=%b spi=%b i2c=%b busy=%b done=%b tx_out=%b read=0x%02h",
             $time, uart_en, spi_en, i2c_en, usi_busy, done, tx_out, rx_byte_out);
  end

endmodule