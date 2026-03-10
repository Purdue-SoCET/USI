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

  typedef enum logic [1:0] {IDLE, LOAD, TRANSFER, DONE} state_t;
  state_t state, next_state;

  logic [3:0] bit_cnt;
  logic [7:0] tx_reg;

  // state register
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) state <= IDLE;
    else state <= next_state;
  end

  // next state
  always_comb begin
    next_state = state;
    case(state)
      IDLE:
        if(spi_en && start && tx_data_valid)
          next_state = LOAD;
      LOAD:
          next_state = TRANSFER;
      TRANSFER:
        if(bit_cnt == 4'd7)
          next_state = DONE;
      DONE:
          next_state = IDLE;
      default:
          next_state = IDLE;
    endcase
  end

  // bit counter
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
      bit_cnt <= 4'd0;
    else if(state == TRANSFER && sclk_tick)
      bit_cnt <= bit_cnt + 1'b1;
    else if(state != TRANSFER)
      bit_cnt <= 4'd0;
  end

  // latch tx_data into local register
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
      tx_reg <= 8'd0;
    else if(state == LOAD)
      tx_reg <= tx_data;
  end

  // outputs
  always_comb begin
    start_bit_en = 1'b0;
    stop_bit_en  = 1'b0;
    parity_mode  = 2'b00;
    msb_first    = 1'b1;
    data_bits    = 3'd7;    
    serial_clk   = sclk_tick;

    tx_enable = (state == TRANSFER);
    rx_enable = (state == TRANSFER);

    busy = (state == TRANSFER);
    done = (state == DONE);

    data_out = tx_reg;     
  end

endmodule
