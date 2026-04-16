`timescale 1ns/1ps

module top_tb;

    logic CLK;
    logic nRST;
    logic serial_in;
    logic serial_out;
    logic serial_clk;
    logic [31:0] spi_cs_n;

    bus_protocol_if bpif();

    top DUT (
        .CLK(CLK),
        .nRST(nRST),
        .bpif(bpif),
        .serial_in(serial_in),
        .serial_out(serial_out),
        .serial_clk(serial_clk),
        .spi_cs_n(spi_cs_n)
    );

    initial CLK = 1'b0;
    always #5 CLK = ~CLK;

    logic [31:0] rdata;
    int pass = 0;
    int fail = 0;

    task reset_dut;
    begin
        nRST = 1'b0;
        bpif.wen = 1'b0;
        bpif.ren = 1'b0;
        bpif.addr = 32'h0;
        bpif.wdata = 32'h0;
        bpif.strobe = 4'hF;
        bpif.is_burst = 1'b0;
        bpif.burst_type = 2'b00;
        bpif.burst_length = 8'h00;
        bpif.secure_transfer = 1'b0;
        serial_in = 1'b0;
        repeat (4) @(posedge CLK);
        nRST = 1'b1;
        repeat (4) @(posedge CLK);
    end
    endtask

    task write_reg(input logic [31:0] addr, input logic [31:0] data);
    begin
        @(negedge CLK);
        bpif.addr   = addr;
        bpif.wdata  = data;
        bpif.strobe = 4'hF;
        bpif.wen    = 1'b1;
        bpif.ren    = 1'b0;
        @(posedge CLK);
        @(negedge CLK);
        bpif.wen    = 1'b1;
        bpif.addr   = 32'h0;
        bpif.wdata  = 32'h0;
    end
    endtask

    task read_reg(input logic [31:0] addr, output logic [31:0] data);
    begin
        @(negedge CLK);
        bpif.addr = addr;
        bpif.ren  = 1'b1;
        bpif.wen  = 1'b0;
        @(posedge CLK);
        #1;
        data = bpif.rdata;
        @(negedge CLK);
        bpif.ren  = 1'b0;
        bpif.addr = 32'h0;
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

    task pulse_serial_clk;
    begin
        force DUT.serial_clk = 1'b0;
        @(posedge CLK);
        force DUT.serial_clk = 1'b1;
        @(posedge CLK);
        force DUT.serial_clk = 1'b0;
        @(posedge CLK);
    end
    endtask

    task run_forced_uart_demo(input [7:0] tx_byte);
        integer i;
        reg [7:0] observed_bits;
    begin
        observed_bits = 8'h00;

        force DUT.data_out      = tx_byte;
        force DUT.tx_enable     = 1'b1;
        force DUT.rx_enable     = 1'b0;
        force DUT.start_bit_en  = 1'b1;
        force DUT.stop_bit_en   = 1'b1;
        force DUT.parity_mode   = 2'b00;
        force DUT.msb_first     = 1'b0;

        repeat (2) @(posedge CLK);

        $display("Forced TX byte = %h", tx_byte);
        $display("Before serial shift: serial_out = %b", serial_out);

        pulse_serial_clk();

        for (i = 0; i < 8; i++) begin
            pulse_serial_clk();
            observed_bits[i] = serial_out;
            $display("bit[%0d] serial_out = %b time=%0t", i, serial_out, $time);
        end

        pulse_serial_clk();

        $display("Observed serial bits (LSB->MSB packed) = %b", observed_bits);

        release DUT.data_out;
        release DUT.tx_enable;
        release DUT.rx_enable;
        release DUT.start_bit_en;
        release DUT.stop_bit_en;
        release DUT.parity_mode;
        release DUT.msb_first;
        release DUT.serial_clk;
    end
    endtask
    task send_uart_byte(input [7:0] data);
        integer i;
    begin
        // idle
        serial_in = 1'b1;
        repeat (2) @(posedge CLK);

        // start bit
        serial_in = 1'b0;
        repeat (2) @(posedge CLK);

        // data bits (LSB first)
        for (i = 0; i < 8; i++) begin
            serial_in = data[i];
            repeat (2) @(posedge CLK);
        end

        // stop bit
        serial_in = 1'b1;
        repeat (2) @(posedge CLK);

        $display("Sent UART byte = %h", data);
    end
    endtask
    initial begin
        reset_dut();

        write_reg(32'h0, 32'h0000_0000);
        read_reg(32'h0, rdata);
        check("mode_sel UART", 32'h0000_0000, rdata);

        write_reg(32'h4, 32'h0000_0002);
        read_reg(32'h4, rdata);
        check("clkdiv", 32'h0000_0002, rdata);

        write_reg(32'h8, 32'h0000_0000);
        read_reg(32'h8, rdata);
        check("config", 32'h0000_0000, rdata);

        write_reg(32'hC, 32'hAABBCCDD);
        read_reg(32'hC, rdata);
        check("tx_data reg", 32'hAABBCCDD, rdata);

        $display("----- RX TEST -----");

        
        force DUT.rx_enable = 1'b1;
        send_uart_byte(8'hA5);
        release DUT.rx_enable;
        run_forced_uart_demo(8'hDD);

        $display("----------------------------------");
        $display("PASS = %0d", pass);
        $display("FAIL = %0d", fail);
        $display("----------------------------------");

        #40;
        $finish;
    end

endmodule

