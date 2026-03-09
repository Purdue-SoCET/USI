// ============================================================
// usi_wrapper_regs.sv
//
// Register-mapped USI wrapper with 7 registers:
//
// Reg 1: MODE_SELECT   [1:0]   00=UART, 01=SPI, 10=I2C
// Reg 2: CLOCK_DIVIDER [31:0]  protocol timing divider
// Reg 3: PARAMETERS    [31:0]  protocol-specific config
// Reg 4: WRITE_DATA    [7:0]   TX data byte; write triggers start_cmd
// Reg 5: ADDRESS       [6:0]   I2C 7-bit address
// Reg 6: ERROR         [31:0]  hardware status/error register
// Reg 7: READ_DATA     [7:0]   RX data byte
//
// Bus interface:
//   wr_en + reg_addr + wdata
//   rd_en + reg_addr -> rdata
//
// Notes:
// - UART submodules are still fixed 8N1, so UART parameter bits are stored
//   but not fully consumed yet.
// - SPI slave select is decoded from PARAMETERS[3:0] and exposed as spi_cs_n.
// - I2C "clock stretching" parameter is stored in PARAMETERS[0] but not yet
//   used by the provided i2c_ctrl module.
// - Current SPI module has no explicit spi_err output, so spi_err is tied low.
// - I2C module uses parity_error input as ACK-fail indicator, per your current RTL.
// ============================================================
module usi_wrapper_regs (
  input logic clk,
  input logic n_rst,

  // simple register bus
  input logic wr_en,
  input logic rd_en,
  input logic [2:0] reg_addr,
  input logic [31:0] wdata,
  output logic [31:0] rdata,

  // wrapper/global enable
  input logic enable,

  // external serial / checker inputs
  input logic rx_line,
  input logic start_bit_det,
  input logic parity_error,
  input logic stop_error,
  input logic [7:0] occupancy,

  // normalized outputs / debug visibility
  output logic usi_busy,
  output logic engines_off,
  output logic latch_mode,
  output logic uart_en,
  output logic i2c_en,
  output logic spi_en,

  output logic start_bit_en,
  output logic stop_bit_en,
  output logic rx_enable,
  output logic tx_enable,
  output logic serial_clk,
  output logic msb_first,
  output logic [1:0] parity_mode,
  output logic [2:0] data_bits,
  output logic [7:0] data_out,

  output logic tx_out,
  output logic [7:0] rx_byte_out,
  output logic push_rx_fifo,

  output logic [3:0] spi_cs_n,
  output logic done
);

  // ------------------------------------------------------------
  // Register map storage
  // ------------------------------------------------------------
  logic [1:0]  mode_reg;         // Reg 1
  logic [31:0] clkdiv_reg;       // Reg 2
  logic [31:0] param_reg;        // Reg 3
  logic [7:0]  write_data_reg;   // Reg 4
  logic [6:0]  addr_reg;         // Reg 5
  logic [31:0] error_reg;        // Reg 6
  logic [7:0]  read_data_reg;    // Reg 7

  logic start_cmd;
  logic rx_activity;

  // ------------------------------------------------------------
  // Parameter decode
  // ------------------------------------------------------------
  logic [2:0] uart_data_bits_cfg;
  logic       uart_stop_bits_cfg;
  logic [3:0] spi_slave_select_cfg;
  logic       i2c_clk_stretch_cfg;

  assign uart_data_bits_cfg   = param_reg[2:0];
  assign uart_stop_bits_cfg   = param_reg[3];
  assign spi_slave_select_cfg = param_reg[3:0];
  assign i2c_clk_stretch_cfg  = param_reg[0];

  // rx_activity can be driven from occupancy or external start detection.
  // Here we treat a detected start bit as receive activity.
  assign rx_activity = start_bit_det;

  // ------------------------------------------------------------
  // Divider/tick generation
  // One divider register is reused by the active protocol.
  // ------------------------------------------------------------
  logic [15:0] active_div;
  logic [15:0] div_cnt;
  logic bit_tick;
  logic half_bit_tick;

  assign active_div = (clkdiv_reg[15:0] == 16'd0) ? 16'd1 : clkdiv_reg[15:0];

  always_ff @(posedge clk or negedge n_rst) begin
    if (!n_rst) begin
      div_cnt <= 16'd0;
    end else begin
      if (div_cnt == active_div - 1)
        div_cnt <= 16'd0;
      else
        div_cnt <= div_cnt + 16'd1;
    end
  end

  assign bit_tick      = (div_cnt == active_div - 1);
  assign half_bit_tick = (div_cnt == ((active_div >> 1) == 0 ? 0 : ((active_div >> 1) - 1)));

  // ------------------------------------------------------------
  // Internal engine status wires
  // ------------------------------------------------------------
  logic uart_tx_done;
  logic uart_rx_done;
  logic uart_rx_err;
  logic uart_done_int;
  logic uart_err_int;

  logic spi_done_int;
  logic spi_err_int;

  logic i2c_done_int;
  logic i2c_ack_error;

  assign uart_done_int = uart_tx_done | uart_rx_done;
  assign uart_err_int  = uart_rx_err;
  assign spi_err_int   = 1'b0;

  // ------------------------------------------------------------
  // Control unit instance (your top module)
  // ------------------------------------------------------------
  top control_unit (
    .clk         (clk),
    .n_rst       (n_rst),
    .enable      (enable),
    .tx_req      (start_cmd),
    .rx_activity (rx_activity),
    .mode        (mode_reg),
    .uart_done   (uart_done_int),
    .uart_err    (uart_err_int),
    .i2c_done    (i2c_done_int),
    .i2c_err     (i2c_ack_error),
    .spi_done    (spi_done_int),
    .spi_err     (spi_err_int),
    .usi_busy    (usi_busy),
    .engines_off (engines_off),
    .latch_mode  (latch_mode),
    .uart_en     (uart_en),
    .i2c_en      (i2c_en),
    .spi_en      (spi_en)
  );

  // ------------------------------------------------------------
  // UART TX instance
  // ------------------------------------------------------------
  logic uart_pop_tx_fifo_unused;
  logic uart_baud_en_unused;
  logic uart_baud_wait_tx;
  logic uart_tx_mod_en_unused;

  uart_tx_fsm_8n1 uart_tx_inst (
    .clk         (clk),
    .rst_n       (n_rst),
    .tx_req      (uart_en && start_cmd),
    .tx_data_in  (write_data_reg),
    .baud_tick   (bit_tick),
    .pop_tx_fifo (uart_pop_tx_fifo_unused),
    .baud_en     (uart_baud_en_unused),
    .baud_wait   (uart_baud_wait_tx),
    .tx_out      (tx_out),
    .uart_en     (uart_tx_mod_en_unused),
    .done        (uart_tx_done)
  );

  // ------------------------------------------------------------
  // UART RX instance
  // Gate idle-high when UART RX not active
  // ------------------------------------------------------------
  logic uart_baud_wait_rx;
  logic uart_half_bit_timer_en;
  logic uart_sample_rx_en;
  logic uart_rx_mod_en_unused;
  logic rx_line_gated;

  assign rx_line_gated = uart_en ? rx_line : 1'b1;

  uart_rx_fsm_8n1 uart_rx_inst (
    .clk              (clk),
    .rst_n            (n_rst),
    .rx_line          (rx_line_gated),
    .baud_tick        (bit_tick),
    .half_bit_tick    (half_bit_tick),
    .uart_en          (uart_rx_mod_en_unused),
    .done             (uart_rx_done),
    .err              (uart_rx_err),
    .baud_wait        (uart_baud_wait_rx),
    .half_bit_timer_en(uart_half_bit_timer_en),
    .sample_rx_en     (uart_sample_rx_en),
    .rx_byte_out      (rx_byte_out),
    .push_rx_fifo     (push_rx_fifo)
  );

  // ------------------------------------------------------------
  // SPI instance
  // ------------------------------------------------------------
  logic spi_start_bit_en, spi_stop_bit_en;
  logic spi_rx_enable, spi_tx_enable;
  logic spi_serial_clk, spi_msb_first;
  logic [1:0] spi_parity_mode;
  logic [2:0] spi_data_bits;
  logic [7:0] spi_data_out;
  logic spi_busy_unused;

  spi_ctrl spi_inst (
    .clk           (clk),
    .rst_n         (n_rst),
    .spi_en        (spi_en),
    .start         (start_cmd),
    .sclk_tick     (bit_tick),
    .tx_data_valid (1'b1),
    .tx_data       (write_data_reg),
    .start_bit_det (start_bit_det),
    .parity_error  (parity_error),
    .stop_error    (stop_error),
    .start_bit_en  (spi_start_bit_en),
    .stop_bit_en   (spi_stop_bit_en),
    .rx_enable     (spi_rx_enable),
    .tx_enable     (spi_tx_enable),
    .serial_clk    (spi_serial_clk),
    .msb_first     (spi_msb_first),
    .parity_mode   (spi_parity_mode),
    .data_bits     (spi_data_bits),
    .data_out      (spi_data_out),
    .busy          (spi_busy_unused),
    .done          (spi_done_int)
  );

  // ------------------------------------------------------------
  // I2C instance
  // ------------------------------------------------------------
  logic i2c_start_bit_en, i2c_stop_bit_en;
  logic i2c_rx_enable, i2c_tx_enable;
  logic i2c_serial_clk, i2c_msb_first;
  logic [1:0] i2c_parity_mode;
  logic [2:0] i2c_data_bits;
  logic [7:0] i2c_data_out;
  logic i2c_busy_unused;

  i2c_ctrl i2c_inst (
    .clk           (clk),
    .rst_n         (n_rst),
    .i2c_en        (i2c_en),
    .start         (start_cmd),
    .scl_tick      (bit_tick),
    .addr7         (addr_reg),
    .rw            (1'b0), // could also come from a parameter bit later
    .tx_data       (write_data_reg),
    .tx_data_valid (1'b1),
    .start_bit_det (start_bit_det),
    .parity_error  (parity_error), // used as ACK-fail indicator by current RTL
    .stop_error    (stop_error),
    .start_bit_en  (i2c_start_bit_en),
    .stop_bit_en   (i2c_stop_bit_en),
    .rx_enable     (i2c_rx_enable),
    .tx_enable     (i2c_tx_enable),
    .serial_clk    (i2c_serial_clk),
    .msb_first     (i2c_msb_first),
    .parity_mode   (i2c_parity_mode),
    .data_bits     (i2c_data_bits),
    .data_out      (i2c_data_out),
    .busy          (i2c_busy_unused),
    .done          (i2c_done_int),
    .ack_error     (i2c_ack_error)
  );

  // ------------------------------------------------------------
  // SPI chip select decode from PARAMETERS register
  // PARAMETERS[3:0] selects one of 4 slaves
  // 0 -> CS0 active, 1 -> CS1 active, etc.
  // ------------------------------------------------------------
  always_comb begin
    spi_cs_n = 4'b1111;
    if (spi_en) begin
      case (spi_slave_select_cfg[1:0])
        2'd0: spi_cs_n = 4'b1110;
        2'd1: spi_cs_n = 4'b1101;
        2'd2: spi_cs_n = 4'b1011;
        2'd3: spi_cs_n = 4'b0111;
        default: spi_cs_n = 4'b1111;
      endcase
    end
  end

  // ------------------------------------------------------------
  // Register write logic
  // Writing Reg 4 triggers a 1-cycle start_cmd pulse
  // ------------------------------------------------------------
  always_ff @(posedge clk or negedge n_rst) begin
    if (!n_rst) begin
      mode_reg       <= 2'b00;
      clkdiv_reg     <= 32'd4;
      param_reg      <= 32'd0;
      write_data_reg <= 8'd0;
      addr_reg       <= 7'd0;
      read_data_reg  <= 8'd0;
      start_cmd      <= 1'b0;
    end else begin
      start_cmd <= 1'b0;

      if (wr_en) begin
        case (reg_addr)
          3'd1: mode_reg       <= wdata[1:0];
          3'd2: clkdiv_reg     <= wdata;
          3'd3: param_reg      <= wdata;
          3'd4: begin
            write_data_reg <= wdata[7:0];
            start_cmd      <= 1'b1;
          end
          3'd5: addr_reg       <= wdata[6:0];
          default: ;
        endcase
      end

      // Hardware update to read-data register
      if (uart_rx_done)
        read_data_reg <= rx_byte_out;
    end
  end

  // ------------------------------------------------------------
  // Error register hardware update
  // ------------------------------------------------------------
  always_comb begin
    error_reg = 32'd0;
    error_reg[0]    = uart_err_int;
    error_reg[1]    = i2c_ack_error;
    error_reg[2]    = spi_err_int;
    error_reg[10:3] = occupancy;
    error_reg[12:11]= mode_reg;
    error_reg[13]   = start_bit_det;
    error_reg[14]   = parity_error;
    error_reg[15]   = stop_error;
    error_reg[16]   = uart_stop_bits_cfg;
    error_reg[19:17]= uart_data_bits_cfg;
    error_reg[20]   = i2c_clk_stretch_cfg;
  end

  // ------------------------------------------------------------
  // Register read mux
  // ------------------------------------------------------------
  always_comb begin
    rdata = 32'd0;
    if (rd_en) begin
      case (reg_addr)
        3'd1: rdata = {30'd0, mode_reg};
        3'd2: rdata = clkdiv_reg;
        3'd3: rdata = param_reg;
        3'd4: rdata = {24'd0, write_data_reg};
        3'd5: rdata = {25'd0, addr_reg};
        3'd6: rdata = error_reg;
        3'd7: rdata = {24'd0, read_data_reg};
        default: rdata = 32'd0;
      endcase
    end
  end

  // ------------------------------------------------------------
  // Normalized shared outputs
  // ------------------------------------------------------------
  always_comb begin
    start_bit_en = 1'b0;
    stop_bit_en  = 1'b0;
    rx_enable    = 1'b0;
    tx_enable    = 1'b0;
    serial_clk   = 1'b0;
    msb_first    = 1'b1;
    parity_mode  = 2'b00;
    data_bits    = 3'd7;
    data_out     = 8'd0;

    if (uart_en) begin
      start_bit_en = 1'b0;
      stop_bit_en  = 1'b0;
      rx_enable    = uart_sample_rx_en;
      tx_enable    = uart_baud_wait_tx;
      serial_clk   = bit_tick;
      msb_first    = 1'b0;   // UART LSB first
      parity_mode  = 2'b00;  // 8N1
      data_bits    = 3'd7;
      data_out     = write_data_reg;
    end
    else if (spi_en) begin
      start_bit_en = spi_start_bit_en;
      stop_bit_en  = spi_stop_bit_en;
      rx_enable    = spi_rx_enable;
      tx_enable    = spi_tx_enable;
      serial_clk   = spi_serial_clk;
      msb_first    = spi_msb_first;
      parity_mode  = spi_parity_mode;
      data_bits    = spi_data_bits;
      data_out     = spi_data_out;
    end
    else if (i2c_en) begin
      start_bit_en = i2c_start_bit_en;
      stop_bit_en  = i2c_stop_bit_en;
      rx_enable    = i2c_rx_enable;
      tx_enable    = i2c_tx_enable;
      serial_clk   = i2c_serial_clk;
      msb_first    = i2c_msb_first;
      parity_mode  = i2c_parity_mode;
      data_bits    = i2c_data_bits;
      data_out     = i2c_data_out;
    end
  end

  assign done = uart_done_int | spi_done_int | i2c_done_int;

endmodule