module uart_tx_fsm_8n1 #(
  parameter int DATA_BITS = 8
) (
  input logic clk,
  input logic rst_n,
  input logic tx_req,       // "have a byte to send"
  input logic [DATA_BITS-1:0] tx_data_in,   // byte presented when popped
  output logic pop_tx_fifo,  // pulse to pop/consume tx_data_in
  input logic baud_tick,    // 1-cycle tick each bit time
  output logic baud_en,      // per your diagram
  output logic baud_wait,    // per your diagram
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
  logic [$clog2(DATA_BITS+1)-1:0] bit_cnt; // needs to represent 0..DATA_BITS

  // Control strobes (internal)
  logic load_tx_sr;
  logic shift_tx_en;
  logic bit_cnt_clr;
  logic bit_cnt_inc;

  // -------------------------
  // Next-state logic
  // -------------------------
  always_comb begin
    state_n = state;

    unique case (state)
      UART_IDLE: begin
        if (tx_req) state_n = UART_TX_LOAD;
      end

      UART_TX_LOAD: begin
        // load+pop occur here, then move on
        state_n = UART_TX_START;
      end

      UART_TX_START: begin
        // hold start bit until the next baud tick
        if (baud_tick) state_n = UART_TX_DATA;
      end

      UART_TX_DATA: begin
        // shift out one bit per baud tick; after 8 bits go to stop
        if (baud_tick && (bit_cnt == DATA_BITS[$bits(bit_cnt)-1:0])) begin
          state_n = UART_TX_STOP;
        end
      end

      UART_TX_STOP: begin
        // hold stop bit for one baud tick then done
        if (baud_tick) state_n = UART_TX_DONE;
      end

      UART_TX_DONE: begin
        // pulse done, return to idle
        state_n = UART_IDLE;
      end

      default: state_n = UART_IDLE;
    endcase
  end

  // -------------------------
  // Output/control decode
  // -------------------------
  always_comb begin
    // defaults
    uart_en     = 1'b1;

    tx_out      = 1'b1;   // UART line idle is high
    done        = 1'b0;

    pop_tx_fifo = 1'b0;

    baud_en     = 1'b0;
    baud_wait   = 1'b0;

    load_tx_sr  = 1'b0;
    shift_tx_en = 1'b0;

    bit_cnt_clr = 1'b0;
    bit_cnt_inc = 1'b0;

    unique case (state)
      UART_IDLE: begin
        // per diagram: uart_en=1, tx_out=1, baud_en=0, done=0
        tx_out  = 1'b1;
      end

      UART_TX_LOAD: begin
        // per diagram: pop_tx_fifo=1, load_tx_sr=1, bit_cnt_clr=1, baud_en=1
        pop_tx_fifo = 1'b1;
        load_tx_sr  = 1'b1;
        bit_cnt_clr = 1'b1;
        baud_en     = 1'b1;
        tx_out      = 1'b1; // still idle-high while loading
      end

      UART_TX_START: begin
        // per diagram: tx_out=0, baud_wait=1
        tx_out    = 1'b0;   // start bit
        baud_wait = 1'b1;
      end

      UART_TX_DATA: begin
        // per diagram: tx_out=tx_sr[0], shift_tx_en=1, bit_cnt_inc=1
        tx_out = tx_sr[0];
        // Only shift/inc on baud ticks (so the bit stays stable between ticks)
        if (baud_tick) begin
          shift_tx_en = 1'b1;
          bit_cnt_inc = 1'b1;
        end
      end

      UART_TX_STOP: begin
        // per diagram: tx_out=1, baud_wait=1
        tx_out    = 1'b1;   // stop bit
        baud_wait = 1'b1;
      end

      UART_TX_DONE: begin
        // per diagram: done=1
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
      bit_cnt <= '0;
    end else begin
      state <= state_n;

      if (bit_cnt_clr) begin
        bit_cnt <= '0;
      end else if (bit_cnt_inc) begin
        bit_cnt <= bit_cnt + 1'b1;
      end

      if (load_tx_sr) begin
        tx_sr <= tx_data_in;
      end else if (shift_tx_en) begin
        // LSB-first: shift right so next bit moves into tx_sr[0]
        tx_sr <= {1'b0, tx_sr[DATA_BITS-1:1]};
      end
    end
  end

endmodule