module control_unit_tb;

  // ========================
  // Clock / Reset
  // ========================
  logic clk;
  logic n_rst;

  initial clk = 0;
  always #5 clk = ~clk; // 100 MHz

  // ========================
  // DUT Interconnect Signals
  // ========================
  logic serial_in;
  logic start_bit_en, stop_bit_en;
  logic rx_enable, tx_enable;
  logic serial_clk;
  logic msb_first;
  logic [1:0] parity_mode;

  logic start_bit_det;
  logic parity_error, stop_error;
  logic serial_out;
  logic [7:0] data_in;
  logic rx_ready, tx_ready;

  logic ctrl_unit_error;
  logic [31:0] cs_n;
  logic load, send;

  logic [7:0] buffer_occupancy;
  logic [7:0] tx_buffer_occupancy;

  logic [1:0] mode_select;
  logic [31:0] clkdiv;
  logic [31:0] configuration;

  logic [7:0] data_out;

  // ========================
  // DUT Instantiation
  // ========================
  datapath dp (
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
    .data_in(data_in),
    .rx_ready(rx_ready),
    .tx_ready(tx_ready)
  );

  control_unit cu (
    .clk(clk),
    .n_rst(n_rst),
    .mode_select(mode_select),
    .clkdiv(clkdiv),
    .configuration(configuration),
    .start_bit_det(start_bit_det),
    .parity_error(parity_error),
    .stop_error(stop_error),
    .rx_ready(rx_ready),
    .tx_ready(tx_ready),
    .buffer_occupancy(buffer_occupancy),
    .tx_buffer_occupancy(tx_buffer_occupancy),
    .ctrl_unit_error(ctrl_unit_error),
    .cs_n(cs_n),
    .parity_mode(parity_mode),
    .start_bit_en(start_bit_en),
    .stop_bit_en(stop_bit_en),
    .rx_enable(rx_enable),
    .serial_clk(serial_clk),
    .tx_enable(tx_enable),
    .msb_first(msb_first),
    .load(load),
    .send(send)
  );

  // ========================
  // Test Tracking
  // ========================
  int test_pass = 0;
  int test_fail = 0;

  task check(string name, logic cond);
    if (cond) begin
      $display("[PASS] %s", name);
      test_pass++;
    end else begin
      $display("[FAIL] %s", name);
      test_fail++;
    end
  endtask

  // ========================
  // UART RX Task
  // ========================
  task rx_byte(
    input [7:0] data
  );
    begin
      @(negedge clk);

      // Send start bit if enabled
      if (start_bit_en) begin
        serial_in = 0; // Start bit is always 0
        repeat (clkdiv) @(negedge clk);
      end

      // Send data bits
      for (int i = 0; i < 8; i++) begin
        if (msb_first) begin
          serial_in = data[7 - i];
        end else begin
          serial_in = data[i];
        end
        repeat (clkdiv) @(negedge clk);
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
        repeat (clkdiv) @(negedge clk);
      end

      // Send stop bit if enabled
      if (stop_bit_en) begin
        serial_in = 1; // Stop bit is always 1
      end
      wait (rx_ready);

      if (stop_error) $display("Stop bit error detected");
      if (parity_error) $display("Parity error detected");
      if (data_in !== data) $display("Data mismatch: expected %h, got %h", data, data_in);

    end
  endtask

  task tx_byte(
    input [7:0] data
  );
    begin
      @(negedge clk);
      tx_buffer_occupancy = 8'd1; // Indicate we have data to send
      data_out = data;
      wait (tx_ready);
      @(negedge clk);
      tx_buffer_occupancy = 8'd0; // Clear buffer occupancy after sending
      @(negedge clk);
      wait (tx_ready); // Wait for transmission to complete
    end
  endtask

  // ========================
  // SPI Transfer Task
  // ========================
  task spi_transfer(input [7:0] data);
    int i;
    for (i = 7; i >= 0; i--) begin
      serial_in = data[i];
      @(posedge serial_clk);
    end
  endtask

  // ========================
  // Reset
  // ========================
  task reset();
    n_rst = 0;
    serial_in = 1;
    buffer_occupancy = 0;
    tx_buffer_occupancy = 0;
    configuration = '0;
    mode_select = 2'b00;
    clkdiv = 32'd10; // slow down clock for testing
    repeat (5) @(negedge clk);
    n_rst = 1;
  endtask

  // ========================
  // TESTS
  // ========================
  logic [7:0] data;
  initial begin
    $dumpfile("waveform.fst");
    $dumpvars(0, datapath_tb);
    reset();
    wait(serial_clk);
    wait(~serial_clk);

    // Test 1: Basic UART RX
    mode_select = 2'b00; // UART mode
    configuration = 32'd0;
    rx_byte(8'hA5); // Send 0b10100101

    // Test 2: UART RX with even parity
    configuration[1:0] = 2'b01; // Even parity
    rx_byte(8'h3C); // Send 0b00111100

    // Test 3: UART RX with odd parity
    configuration[1:0] = 2'b10; // Odd parity
    rx_byte(8'h7B); // Send 0b01111011

    // Test 4: UART TX with no parity
    @(negedge clk);
    configuration[1:0] = 2'b00; // No parity
    tx_buffer_occupancy = 8'd3; // Indicate we have data to send
    data_out = 8'h5A; // Load data to be sent
    @(negedge clk);
    tx_buffer_occupancy = 8'd2; // Clear buffer occupancy after sending
    wait (tx_ready);
    @(negedge clk);
    data_out = 8'hC3; // Load next byte to be sent
    @(negedge clk);
    tx_buffer_occupancy = 8'd1; // Clear buffer occupancy after sending
    wait (tx_ready);
    @(negedge clk);
    data_out = 8'h16; // Clear data_out after sending
    @(negedge clk);
    tx_buffer_occupancy = 8'd0; // Clear buffer occupancy after sending
    wait (tx_ready); // Wait for transmission to complete
    @(negedge clk);

    // SPI mode test
    mode_select = 2'b01; // SPI mode
    configuration[31:0] = 32'hFFFF_FFFE; // CS_N = 0 (active low)
    repeat (5) @(negedge clk);
    wait(serial_clk);
    @(negedge clk);
    tx_buffer_occupancy = 8'd1; // Indicate we have data to send
    data_out = 8'hA5; // Load data to be sent
    @(negedge clk);
    tx_buffer_occupancy = 8'd0; // Clear buffer occupancy after sending
    data = 8'hA5; // Expected data to be received (same as sent for SPI)
    for (int i = 0; i < 8; i++) begin
        if (msb_first) begin
          serial_in = data[7 - i];
        end else begin
          serial_in = data[i];
        end
        repeat (clkdiv) @(negedge clk);
      end
    @(negedge clk);
    wait (serial_clk);
    @(negedge clk);

    $display("All tests completed.");
    $finish;
  end


endmodule