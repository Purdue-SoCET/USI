module uart_rx_fsm_8n1 #(
  parameter int DATA_BITS = 8
) (
  input  logic                 clk,
  input  logic                 rst_n,

  // UART line input
  input  logic                 rx_line,

  // Timing pulses
  input  logic                 baud_tick,      // 1-cycle pulse each bit time
  input  logic                 half_bit_tick,  // 1-cycle pulse at half bit time (for start alignment)

  // Control/status (per diagram)
  output logic                 uart_en,
  output logic                 done,
  output logic                 err,

  output logic                 baud_wait,
  output logic                 half_bit_timer_en,
  output logic                 sample_rx_en,

  // Data sink (e.g., FIFO push)
  output logic [DATA_BITS-1:0] rx_byte_out,
  output logic                 push_rx_fifo
);

  typedef enum logic [2:0] {
    UART_RX_IDLE        = 3'd0,
    UART_RX_START_ALIGN = 3'd1,
    UART_RX_START_CHECK = 3'd2,
    UART_RX_DATA        = 3'd3,
    UART_RX_STOP        = 3'd4,
    UART_RX_PUSH        = 3'd5,
    UART_RX_ERROR       = 3'd6
  } state_t;

  state_t state, state_n;

  logic [DATA_BITS-1:0] rx_sr;
  logic [$clog2(DATA_BITS+1)-1:0] bit_cnt;

  // internal strobes
  logic bit_cnt_clr, bit_cnt_inc;
  logic shift_rx_en;

  // -------------------------
  // Next-state logic
  // -------------------------
  always_comb begin
    state_n = state;

    unique case (state)
      UART_RX_IDLE: begin
        if (!rx_line) state_n = UART_RX_START_ALIGN;
      end

      UART_RX_START_ALIGN: begin
        if (half_bit_tick) state_n = UART_RX_START_CHECK;
      end

      UART_RX_START_CHECK: begin
        // sample at the middle of the start bit
        if (!rx_line) state_n = UART_RX_DATA;   // valid start
        else          state_n = UART_RX_IDLE;   // false start
      end

      UART_RX_DATA: begin
        // shift on baud_tick; after 8 bits -> STOP
        if (baud_tick && (bit_cnt == DATA_BITS[$bits(bit_cnt)-1:0])) begin
          state_n = UART_RX_STOP;
        end
      end

      UART_RX_STOP: begin
        // check stop bit on baud_tick
        if (baud_tick) begin
          if (rx_line) state_n = UART_RX_PUSH; // stop bit = 1 OK
          else         state_n = UART_RX_ERROR;
        end
      end

      UART_RX_PUSH: begin
        state_n = UART_RX_IDLE;
      end

      UART_RX_ERROR: begin
        state_n = UART_RX_IDLE;
      end

      default: state_n = UART_RX_IDLE;
    endcase
  end

  // -------------------------
  // Output/control decode
  // -------------------------
  always_comb begin
    // defaults
    uart_en           = 1'b1;

    done              = 1'b0;
    err               = 1'b0;

    baud_wait         = 1'b0;
    half_bit_timer_en = 1'b0;
    sample_rx_en      = 1'b0;

    push_rx_fifo      = 1'b0;

    bit_cnt_clr       = 1'b0;
    bit_cnt_inc       = 1'b0;
    shift_rx_en       = 1'b0;

    unique case (state)
      UART_RX_IDLE: begin
        // done=0, err=0, monitor rx_line (implicit)
      end

      UART_RX_START_ALIGN: begin
        // half_bit_timer_en=1, bit_cnt_clr=1
        half_bit_timer_en = 1'b1;
        bit_cnt_clr       = 1'b1;
      end

      UART_RX_START_CHECK: begin
        // sample_rx_en=1 (start validation sample)
        sample_rx_en = 1'b1;
      end

      UART_RX_DATA: begin
        // sample_rx_en=1, shift_rx_en=1, bit_cnt_inc=1, baud_wait=1
        sample_rx_en = 1'b1;
        baud_wait    = 1'b1;

        // only advance/shift on baud_tick so bits remain stable between ticks
        if (baud_tick) begin
          shift_rx_en = 1'b1;
          bit_cnt_inc = 1'b1;
        end
      end

      UART_RX_STOP: begin
        // sample_rx_en=1, baud_wait=1
        sample_rx_en = 1'b1;
        baud_wait    = 1'b1;
      end

      UART_RX_PUSH: begin
        // push_rx_fifo=1, done=1
        push_rx_fifo = 1'b1;
        done         = 1'b1;
      end

      UART_RX_ERROR: begin
        // err=1
        err = 1'b1;
      end

      default: ;
    endcase
  end

  // -------------------------
  // State + datapath registers
  // -------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state   <= UART_RX_IDLE;
      rx_sr   <= '0;
      bit_cnt <= '0;
    end else begin
      state <= state_n;

      if (bit_cnt_clr) begin
        bit_cnt <= '0;
      end else if (bit_cnt_inc) begin
        bit_cnt <= bit_cnt + 1'b1;
      end

      // Shift in data bits LSB-first:
      // First sampled bit becomes rx_sr[0], next -> rx_sr[1], ... like UART framing.
      if (shift_rx_en) begin
        rx_sr <= {rx_line, rx_sr[DATA_BITS-1:1]}; // shift right, new bit into MSB?
        // If you want first bit into bit0 (common), use this instead:
        // rx_sr <= {rx_sr[DATA_BITS-2:0], rx_line}; // shift left, new bit into LSB position progression
      end
    end
  end

  assign rx_byte_out = rx_sr;

endmodule