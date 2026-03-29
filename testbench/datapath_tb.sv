module datapath_tb;

  logic clk;
  logic n_rst;
  logic serial_in;
  logic start_bit_en;
  logic stop_bit_en;
  logic rx_enable;
  logic serial_clk;
  logic tx_enable;
  logic msb_first;
  logic [1:0] parity_mode;
  logic [7:0] data_out;
  logic start_bit_det;
  logic parity_error;
  logic stop_error;
  logic serial_out;
  logic [7:0] data_in;

  always begin
    clk = ~clk;
    #5;
  end

  datapath DUT (
    .clk(clk),
    .n_rst(n_rst),
    .serial_in(serial_in),
    .start_bit_en(start_bit_en),
    .stop_bit_en(stop_bit_en),
    .rx_enable(rx_enable),
    .serial_clk(serial_clk),
    .tx_enable(tx_enable),
    .msb_first(msb_first),
    .parity_mode(parity_mode),
    .data_out(data_out),
    .start_bit_det(start_bit_det),
    .parity_error(parity_error),
    .stop_error(stop_error),
    .serial_out(serial_out),
    .data_in(data_in)
  );

  task serial_clk_tick();
    begin
      serial_clk = 1;
      @(negedge clk);
      serial_clk = 0;
      repeat(10) @(negedge clk);
    end
  endtask

  task reset();
    begin
      n_rst = 0;
      serial_in = 1;
      start_bit_en = 0;
      stop_bit_en = 0;
      rx_enable = 0;
      serial_clk = 0;
      tx_enable = 0;
      msb_first = 0;
      parity_mode = 0;
      data_out = 0;
      serial_clk_tick();
      n_rst = 1;
      serial_clk_tick();
    end
  endtask

  task rx_byte(
    input [7:0] data, 
    input logic start_bit, 
    input logic stop_bit,
    input logic [1:0] parity, 
    input logic msb_first
  );
    begin
      @(negedge clk);
      start_bit_en = start_bit;
      stop_bit_en = stop_bit;
      parity_mode = parity;
      msb_first = msb_first;
      rx_enable = 1;

      // Send start bit if enabled
      if (start_bit) begin
        serial_in = 0; // Start bit is always 0
        serial_clk_tick();
      end

      // Send data bits
      for (int i = 0; i < 8; i++) begin
        if (msb_first) begin
          serial_in = data[7 - i];
        end else begin
          serial_in = data[i];
        end
        serial_clk_tick();
      end

      // Send parity bit if enabled
      if (parity_mode != 2'b00) begin
        logic parity_bit;
        case (parity_mode)
          2'b01: parity_bit = (^data); // Even parity
          2'b10: parity_bit = ~(^data); // Odd parity
          default: parity_bit = 0; // No parity
        endcase
        serial_in = parity_bit;
        serial_clk_tick();
      end

      // Send stop bit if enabled
      if (stop_bit) begin
        serial_in = 1; // Stop bit is always 1
        serial_clk_tick();
      end

      rx_enable = 0; // Done sending byte
    end
  endtask

  task tx_byte(
    input [7:0] data, 
    input logic start_bit, 
    input logic stop_bit,
    input logic [1:0] parity, 
    input logic msb_first, 
  );
    begin
      @(negedge clk);
      start_bit_en = start_bit;
      stop_bit_en = stop_bit;
      tx_enable = 1;
      parity_mode = parity;
      msb_first = msb_first;
      data_out = data;

      // Wait for transmission to complete
      repeat (12) serial_clk_tick();
      tx_enable = 0; // Done transmitting byte
    end
  endtask

  initial begin
    $dumpfile("waveform.fst");
    $dumpvars(0, datapath_tb);
    reset();

    // Test case 1: Receive byte with start bit, stop bit, even parity, LSB first
    rx_byte(8'hA5, 1, 1, 2'b01, 0);
    #10;

    // Test case 2: Transmit byte with start bit, stop bit, odd parity, LSB first
    tx_byte(8'h3C, 1, 1, 2'b10, 0);
    #10;

    $display("Testbench ran");
    $finish;
  end

endmodule