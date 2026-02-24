module spi_fsm #(
  parameter int WORD_W = 8
) (
  input  logic clk,
  input  logic rst_n,

  // control
  input  logic spi_en,
  input  logig start,// start transfer (level or pulse)
  input  logic cpol,// clock idle polarity
  input  logic cpha,// clock phase (basic support)
  input  logic sclk_tick, // one pulse per bit step from clk gen
  input  logic [WORD_W-1:0] tx_data,
  input  logic tx_data_valid,  // indicates tx_data is valid for LOAD

  // SPI pins
  input  logic miso,
  output logic mosi,
  output logic sclk,
  output logic cs_n,

  // status data out
  output logic [WORD_W-1:0] rx_data,
  output logic rx_data_valid,
  output logic busy,
  output logic done
);

typedef enum logic [2:0] {
    SPI_IDLE,
    SPI_ASSERT_CS,
    SPI_LOAD,
    SPI_TRANSFER,
    SPI_DEASSERT_CS,
    SPI_DONE
  } spi_state_t;

  spi_state_t state, next_state;
  logic [WORD_W-1:0] shift_reg;
  logic [$clog2(WORD_W+1)-1:0] bit_cnt;
  logic [WORD_W-1:0] shift_reg;
  logic [$clog2(WORD_W+1)-1:0] bit_cnt;
  logic phase;
  logic bit_step; // when advancing one bit
  logic last_step; // when finishing the word

  assign bit_step  = (state == SPI_TRANSFER) && sclk_tick;
  assign last_step = bit_step && (bit_cnt == WORD_W-1);

// state register
 always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= SPI_IDLE;
    end 
    else begin
      state <= next_state;
    end
  end


   always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= SPI_IDLE;
    end else begin
      state <= next_state;
    end
  end

    always_comb begin
    next_state = state;

    unique case (state)
      SPI_IDLE: begin
        if (spi_en && start && tx_data_valid) next_state = SPI_ASSERT_CS;
      end

      SPI_ASSERT_CS: begin
        next_state = SPI_LOAD;
      end

      SPI_LOAD: begin
        next_state = SPI_TRANSFER;
      end

      SPI_TRANSFER: begin
        if (last_step) next_state = SPI_DEASSERT_CS;
      end

      SPI_DEASSERT_CS: begin
        next_state = SPI_DONE;
      end

      SPI_DONE: begin
        next_state = SPI_IDLE;
      end

      default: next_state = SPI_IDLE;
    endcase
  end
    always_comb begin
    // defaults
    cs_n = 1'b1;
    busy = 1'b0;
    done = 1'b0;
    rx_data_valid = 1'b0;

    // SPI clock is idle unless transferring
    sclk = cpol;

    // drive MOSI from shift_reg MSB when active
    mosi = shift_reg[WORD_W-1];

    unique case (state)
      SPI_IDLE: begin
        cs_n = 1'b1;
        busy = 1'b0;
      end

      SPI_ASSERT_CS: begin
        cs_n = 1'b0;
        busy = 1'b1;
      end

      SPI_LOAD: begin
        cs_n = 1'b0;
        busy = 1'b1;
      end

      SPI_TRANSFER: begin
        cs_n = 1'b0;
        busy = 1'b1;
  
      end

      SPI_DEASSERT_CS: begin
        cs_n = 1'b1;
        busy = 1'b1;
      end

      SPI_DONE: begin
        cs_n = 1'b1;
        busy = 1'b0;
        done = 1'b1;
        rx_data_valid = 1'b1;
      end
    endcase
  end

  // Datapath: shift reg + counter

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      shift_reg <= '0;
      bit_cnt <= '0;
      phase <= 1'b0;
      rx_data <= '0;
    end else begin
      // defaults for phase when not transferring
      if (state != SPI_TRANSFER) begin
        phase <= 1'b0;
      end

      if (state == SPI_LOAD) begin
        shift_reg <= tx_data;
        bit_cnt <= '0;
        rx_data <= '0;
        phase <= 1'b0;
      end else if (state == SPI_TRANSFER && sclk_tick) begin
        if (!cpha) begin
          // CPHA=0: shift and sample each tick
          shift_reg <= {shift_reg[WORD_W-2:0], miso};
          bit_cnt <= bit_cnt + 1'b1;
        end else begin
          // CPHA=1: two-phase per bit (shift on phase=0, sample on phase=1)
          if (!phase) begin
            // shift phase
            shift_reg <= {shift_reg[WORD_W-2:0], 1'b0};
            phase <= 1'b1;
          end else begin
            // sample phase
            shift_reg[0] <= miso;
            bit_cnt <= bit_cnt + 1'b1;
            phase <= 1'b0;
          end
        end
      end

      // latch final received data at DONE
      if (state == SPI_DEASSERT_CS) begin
        rx_data <= shift_reg;
      end
    end
  end
endmodule