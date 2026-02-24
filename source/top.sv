// USI FSM based on your diagram:
// States: IDLE -> DISPATCH -> {UART_ENGINE | I2C_ENGINE | SPI_ENGINE} -> RETURN_IDLE -> IDLE
// IDLE -> DISPATCH when: enable && (tx_req || rx_activity)
// ENGINE -> RETURN_IDLE when: <engine>_done || <engine>_err
//
// Mode encoding (from diagram):
//   UART = 2'b00
//   I2C  = 2'b01
//   SPI  = 2'b10

module usi_fsm (
  input logic clk,
  input logic n_rst,        // active-low reset per diagram label
  input logic enable,
  input logic tx_req,
  input logic rx_activity,
  input logic [1:0] mode,
  input logic uart_done,
  input logic uart_err,
  input logic i2c_done,
  input logic i2c_err,
  input logic spi_done,
  input logic spi_err,
  output logic usi_busy,
  output logic engines_off,
  output logic latch_mode,
  output logic uart_en,
  output logic i2c_en,
  output logic spi_en
);

  typedef enum logic [2:0] {
    IDLE = 3'd0,
    DISPATCH = 3'd1,
    UART_ENGINE = 3'd2,
    I2C_ENGINE = 3'd3,
    SPI_ENGINE = 3'd4,
    RETURN_IDLE = 3'd5
  } state_t;

  state_t state, next_state;
  // ----------------------------
  // State register
  // ----------------------------
  always_ff @(posedge clk, negedge !n_rst) begin
    if (!n_rst) begin
      state <= S_IDLE;
    end else begin
      state <= next_state;
    end
  end

  // ----------------------------
  // Next-state logic
  // ----------------------------
  always_comb begin
    next_state = state;
    unique case (state)
      IDLE: begin
        if (enable && (tx_req || rx_activity)) begin
          next_state = S_DISPATCH;
        end
      end

      DISPATCH: begin
        // Branch based on mode
        unique case (mode)
          2'b00: next_state = UART_ENGINE; // UART
          2'b01: next_state = I2C_ENGINE;  // I2C
          2'b10: next_state = SPI_ENGINE;  // SPI
          default: next_state = RETURN_IDLE; // invalid mode -> safe exit
        endcase
      end
      UART_ENGINE: begin
        if (uart_done || uart_err) next_state = RETURN_IDLE;
      end
      I2C_ENGINE: begin
        if (i2c_done || i2c_err) next_state = RETURN_IDLE;
      end
      SPI_ENGINE: begin
        if (spi_done || spi_err) next_state = RETURN_IDLE;
      end
      RETURN_IDLE: begin
        next_state = IDLE;
      end
      default: begin
        next_state = IDLE;
      end
    endcase
  end

  // ----------------------------
  // Output logic (Moore-style: outputs depend only on state)
  // ----------------------------
  always_comb begin
    // defaults (safe)
    usi_busy    = 1'b0;
    engines_off = 1'b1;
    latch_mode  = 1'b0;

    uart_en     = 1'b0;
    i2c_en      = 1'b0;
    spi_en      = 1'b0;

    unique case (state)
      IDLE: begin
        // diagram: usi_busy=0, engines_off=1
        usi_busy    = 1'b0;
        engines_off = 1'b1;
      end

      DISPATCH: begin
        // diagram: usi_busy=1, latch_mode=1
        usi_busy    = 1'b1;
        engines_off = 1'b1;   // engines not enabled yet
        latch_mode  = 1'b1;
      end

      UART_ENGINE: begin
        // diagram: usi_busy=1, uart_en=1
        usi_busy    = 1'b1;
        engines_off = 1'b0;
        uart_en     = 1'b1;
      end

      I2C_ENGINE: begin
        // diagram: usi_busy=1, i2c_en=1
        usi_busy    = 1'b1;
        engines_off = 1'b0;
        i2c_en      = 1'b1;
      end

      SPI_ENGINE: begin
        // diagram: usi_busy=1, spi_en=1
        usi_busy    = 1'b1;
        engines_off = 1'b0;
        spi_en      = 1'b1;
      end

      RETURN_IDLE: begin
        // diagram: usi_busy=0, engines_off=1
        usi_busy    = 1'b0;
        engines_off = 1'b1;
      end
      default: begin
        // keep safe defaults
      end
    endcase
  end

endmodule
