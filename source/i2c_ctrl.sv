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

  typedef enum logic [3:0] {
    IDLE,
    START_COND,
    LOAD_ADDR,
    SEND_ADDR,
    ADDR_ACK,
    LOAD_DATA,
    SEND_DATA,
    DATA_ACK,
    STOP_COND,
    DONE_ST
  } state_t;

  state_t state,next_state;

  logic [3:0] bit_cnt,bit_cnt_n;
  logic [7:0] data_reg,data_reg_n;
  logic ack_error_n;

  assign serial_clk  = scl_tick;
  assign msb_first   = 1'b1;
  assign parity_mode = 2'b00;
  assign data_out    = data_reg;

  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) state <= IDLE;
    else state <= next_state;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      bit_cnt <= 4'd0;
      data_reg <= 8'd0;
      ack_error <= 1'b0;
    end else begin
      bit_cnt <= bit_cnt_n;
      data_reg <= data_reg_n;
      ack_error <= ack_error_n;
    end
  end

  always_comb begin
    next_state = state;
    case(state)
      IDLE: if(i2c_en && start && tx_data_valid) next_state = START_COND;
      START_COND: next_state = LOAD_ADDR;
      LOAD_ADDR: next_state = SEND_ADDR;
      SEND_ADDR: if(scl_tick && bit_cnt == 4'd7) next_state = ADDR_ACK;
      ADDR_ACK: next_state = parity_error ? STOP_COND : LOAD_DATA;
      LOAD_DATA: next_state = SEND_DATA;
      SEND_DATA: if(scl_tick && bit_cnt == 4'd7) next_state = DATA_ACK;
      DATA_ACK: next_state = STOP_COND;
      STOP_COND: next_state = DONE_ST;
      DONE_ST: next_state = IDLE;
      default: next_state = IDLE;
    endcase
  end

  always_comb begin
    bit_cnt_n = bit_cnt;
    data_reg_n = data_reg;
    ack_error_n = ack_error;

    start_bit_en = 1'b0;
    stop_bit_en = 1'b0;
    tx_enable = 1'b0;
    rx_enable = 1'b0;
    busy = 1'b0;
    done = 1'b0;

    data_bits = 3'd7;

    case(state)
      IDLE: begin
        bit_cnt_n = 4'd0;
        ack_error_n = 1'b0;
      end

      START_COND: begin
        busy = 1'b1;
        start_bit_en = 1'b1;
        bit_cnt_n = 4'd0;
      end

      LOAD_ADDR: begin
        busy = 1'b1;
        data_reg_n = {addr7,rw};
        bit_cnt_n = 4'd0;
      end

      SEND_ADDR: begin
        busy = 1'b1;
        tx_enable = 1'b1;
        if(scl_tick && bit_cnt != 4'd7) bit_cnt_n = bit_cnt + 1'b1;
      end

      ADDR_ACK: begin
        busy = 1'b1;
        rx_enable = 1'b1;
        data_bits = 3'd0;
        if(parity_error) ack_error_n = 1'b1;
        bit_cnt_n = 4'd0;
      end

      LOAD_DATA: begin
        busy = 1'b1;
        data_reg_n = tx_data;
        bit_cnt_n = 4'd0;
      end

      SEND_DATA: begin
        busy = 1'b1;
        tx_enable = 1'b1;
        if(scl_tick && bit_cnt != 4'd7) bit_cnt_n = bit_cnt + 1'b1;
      end

      DATA_ACK: begin
        busy = 1'b1;
        rx_enable = 1'b1;
        data_bits = 3'd0;
        if(parity_error) ack_error_n = 1'b1;
        bit_cnt_n = 4'd0;
      end

      STOP_COND: begin
        busy = 1'b1;
        stop_bit_en = 1'b1;
      end

      DONE_ST: begin
        done = 1'b1;
      end

      default: begin end
    endcase
  end

endmodule
