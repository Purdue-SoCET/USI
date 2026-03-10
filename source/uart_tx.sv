module uart_tx_fsm_8n1 #(
  parameter int DATA_BITS = 8
) (
  input logic clk,
  input logic rst_n,
  input logic tx_req,                         // request to send one byte
  input logic [DATA_BITS-1:0] tx_data_in,    // byte to transmit
  input logic baud_tick,                      // 1-cycle pulse each bit time

  output logic pop_tx_fifo,                    // pulse to consume tx_data_in
  output logic baud_en,
  output logic baud_wait,
  output logic tx_out,
  output logic uart_en,
  output logic done
);

  typedef enum logic [2:0] {
    UART_IDLE     = 3'd0,
    UART_TX_LOAD  = 3'd1,
    UART_TX_START = 3'd2,
    UART_TX_DATA  = 3'd3,
    UART_TX_STOP  = 3'd4,
    UART_TX_DONE  = 3'd5
  } state_t;

  state_t state, state_n;

  logic [DATA_BITS-1:0] tx_sr;
  int bit_cnt;

  // internal control strobes
  logic load_tx_sr;
  logic shift_tx_en;
  logic bit_cnt_clr;
  logic bit_cnt_inc;

  // -------------------------
  // Next-state logic
  // -------------------------
  always_comb begin
    state_n = state;

    case (state)
      UART_IDLE: begin
        if (tx_req)
          state_n = UART_TX_LOAD;
      end

      UART_TX_LOAD: begin
        state_n = UART_TX_START;
      end

      UART_TX_START: begin
        // hold start bit for one baud interval
        if (baud_tick)
          state_n = UART_TX_DATA;
      end

      UART_TX_DATA: begin
        // after sending DATA_BITS bits, go to stop bit
        if (baud_tick && (bit_cnt == DATA_BITS-1))
          state_n = UART_TX_STOP;
      end

      UART_TX_STOP: begin
        // hold stop bit for one baud interval
        if (baud_tick)
          state_n = UART_TX_DONE;
      end

      UART_TX_DONE: begin
        state_n = UART_IDLE;
      end

      default: begin
        state_n = UART_IDLE;
      end
    endcase
  end

  // -------------------------
  // Output / control decode
  // -------------------------
  always_comb begin
    // defaults
    uart_en     = 1'b1;
    pop_tx_fifo = 1'b0;
    baud_en     = 1'b0;
    baud_wait   = 1'b0;
    tx_out      = 1'b1;   // UART idle line is high
    done        = 1'b0;

    load_tx_sr  = 1'b0;
    shift_tx_en = 1'b0;
    bit_cnt_clr = 1'b0;
    bit_cnt_inc = 1'b0;

    case (state)
      UART_IDLE: begin
        tx_out = 1'b1;
      end

      UART_TX_LOAD: begin
        pop_tx_fifo = 1'b1;
        load_tx_sr  = 1'b1;
        bit_cnt_clr = 1'b1;
        baud_en     = 1'b1;
        tx_out      = 1'b1;
      end

      UART_TX_START: begin
        tx_out    = 1'b0;   // start bit
        baud_wait = 1'b1;
      end

      UART_TX_DATA: begin
        tx_out = tx_sr[0];
        baud_wait = 1'b1;

        if (baud_tick) begin
          shift_tx_en = 1'b1;
          bit_cnt_inc = 1'b1;
        end
      end

      UART_TX_STOP: begin
        tx_out    = 1'b1;   // stop bit
        baud_wait = 1'b1;
      end

      UART_TX_DONE: begin
        tx_out = 1'b1;
        done   = 1'b1;
      end

      default: begin
        tx_out = 1'b1;
      end
    endcase
  end

  // -------------------------
  // State + datapath registers
  // -------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state   <= UART_IDLE;
      tx_sr   <= '0;
      bit_cnt <= 0;
    end
    else begin
      state <= state_n;

      if (bit_cnt_clr)
        bit_cnt <= 0;
      else if (bit_cnt_inc)
        bit_cnt <= bit_cnt + 1;

      if (load_tx_sr)
        tx_sr <= tx_data_in;
      else if (shift_tx_en)
        tx_sr <= {1'b0, tx_sr[DATA_BITS-1:1]};  // shift right, LSB first
    end
  end

endmodule