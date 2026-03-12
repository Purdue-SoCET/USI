<<<<<<< HEAD
`timescale 1ns/1ps

module tb_top;

  logic clk;
  logic n_rst;
  logic enable;
  logic tx_req;
  logic rx_activity;
  logic [1:0] mode;
  logic uart_done;
  logic uart_err;
  logic i2c_done;
  logic i2c_err;
  logic spi_done;
  logic spi_err;
  logic usi_busy;
  logic engines_off;
  logic latch_mode;
  logic uart_en;
  logic i2c_en;
  logic spi_en;

  // DUT
  top dut (
    .clk(clk),
    .n_rst(n_rst),
    .enable(enable),
    .tx_req(tx_req),
    .rx_activity(rx_activity),
    .mode(mode),
    .uart_done(uart_done),
    .uart_err(uart_err),
    .i2c_done(i2c_done),
    .i2c_err(i2c_err),
    .spi_done(spi_done),
    .spi_err(spi_err),
    .usi_busy(usi_busy),
    .engines_off(engines_off),
    .latch_mode(latch_mode),
    .uart_en(uart_en),
    .i2c_en(i2c_en),
    .spi_en(spi_en)
  );

  // Clock generation
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  // Main stimulus
  initial begin
    // Initialize everything
    n_rst       = 1'b0;
    enable      = 1'b0;
    tx_req      = 1'b0;
    rx_activity = 1'b0;
    mode        = 2'b00;
    uart_done   = 1'b0;
    uart_err    = 1'b0;
    i2c_done    = 1'b0;
    i2c_err     = 1'b0;
    spi_done    = 1'b0;
    spi_err     = 1'b0;

    // Reset
    @(negedge clk);
    n_rst = 1'b0;
    @(negedge clk);
    n_rst = 1'b1;

    // -----------------------------------
    // 1) IDLE -> DISPATCH -> UART_ENGINE -> RETURN_IDLE -> IDLE
    // -----------------------------------
    @(negedge clk);
    enable = 1'b1;
    tx_req = 1'b1;
    mode   = 2'b00;

    @(negedge clk);
    tx_req = 1'b0;   // request only needs to be seen once

    @(negedge clk);
    uart_done = 1'b1;

    @(negedge clk);
    uart_done = 1'b0;
    enable    = 1'b0;

    // -----------------------------------
    // 2) IDLE -> DISPATCH -> I2C_ENGINE -> RETURN_IDLE -> IDLE
    // -----------------------------------
    @(negedge clk);
    enable      = 1'b1;
    rx_activity = 1'b1;
    mode        = 2'b01;

    @(negedge clk);
    rx_activity = 1'b0;

    @(negedge clk);
    i2c_done = 1'b1;

    @(negedge clk);
    i2c_done = 1'b0;
    enable   = 1'b0;

    // -----------------------------------
    // 3) IDLE -> DISPATCH -> SPI_ENGINE -> RETURN_IDLE -> IDLE
    // -----------------------------------
    @(negedge clk);
    enable = 1'b1;
    tx_req = 1'b1;
    mode   = 2'b10;

    @(negedge clk);
    tx_req = 1'b0;

    @(negedge clk);
    spi_done = 1'b1;

    @(negedge clk);
    spi_done = 1'b0;
    enable   = 1'b0;

    // -----------------------------------
    // 4) Optional: invalid mode goes to RETURN_IDLE
    // -----------------------------------
    @(negedge clk);
    enable = 1'b1;
    tx_req = 1'b1;
    mode   = 2'b11;

    @(negedge clk);
    tx_req  = 1'b0;
    enable  = 1'b0;

    repeat (3) @(negedge clk);

    $finish;
  end

  // Monitor
  initial begin
    $monitor("T=%0t | state=%0d | en=%b tx_req=%b rx_act=%b mode=%b | uart_done=%b i2c_done=%b spi_done=%b | usi_busy=%b engines_off=%b latch_mode=%b uart_en=%b i2c_en=%b spi_en=%b",
              $time, dut.state, enable, tx_req, rx_activity, mode,
              uart_done, i2c_done, spi_done,
              usi_busy, engines_off, latch_mode, uart_en, i2c_en, spi_en);
  end
=======
module top_tb;

    logic CLK;
    logic nRST;

    logic load;
    logic send;
    logic [7:0] data_in;
    logic [7:0] data_out;
    logic [7:0] buffer_occupancy;

    bus_protocol_if bpif();

    top DUT (
        .CLK(CLK),
        .nRST(nRST),
        .bpif(bpif),
        .load(load),
        .send(send),
        .data_in(data_in),
        .data_out(data_out),
        .buffer_occupancy(buffer_occupancy)
    );

    initial CLK = 1'b0;
    always #5 CLK = ~CLK;

    int pass = 0;
    int fail = 0;

    logic [31:0] rdata;
    logic [7:0] b0, b1, b2, b3;

    task reset_dut;
    begin
        nRST = 1'b0;
        bpif.wen = 1'b0;
        bpif.ren = 1'b0;
        bpif.addr = 32'h0;
        bpif.wdata = 32'h0;
        bpif.strobe = 4'hF;
        load = 1'b0;
        send = 1'b0;
        data_in = 8'h00;

        repeat (2) @(posedge CLK);
        nRST = 1'b1;
        @(posedge CLK);
    end
    endtask

    task write(input logic [31:0] addr, input logic [31:0] data, input logic [3:0] strb);
    begin
        @(negedge CLK);
        bpif.addr   = addr;
        bpif.wdata  = data;
        bpif.strobe = strb;
        bpif.wen    = 1'b1;
        bpif.ren    = 1'b0;

        @(posedge CLK);
        @(negedge CLK);
        bpif.wen    = 1'b0;
        bpif.addr   = 32'h0;
        bpif.wdata  = 32'h0;
        bpif.strobe = 4'hF;
    end
    endtask

    task read(input logic [31:0] addr, output logic [31:0] data);
    begin
        @(negedge CLK);
        bpif.addr = addr;
        bpif.ren  = 1'b1;
        bpif.wen  = 1'b0;

        #1;
        data = bpif.rdata;

        @(posedge CLK);
        @(negedge CLK);
        bpif.ren  = 1'b0;
        bpif.addr = 32'h0;
    end
    endtask

    task load_byte(input logic [7:0] din);
    begin
        @(negedge CLK);
        data_in = din;
        load    = 1'b1;

        @(posedge CLK);
        @(negedge CLK);
        load    = 1'b0;
        data_in = 8'h00;
    end
    endtask

    task send_byte(output logic [7:0] dout);
    begin
        @(negedge CLK);
        send = 1'b1;

        #1;
        dout = data_out;

        @(posedge CLK);
        @(negedge CLK);
        send = 1'b0;
    end
    endtask

    task check(input string name, input logic [31:0] expected, input logic [31:0] actual);
    begin
        if (expected === actual) begin
            $display("PASS: %s exp=%h act=%h", name, expected, actual);
            pass++;
        end
        else begin
            $display("FAIL: %s exp=%h act=%h", name, expected, actual);
            fail++;
        end
    end
    endtask

    initial begin
        $dumpfile("waveform.fst");
        $dumpvars(0, top_tb);
        reset_dut();

        write(32'h0, 32'h2, 4'hF);
        read(32'h0, rdata);
        check("mode_sel", 32'h00000002, rdata);

        write(32'h4, 32'h12345678, 4'hF);
        read(32'h4, rdata);
        check("clkdiv", 32'h12345678, rdata);

        write(32'h8, 32'hAAAAAAAA, 4'hF);
        read(32'h8, rdata);
        check("configuration", 32'hAAAAAAAA, rdata);

        load_byte(8'h11);
        load_byte(8'h22);
        load_byte(8'h33);
        load_byte(8'h44);

        read(32'h10, rdata);
        check("RX pop", 32'h44332211, rdata);

        write(32'hC, 32'hAABBCCDD, 4'hF);

        send_byte(b0);
        send_byte(b1);
        send_byte(b2);
        send_byte(b3);

        check("TX byte0", 32'h000000DD, {24'h0, b0});
        check("TX byte1", 32'h000000CC, {24'h0, b1});
        check("TX byte2", 32'h000000BB, {24'h0, b2});
        check("TX byte3", 32'h000000AA, {24'h0, b3});

        load_byte(8'h55);
        load_byte(8'h66);
        @(posedge CLK);
        check("buffer occupancy", 32'h00000002, {24'h0, buffer_occupancy});

        write(32'h20, 32'hDEADBEEF, 4'hF);
        if (bpif.error) begin
            $display("PASS: bus error detected");
            pass++;
        end
        else begin
            $display("FAIL: bus error not detected");
            fail++;
        end

        write(32'h4, 32'hFFFFFFFF, 4'b0011);
        if (bpif.error) begin
            $display("PASS: strobe error detected");
            pass++;
        end
        else begin
            $display("FAIL: strobe error not detected");
            fail++;
        end

        $display("----------------------------------");
        $display("TEST COMPLETE");
        $display("PASS = %0d", pass);
        $display("FAIL = %0d", fail);
        $display("----------------------------------");

        if (fail == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        #20;
        $finish;
    end
>>>>>>> 30a04555965cfb7c8a57236a28b0dcacbc21b54b

endmodule