module datapath (
  input logic clk,
  input logic n_rst,
  input logic serial_in, 
  input logic start_bit_en, // whether to check for start bit (for RX) or generate start bit (for TX)
  input logic stop_bit_en, // whether to check for stop bit (for RX) or generate stop bit (for TX)
  input logic rx_enable, // enable receiving data (shift in serial_in)
  input logic serial_clk, 
  input logic tx_enable, // enable transmitting data (shift out to serial_out)
  input logic msb_first, // whether to shift MSB first or LSB first
  input logic [1:0] parity_mode, // 00 = no parity, 01 = even parity, 10 = odd parity
  input logic [7:0] data_out, 
  output logic start_bit_det,
  output logic parity_error,
  output logic stop_error,
  output logic serial_out,
  output logic [7:0] data_in
);

typedef enum logic [2:0] { 
  IDLE = 3'd0,
  START_BIT = 3'd1,
  DATA_BITS = 3'd2,
  PARITY_BIT = 3'd3,
  STOP_BIT = 3'd4
} shift_state_t;

// Shift register state machine for RX and TX
  shift_state_t rx_state, next_rx_state, tx_state, next_tx_state;
  logic [2:0] rx_bit_cnt, next_rx_bit_cnt, tx_bit_cnt, next_tx_bit_cnt; // counts number of data bits shifted in/out (0 to 7)
  always_ff @(posedge clk, negedge n_rst) begin
    if (~n_rst) begin
      rx_state <= IDLE;
      tx_state <= IDLE;
      rx_bit_cnt <= 3'd0;
      tx_bit_cnt <= 3'd0;
    end else begin
      rx_state <= next_rx_state;
      tx_state <= next_tx_state;
      rx_bit_cnt <= next_rx_bit_cnt;
      tx_bit_cnt <= next_tx_bit_cnt;
    end
  end
  always_comb begin 
    next_rx_state = rx_state;
    next_rx_bit_cnt = rx_bit_cnt;
    unique case (rx_state)
      IDLE: begin
        next_rx_bit_cnt = 3'd0;
        if (rx_enable) begin
          next_rx_state = DATA_BITS;
        end
        else begin
          next_rx_state = IDLE;
        end
      end
      START_BIT: begin
        next_rx_state = DATA_BITS;
      end
      DATA_BITS: begin
        if (serial_clk && rx_bit_cnt < 3'd7) begin
          next_rx_bit_cnt = rx_bit_cnt + 1;
        end
        else if (serial_clk && rx_bit_cnt >= 3'd7) begin
          next_rx_bit_cnt = 3'd0;
          if (parity_mode != 2'b00) begin
            next_rx_state = PARITY_BIT;
          end
          else if (stop_bit_en) begin
            next_rx_state = STOP_BIT;
          end
          else begin
            next_rx_state = IDLE;
          end
        end
      end
      PARITY_BIT: begin
        if (serial_clk && stop_bit_en) begin 
          next_rx_state = STOP_BIT; 
        end
        else if (serial_clk) begin
          next_rx_state = IDLE;
        end
      end
      STOP_BIT: begin
        if (serial_clk) next_rx_state = IDLE;
      end
    endcase
  end
  always_comb begin
    next_tx_state = tx_state;
    next_tx_bit_cnt = tx_bit_cnt;
    unique case (tx_state)
      IDLE: begin
        next_tx_bit_cnt = 3'd0;
        if (tx_enable) begin
          next_tx_state = START_BIT;
        end
        else begin
          next_tx_state = IDLE;
        end
      end
      START_BIT: begin
        next_tx_bit_cnt = 3'b0;
        if (serial_clk || !start_bit_en) begin
          next_tx_state = DATA_BITS;
        end
      end
      DATA_BITS: begin
        if (serial_clk && tx_bit_cnt < 3'd7) begin
          next_tx_bit_cnt = tx_bit_cnt + 1;
        end
        else if (serial_clk && tx_bit_cnt >= 3'd7) begin
          next_tx_bit_cnt = 3'd0;
          if (parity_mode != 2'b00) begin
            next_tx_state = PARITY_BIT;
          end
          else if (stop_bit_en) begin
            next_tx_state = STOP_BIT;
          end
          else begin
            next_tx_state = IDLE;
          end
        end
      end
      PARITY_BIT: begin
        if (serial_clk && stop_bit_en) begin 
          next_tx_state = STOP_BIT; 
        end
        else if (serial_clk) begin
          next_tx_state = IDLE;
        end
      end
      STOP_BIT: begin
        if (serial_clk) next_tx_state = IDLE;
      end
    endcase
  end

// Start bit detection
  logic serial_in_reg;
  always_ff @(posedge clk, negedge n_rst) begin
    if (~n_rst) begin
      serial_in_reg <= 1'b1; // idle state is high
    end else begin
      serial_in_reg <= serial_in;
    end
  end
  assign start_bit_det = (serial_in_reg == 1'b1) && (serial_in == 1'b0);

// Shift register in
  logic [7:0] parallel_in, next_parallel_in; // 1 start bit + 8 data bits + 1 parity bit + 1 stop bit
  logic parity_bit, next_parity_bit;
  logic stop_bit, next_stop_bit;
  always_ff @(posedge clk, negedge n_rst) begin
    if (~n_rst) begin
      parallel_in <= 8'b0;
      parity_bit <= 1'b0;
      stop_bit <= 1'b0;
    end else begin
      parallel_in <= next_parallel_in;
      parity_bit <= next_parity_bit;
      stop_bit <= next_stop_bit;
    end
  end
  always_comb begin
    next_parallel_in = parallel_in;
    next_parity_bit = parity_bit;
    next_stop_bit = stop_bit;
    if (rx_state == IDLE) begin
      next_parallel_in = 8'b0;
      next_parity_bit = 1'b0;
      next_stop_bit = 1'b0;
    end
    else if (rx_enable && serial_clk && !msb_first && rx_state == DATA_BITS) begin
      next_parallel_in = {serial_in, parallel_in[7:1]}; // shift in new bit LSB first
    end
    else if (rx_enable && serial_clk && msb_first && rx_state == DATA_BITS) begin
      next_parallel_in = {parallel_in[6:0], serial_in}; // shift in new bit MSB first
    end
    else if (rx_enable && serial_clk && rx_state == PARITY_BIT) begin
      next_parity_bit = serial_in;
    end
    else if (rx_enable && serial_clk && rx_state == STOP_BIT) begin
      next_stop_bit = serial_in;
    end
  end
  assign data_in = parallel_in; // right-align the received data bits in data_in

// Shift register out
  logic [7:0] shift_out, next_shift_out; // holds the data bits being shifted out
  always_ff @(posedge clk, negedge n_rst) begin
    if (~n_rst) begin
      shift_out <= 8'b0;
    end else begin
      shift_out <= next_shift_out;
    end
  end
  always_comb begin // shift register output logic
    serial_out = 1'b1; // default idle high
    next_shift_out = shift_out;
    if (tx_enable) begin
      unique case (tx_state)
        IDLE: begin 
          serial_out = 1'b1;
          next_shift_out = data_out;
        end
        START_BIT: begin
          serial_out = 1'b0;
          next_shift_out = data_out;
        end
        DATA_BITS: begin
          if (!msb_first) begin
            serial_out = shift_out[0];
            if (serial_clk) begin
              next_shift_out = {1'b0, shift_out[7:1]};
            end
          end
          else begin
            serial_out = shift_out[7];
            if (serial_clk) begin
              next_shift_out = {shift_out[6:0], 1'b0};
            end
          end
        end
        PARITY_BIT: begin
          if (parity_mode == 2'b01) begin // even parity
            serial_out = (^data_out);
          end
          else if (parity_mode == 2'b10) begin // odd parity
            serial_out = ~(^data_out);
          end
        end
        STOP_BIT: serial_out = 1'b1;
      endcase
    end
  end

// Bit check for RX
  always_comb begin
    parity_error = 1'b0;
    stop_error = 1'b0;
    if (rx_state == STOP_BIT && rx_enable) begin
      if (stop_bit_en && stop_bit != 1'b1) begin
        stop_error = 1'b1; // stop bit should be high
      end
      if (parity_mode == 2'b01) begin // even parity
        if (parity_bit != (^parallel_in)) begin
          parity_error = 1'b1;
        end
      end
      else if (parity_mode == 2'b10) begin // odd parity
        if (parity_bit != (~(^parallel_in))) begin
          parity_error = 1'b1;
        end
      end
    end
  end
endmodule