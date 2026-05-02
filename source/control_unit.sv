module control_unit (
  input logic clk, // system clock
  input logic n_rst, // active low reset
  input logic [1:0] mode_select, // 00 = UART, 01 = SPI, 10 = I2C (no I2C support in this version)
  input logic [31:0] clkdiv, // clock divider value to generate serial_clk from clk
  input logic [31:0] configuration, // configuration bits for parity mode, MSB/LSB first, etc.
  input logic start_bit_det, // from datapath, indicates a start bit has been detected (for RX)
  input logic parity_error, // from datapath, indicates a parity error was detected in the received data
  input logic stop_error, // from datapath, indicates a stop bit error was detected in the received data
  input logic rx_ready, // from datapath, one cycle pulse indicates a full byte has been received and is ready to be loaded into the buffer
  input logic tx_ready, // from datapath, indicates tx shift register is ready for the next byte to transmit
  input logic [7:0] buffer_occupancy, // number of bytes currently in the data buffer
  input logic [7:0] tx_buffer_occupancy, // number of tx bytes currently in the data buffer
  output logic ctrl_unit_error, // indicates an error in the control unit (e.g. invalid mode select, parity/stop error in UART mode, etc.)
  output logic [31:0] cs_n, // chip select signals for SPI mode (active low, one bit per slave device)
  output logic [1:0] parity_mode, // 00 = no parity, 01 = even parity, 10 = odd parity (only used in UART mode)
  output logic start_bit_en, // enable signal to datapath to indicate whether to check for start bit (for RX) or generate start bit (for TX)
  output logic stop_bit_en, // enable signal to datapath to indicate whether to check for stop bit (for RX) or generate stop bit (for TX)
  output logic rx_enable, // enable signal to datapath to start receiving data (shifting in serial_in)
  output logic serial_clk, // one cycle pulse, generated serial clock for shifting data in/out of datapath, derived from clk and clkdiv
  output logic tx_enable, // enable signal to datapath to start transmitting data (shifting out serial_out)
  output logic msb_first, // signal to datapath to indicate whether to shift MSB first or LSB first
  output logic load, // one cycle pulse signal to data buffer to load the received byte from datapath into the buffer
  output logic send // one cycle pulse signal to data buffer to send the next byte from the buffer to datapath for transmission
);

  typedef enum logic [1:0] { 
    IDLE, UART, SPI
  } state_t;

  state_t state, next_state;

  always_ff @(posedge clk, negedge n_rst) begin
    if (~n_rst) begin
      state <= IDLE;
    end else begin
      state <= next_state;
    end
  end

// State machine transitions
  always_comb begin
    next_state = state;
    unique casez (state)
      IDLE: begin
        if (mode_select == 2'b00) begin
          next_state = UART;
        end else if (mode_select == 2'b01) begin
          next_state = SPI;
        end
      end
      UART: begin
        if (mode_select != 2'b00) begin
          next_state = IDLE;
        end
      end
      SPI: begin
        if (mode_select != 2'b01) begin
          next_state = IDLE;
        end
      end
    endcase
  end

// State outputs
  always_comb begin
    ctrl_unit_error = 1'b0;
    cs_n = 32'd0;
    parity_mode = 2'd0;
    start_bit_en = 1'b0;
    stop_bit_en = 1'b0;
    rx_enable = 1'b0;
    tx_enable = 1'b0;
    msb_first = 1'b0;
    load = 1'b0;
    send = 1'b0;
    unique casez (state)
      IDLE: begin
      end
      UART: begin
        ctrl_unit_error = parity_error || stop_error;
        parity_mode = configuration[1:0];
        start_bit_en = 1'b1;
        stop_bit_en = 1'b1;
        if (start_bit_det) begin
          rx_enable = 1'b1;
        end
        if (tx_buffer_occupancy > 8'd0) begin
          tx_enable = 1'b1;
          if (tx_ready) begin
            send = 1'b1;
          end
        end
        if (rx_ready) begin
          load = 1'b1;
        end
        msb_first = 1'b0;
      end
      SPI: begin
        cs_n = configuration[31:0];
        if (tx_buffer_occupancy > 8'd0) begin
          tx_enable = 1'b1;
          rx_enable = 1'b1; // for SPI, we shift data in and out simultaneously, so rx_enable is also asserted when we have data to send
          if (tx_ready) begin
            send = 1'b1;
          end
        end
        if (rx_ready) begin
          load = 1'b1;
        end
        msb_first = 1'b1;
      end
    endcase
  end
// Clock Divider
  logic [31:0] clkdiv_cnt, next_clkdiv_cnt;
  always_ff @(posedge clk, negedge n_rst) begin
    if (~n_rst) begin
      clkdiv_cnt <= 32'd0;
    end else begin
      clkdiv_cnt <= next_clkdiv_cnt;
    end
  end

  always_comb begin
    next_clkdiv_cnt = clkdiv_cnt + 1;
    if (clkdiv_cnt >= clkdiv) begin
      next_clkdiv_cnt = 32'd1;
    end
  end

  assign serial_clk = (clkdiv_cnt == 32'd1) ? 1'b1 : 1'b0;

endmodule
