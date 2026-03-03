module i2c_fsm #(
  parameter int ADDR_W = 7,
  parameter int DATA_W = 8
) (
  input  logic clk,
  input  logic rst_n,
  // control
  input  logic i2c_en,
  input  logic start,          // start transaction (level or pulse)
  input  logic [ADDR_W-1:0] addr7,          // 7-bit address
  input  logic [DATA_W-1:0] tx_data,
  input  logic tx_data_valid,
  // timing from clock generator
  input  logic scl_tick,        // one pulse per "half step" or "bit step"
  input  logic  scl_high_phase,  // 1 when SCL should be high during this tick, 0 when low
  // line sense
  input  logic sda_in,
  input  logic scl_in,
  // line drive (open drain)
  output logic sda_drive_low,
  output logic scl_drive_low,
  // status
  output logic busy,
  output logic done,
  output logic ack_error
);

  // State machine
  typedef enum logic [3:0] {
    I2C_IDLE,
    I2C_START_A,// prepare START while SCL high: SDA 1->0
    I2C_START_B, // hold after START, then go to sending bits
    I2C_SEND_BIT,// shift out address/data bits while SCL low, sample on SCL high
    I2C_RECV_ACK, // release SDA, sample ACK on SCL high
    I2C_STOP_A,// drive SDA low while SCL low
    I2C_STOP_B,// release SCL high, then SDA 0->1
    I2C_DONE,
    I2C_ERROR
  } i2c_state_t;

  i2c_state_t state, next_state;

  // Internal registers
  logic [7:0] shift_reg;
  logic [3:0] bit_cnt;// counts 0..7
  logic       sending_addr; // 1: sending address byte, 0: sending data byte
  logic       ack_sampled;// helper
  logic       ack_ok; // ack result

  // "advance" when we get ticks in SCL low or high phases
  wire tick_low  = scl_tick && (scl_high_phase == 1'b0);
  wire tick_high = scl_tick && (scl_high_phase == 1'b1);

  // State register
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= I2C_IDLE;
    end else begin
      state <= next_state;
    end
  end

  // Next-state logic
  always_comb begin
    next_state = state;

    unique case (state)
      I2C_IDLE: begin
        if (i2c_en && start && tx_data_valid)
          next_state = I2C_START_A;
      end

      // START: need SCL high and SDA pulled low
      I2C_START_A: begin
        // wait for a high-phase tick to ensure we align to SCL high
        if (tick_high) next_state = I2C_START_B;
      end

      I2C_START_B: begin
        // move to bit sending on next low phase
        if (tick_low) next_state = I2C_SEND_BIT;
      end

      I2C_SEND_BIT: begin
        // After 8 bits, go to ACK receive
        if (tick_high && (bit_cnt == 4'd7)) next_state = I2C_RECV_ACK;
      end

      I2C_RECV_ACK: begin
        // sample ACK on high phase, then decide
        if (tick_high && ack_sampled) begin
          if (ack_ok) begin
            // if just finished address, send data next
            if (sending_addr)
              next_state = I2C_SEND_BIT;
            else
              next_state = I2C_STOP_A;
          end else begin
            next_state = I2C_ERROR;
          end
        end
      end

      I2C_STOP_A: begin
        // ensure we are in low phase to set SDA low
        if (tick_low) next_state = I2C_STOP_B;
      end

      I2C_STOP_B: begin
        // STOP condition happens when SCL high and SDA goes low->high
        if (tick_high) next_state = I2C_DONE;
      end

      I2C_DONE: begin
        next_state = I2C_IDLE;
      end

      I2C_ERROR: begin
        // still issue STOP to release bus
        if (tick_low) next_state = I2C_STOP_B;
      end

      default: next_state = I2C_IDLE;
    endcase
  end

  // Outputs (defaults)

  always_comb begin
    // open drain defaults: release lines
    sda_drive_low = 1'b0;
    scl_drive_low = 1'b0;

    busy      = 1'b0;
    done      = 1'b0;
    ack_error = 1'b0;

    unique case (state)
      I2C_IDLE: begin
        busy = 1'b0;
      end

      I2C_START_A: begin
        busy = 1'b1;
        // START: while SCL is high, pull SDA low
        sda_drive_low = 1'b1;
      end

      I2C_START_B: begin
        busy = 1'b1;
        // hold SDA low after START
        sda_drive_low = 1'b1;
      end

      I2C_SEND_BIT: begin
        busy = 1'b1;
        if (shift_reg[7] == 1'b0)
          sda_drive_low = 1'b1;
        else
          sda_drive_low = 1'b0;
      end

      I2C_RECV_ACK: begin
        busy = 1'b1;
        // release SDA to let slave drive ACK
        sda_drive_low = 1'b0;
      end

      I2C_STOP_A: begin
        busy = 1'b1;
        // Before STOP, ensure SDA low while SCL low
        sda_drive_low = 1'b1;
      end

      I2C_STOP_B: begin
        busy = 1'b1;
        // STOP: when SCL high, release SDA (low->high due to pull-up)
        sda_drive_low = 1'b0;
      end

      I2C_DONE: begin
        busy = 1'b0;
        done = 1'b1;
      end

      I2C_ERROR: begin
        busy      = 1'b1;
        ack_error = 1'b1;
        // keep SDA released; we will go to STOP_B to release bus
        sda_drive_low = 1'b0;
      end
    endcase
  end

  // Datapath and counters
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      shift_reg<= 8'hFF;
      bit_cnt<= 4'd0;
      sending_addr <= 1'b1;
      ack_sampled <= 1'b0;
      ack_ok <= 1'b0;
    end else begin
      ack_sampled <= 1'b0;

      if (state == I2C_IDLE) begin
        bit_cnt<= 4'd0;
        sending_addr <= 1'b1;
        shift_reg<= 8'hFF;
      end

      // After START, load address byte
      if (state == I2C_START_B && tick_low) begin
        shift_reg<= {addr7, 1'b0}; // write transaction
        bit_cnt<= 4'd0;
        sending_addr <= 1'b1;
      end

      if (state == I2C_SEND_BIT) begin
        // advance one bit each low phase tick
        if (tick_low) begin
          shift_reg <= {shift_reg[6:0], 1'b0};
          if (bit_cnt != 4'd7)
            bit_cnt <= bit_cnt + 1'b1;
          else
            bit_cnt <= 4'd7; // hold; transition to ACK happens on high tick
        end
      end

      if (state == I2C_RECV_ACK) begin
        // sample ACK on high phase
        if (tick_high) begin
          ack_ok<= (sda_in == 1'b0); // ACK is 0
          ack_sampled <= 1'b1;

          if (sending_addr) begin
            // prepare to send data next
            shift_reg<= tx_data;
            bit_cnt <= 4'd0;
            sending_addr <= 1'b0;
          end
        end
      end

      // If error, keep flags; STOP will release the bus
      if (state == I2C_ERROR) begin
      end
    end
  end

endmodule
