`timescale 1ns/1ps

module tb_usi_wrapper_regs;

  // ============================================================
  // DUT signals
  // ============================================================
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

  // ============================================================
  // DUT instantiation
  // ============================================================
  usi_wrapper_regs dut (
    .clk(clk),
    .n_rst(n_rst),

    .wr_en(wr_en),
    .rd_en(rd_en),
    .reg_addr(reg_addr),
    .wdata(wdata),
    .rdata(rdata),

    .enable(enable),

    .rx_line(rx_line),
    .start_bit_det(start_bit_det),
    .parity_error(parity_error),
    .stop_error(stop_error),
    .occupancy(occupancy),

    .usi_busy(usi_busy),
    .engines_off(engines_off),
    .latch_mode(latch_mode),
    .uart_en(uart_en),
    .i2c_en(i2c_en),
    .spi_en(spi_en),

    .start_bit_en(start_bit_en),
    .stop_bit_en(stop_bit_en),
    .rx_enable(rx_enable),
    .tx_enable(tx_enable),
    .serial_clk(serial_clk),
    .msb_first(msb_first),
    .parity_mode(parity_mode),
    .data_bits(data_bits),
    .data_out(data_out),

    .tx_out(tx_out),
    .rx_byte_out(rx_byte_out),
    .push_rx_fifo(push_rx_fifo),

    .spi_cs_n(spi_cs_n),
    .done(done)
  );

  // ============================================================
  // Clock generation
  // ============================================================
  initial clk = 0;
  always #5 clk = ~clk;  // 100 MHz

  // ============================================================
  // Simple bus tasks
  // ============================================================
  task automatic write_reg(input [2:0] addr, input [31:0] data);
    begin
      @(negedge clk);
      wr_en    = 1'b1;
      rd_en    = 1'b0;
      reg_addr = addr;
      wdata    = data;
      @(negedge clk);
      wr_en    = 1'b0;
      reg_addr = 3'd0;
      wdata    = 32'd0;
    end
  endtask

  task automatic read_reg(input [2:0] addr, output [31:0] data);
    begin
      @(negedge clk);
      wr_en    = 1'b0;
      rd_en    = 1'b1;
      reg_addr = addr;
      @(posedge clk);
      #1;
      data = rdata;
      @(negedge clk);
      rd_en    = 1'b0;
      reg_addr = 3'd0;
    end
  endtask

  // ============================================================
  // Test procedure
  // ============================================================
  logic [31:0] rd_val;

  initial begin
    // -----------------------
    // Initialize
    // -----------------------
    wr_en         = 0;
    rd_en         = 0;
    reg_addr      = 0;
    wdata         = 0;
    enable        = 0;
    rx_line       = 1'b1;
    start_bit_det = 0;
    parity_error  = 0;
    stop_error    = 0;
    occupancy     = 8'h00;
    n_rst         = 0;

    // -----------------------
    // Reset
    // -----------------------
    repeat (3) @(posedge clk);
    n_rst  = 1;
    enable = 1;

    $display("\n==== Starting usi_wrapper_regs testbench ====\n");

    // -----------------------
    // Read reset defaults
    // -----------------------
    read_reg(3'd1, rd_val);
    $display("Reg1 MODE after reset = 0x%08h", rd_val);

    read_reg(3'd2, rd_val);
    $display("Reg2 CLKDIV after reset = 0x%08h", rd_val);

    read_reg(3'd3, rd_val);
    $display("Reg3 PARAM after reset = 0x%08h", rd_val);

    // ============================================================
    // TEST 1: UART mode write/readback
    // ============================================================
    $display("\n---- TEST 1: UART mode ----");

    write_reg(3'd1, 32'h0000_0000);  // mode = UART
    write_reg(3'd2, 32'd4);          // divider
    write_reg(3'd3, 32'h0000_0007);  // UART data bits config example
    write_reg(3'd4, 32'h0000_00A5);  // TX data, triggers start_cmd

    repeat (8) @(posedge clk);

    read_reg(3'd4, rd_val);
    $display("Reg4 WRITE_DATA = 0x%08h", rd_val);

    read_reg(3'd6, rd_val);
    $display("Reg6 ERROR/STATUS = 0x%08h", rd_val);

    if (uart_en !== 1'b1)
      $error("UART mode expected uart_en=1");

    if (data_out !== 8'hA5)
      $error("UART data_out expected 0xA5, got 0x%02h", data_out);

    // Simulate receive activity for UART
    start_bit_det = 1'b1;
    @(posedge clk);
    start_bit_det = 1'b0;

    repeat (6) @(posedge clk);

    read_reg(3'd7, rd_val);
    $display("Reg7 READ_DATA after UART RX = 0x%08h", rd_val);

    // ============================================================
    // TEST 2: SPI mode + chip select decode
    // ============================================================
    $display("\n---- TEST 2: SPI mode ----");

    write_reg(3'd1, 32'h0000_0001);  // mode = SPI
    write_reg(3'd3, 32'h0000_0002);  // PARAMETERS[1:0] => CS2 active
    write_reg(3'd4, 32'h0000_003C);  // TX data, triggers start

    repeat (6) @(posedge clk);

    read_reg(3'd1, rd_val);
    $display("Reg1 MODE = 0x%08h", rd_val);
    $display("spi_cs_n = %b", spi_cs_n);

    if (spi_en !== 1'b1)
      $error("SPI mode expected spi_en=1");

    if (spi_cs_n !== 4'b1011)
      $error("Expected spi_cs_n = 1011 for slave 2, got %b", spi_cs_n);

    // ============================================================
    // TEST 3: I2C mode + address + ACK error
    // ============================================================
    $display("\n---- TEST 3: I2C mode ----");

    write_reg(3'd1, 32'h0000_0002);  // mode = I2C
    write_reg(3'd5, 32'h0000_0055);  // 7-bit address = 0x55
    write_reg(3'd3, 32'h0000_0001);  // clock stretch config example
    parity_error = 1'b1;             // used as ACK fail in your RTL
    write_reg(3'd4, 32'h0000_00C3);  // TX data, triggers start

    repeat (6) @(posedge clk);
    parity_error = 1'b0;

    if (i2c_en !== 1'b1)
      $error("I2C mode expected i2c_en=1");

    read_reg(3'd5, rd_val);
    $display("Reg5 ADDRESS = 0x%08h", rd_val);

    read_reg(3'd6, rd_val);
    $display("Reg6 ERROR/STATUS after I2C ACK fail = 0x%08h", rd_val);

    // ============================================================
    // TEST 4: external status inputs reflected in error register
    // ============================================================
    $display("\n---- TEST 4: status/error register contents ----");

    occupancy     = 8'hAB;
    start_bit_det = 1'b1;
    parity_error  = 1'b1;
    stop_error    = 1'b1;

    @(posedge clk);

    read_reg(3'd6, rd_val);
    $display("Reg6 ERROR/STATUS with external flags = 0x%08h", rd_val);

    start_bit_det = 1'b0;
    parity_error  = 1'b0;
    stop_error    = 1'b0;

    // ============================================================
    // Finish
    // ============================================================
    repeat (5) @(posedge clk);
    $display("\n==== Testbench completed ====\n");
    $finish;
  end

endmodule


// ============================================================================
// STUB MODULES
// Remove these if you already have the real RTL modules in your project.
// ============================================================================

// ----------------------------------------------------------------------------
// Stub: top control FSM
// ----------------------------------------------------------------------------
module top (
  input  logic clk,
  input  logic n_rst,
  input  logic enable,
  input  logic tx_req,
  input  logic rx_activity,
  input  logic [1:0] mode,
  input  logic uart_done,
  input  logic uart_err,
  input  logic i2c_done,
  input  logic i2c_err,
  input  logic spi_done,
  input  logic spi_err,
  output logic usi_busy,
  output logic engines_off,
  output logic latch_mode,
  output logic uart_en,
  output logic i2c_en,
  output logic spi_en
);
  always_comb begin
    uart_en     = 1'b0;
    spi_en      = 1'b0;
    i2c_en      = 1'b0;
    usi_busy    = 1'b0;
    engines_off = ~enable;
    latch_mode  = tx_req | rx_activity;

    if (enable) begin
      case (mode)
        2'b00: uart_en = 1'b1;
        2'b01: spi_en  = 1'b1;
        2'b10: i2c_en  = 1'b1;
        default: ;
      endcase

      if (tx_req || rx_activity)
        usi_busy = 1'b1;
      else if (uart_done || i2c_done || spi_done)
        usi_busy = 1'b0;
    end
  end
endmodule

// ----------------------------------------------------------------------------
// Stub: UART TX
// ----------------------------------------------------------------------------
module uart_tx_fsm_8n1 (
  input  logic clk,
  input  logic rst_n,
  input  logic tx_req,
  input  logic [7:0] tx_data_in,
  input  logic baud_tick,
  output logic pop_tx_fifo,
  output logic baud_en,
  output logic baud_wait,
  output logic tx_out,
  output logic uart_en,
  output logic done
);
  logic [1:0] cnt;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt         <= 0;
      done        <= 0;
      baud_wait   <= 0;
    end else begin
      done      <= 0;
      if (tx_req) begin
        cnt       <= 2'd2;
        baud_wait <= 1'b1;
      end else if (cnt != 0 && baud_tick) begin
        cnt <= cnt - 1'b1;
        if (cnt == 1) begin
          done      <= 1'b1;
          baud_wait <= 1'b0;
        end
      end
    end
  end

  assign pop_tx_fifo = 1'b0;
  assign baud_en     = 1'b1;
  assign tx_out      = tx_data_in[0];
  assign uart_en     = 1'b1;
endmodule

// ----------------------------------------------------------------------------
// Stub: UART RX
// ----------------------------------------------------------------------------
module uart_rx_fsm_8n1 (
  input  logic clk,
  input  logic rst_n,
  input  logic rx_line,
  input  logic baud_tick,
  input  logic half_bit_tick,
  output logic uart_en,
  output logic done,
  output logic err,
  output logic baud_wait,
  output logic half_bit_timer_en,
  output logic sample_rx_en,
  output logic [7:0] rx_byte_out,
  output logic push_rx_fifo
);
  logic [1:0] cnt;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt         <= 0;
      done        <= 0;
      push_rx_fifo<= 0;
      rx_byte_out <= 8'h00;
      err         <= 0;
    end else begin
      done         <= 0;
      push_rx_fifo <= 0;

      if (!rx_line) begin
        cnt <= 2'd2;
      end else if (cnt != 0 && baud_tick) begin
        cnt <= cnt - 1'b1;
        if (cnt == 1) begin
          done         <= 1'b1;
          push_rx_fifo <= 1'b1;
          rx_byte_out  <= 8'h5A;
        end
      end
    end
  end

  assign uart_en           = 1'b1;
  assign baud_wait         = 1'b0;
  assign half_bit_timer_en = 1'b1;
  assign sample_rx_en      = 1'b1;
endmodule

// ----------------------------------------------------------------------------
// Stub: SPI controller
// ----------------------------------------------------------------------------
module spi_ctrl (
  input  logic clk,
  input  logic rst_n,
  input  logic spi_en,
  input  logic start,
  input  logic sclk_tick,
  input  logic tx_data_valid,
  input  logic [7:0] tx_data,
  input  logic start_bit_det,
  input  logic parity_error,
  input  logic stop_error,
  output logic start_bit_en,
  output logic stop_bit_en,
  output logic rx_enable,
  output logic tx_enable,
  output logic serial_clk,
  output logic msb_first,
  output logic [1:0] parity_mode,
  output logic [2:0] data_bits,
  output logic [7:0] data_out,
  output logic busy,
  output logic done
);
  logic [1:0] cnt;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt  <= 0;
      done <= 0;
      busy <= 0;
    end else begin
      done <= 0;
      if (spi_en && start) begin
        cnt  <= 2'd2;
        busy <= 1;
      end else if (cnt != 0 && sclk_tick) begin
        cnt <= cnt - 1'b1;
        if (cnt == 1) begin
          done <= 1'b1;
          busy <= 1'b0;
        end
      end
    end
  end

  assign start_bit_en = 1'b0;
  assign stop_bit_en  = 1'b0;
  assign rx_enable    = spi_en;
  assign tx_enable    = spi_en;
  assign serial_clk   = sclk_tick;
  assign msb_first    = 1'b1;
  assign parity_mode  = 2'b00;
  assign data_bits    = 3'd7;
  assign data_out     = tx_data;
endmodule

// ----------------------------------------------------------------------------
// Stub: I2C controller
// ----------------------------------------------------------------------------
module i2c_ctrl (
  input  logic clk,
  input  logic rst_n,
  input  logic i2c_en,
  input  logic start,
  input  logic scl_tick,
  input  logic [6:0] addr7,
  input  logic rw,
  input  logic [7:0] tx_data,
  input  logic tx_data_valid,
  input  logic start_bit_det,
  input  logic parity_error,
  input  logic stop_error,
  output logic start_bit_en,
  output logic stop_bit_en,
  output logic rx_enable,
  output logic tx_enable,
  output logic serial_clk,
  output logic msb_first,
  output logic [1:0] parity_mode,
  output logic [2:0] data_bits,
  output logic [7:0] data_out,
  output logic busy,
  output logic done,
  output logic ack_error
);
  logic [1:0] cnt;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt       <= 0;
      done      <= 0;
      busy      <= 0;
      ack_error <= 0;
    end else begin
      done <= 0;
      if (i2c_en && start) begin
        cnt       <= 2'd2;
        busy      <= 1;
        ack_error <= parity_error;
      end else if (cnt != 0 && scl_tick) begin
        cnt <= cnt - 1'b1;
        if (cnt == 1) begin
          done <= 1'b1;
          busy <= 1'b0;
        end
      end
    end
  end

  assign start_bit_en = i2c_en;
  assign stop_bit_en  = i2c_en;
  assign rx_enable    = 1'b0;
  assign tx_enable    = i2c_en;
  assign serial_clk   = scl_tick;
  assign msb_first    = 1'b1;
  assign parity_mode  = 2'b00;
  assign data_bits    = 3'd7;
  assign data_out     = tx_data;
endmodule