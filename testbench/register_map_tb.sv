`timescale 1ns/1ps

module reg_map_tb;
    localparam int RX_FIFO_SIZE = 16;
    localparam int TX_FIFO_SIZE = 16;
    localparam int CLKDIV_BITS = 16;

    logic CLK;
    logic nRST;
    bus_protocol_if bpif();

    int pass_count = 0;
    int fail_count = 0;

    logic tx_full, tx_empty, rx_full, rx_empty;
    logic [$clog2(TX_FIFO_SIZE+1)-1:0] tx_count;
    logic [$clog2(RX_FIFO_SIZE+1)-1:0] rx_count;
    logic [31:0] rx_rdata;
    logic protocol_busy, protocol_done, protocol_error;
    logic [2:0] mode_sel;
    logic [CLKDIV_BITS-1:0] clkdiv;
    logic [31:0] tx_wdata;
    logic [31:0] transfer_count;
    logic [7:0] spi_config, i2c_config;
    logic [6:0] i2c_addr;
    logic [5:0] spi_length;
    logic error_clear, done_clear, start, abort;
    logic tx_wen, rx_ren, tx_flush, rx_flush;
    logic [31:0] rdata;

    register_map #(
        .RX_FIFO_SIZE(RX_FIFO_SIZE),
        .TX_FIFO_SIZE(TX_FIFO_SIZE),
        .CLKDIV_BITS(CLKDIV_BITS)
    ) DUT (.*);

    always #5 CLK = ~CLK;

    task reset();
    begin
        nRST = 0;
        #20;
        nRST = 1;
    end
    endtask

  
    task write(
        input [31:0] addr, // which address in the bus
        input [31:0] data, // data input in the bus
        input [3:0] strb, // require 1111 since use all 32 bits
        input expected_error // 1 if we expect error, 0 if we don't
    );
    begin
        // 
        @(negedge CLK);
        bpif.addr = addr;
        bpif.wdata = data;
        bpif.strobe = strb;
        bpif.wen = 1; // assert write
        bpif.ren = 0;

        // settle inputs
        @(posedge CLK);
        #1;

        // check for a write error
        check("write error", expected_error, bpif.error);

        // verify all commands 0 if we have an error
        if (expected_error) begin
            check("rejected write has no commands", 0,
                {tx_wen, tx_flush, rx_flush, start, abort, error_clear, done_clear});
        end
        else begin

            // check behavior based on the given address
            case (addr)
                // check buffer data, request Tx FIFO push
                32'h10: begin
                    check("TX FIFO push", 1, tx_wen);
                    check("TX data path", data, tx_wdata);
                end
                // buffer flush
                32'h14: check("FIFO flush commands", data[1:0], {tx_flush, rx_flush});
                // start
                32'h18: check("start command", data[0], start);
                // error and done register clear
                32'h30: check("status clear commands", data[2:1], {error_clear, done_clear});
                // abort
                32'h3C: check("abort command", data[0], abort);
                // no commands triggered
                default: check("no commands triggered", 0,
                    {tx_wen, tx_flush, rx_flush, start, abort, error_clear, done_clear});
            endcase
        end

        // end the write
        @(negedge CLK);
        bpif.wen = 0;
        #1;

        // check that the commands were just a pulse
        check("write commands return to zero", 0,
            {tx_wen, tx_flush, rx_flush, start, abort, error_clear, done_clear});
    end
    endtask

    // use for reads
    task read(input [31:0] addr, output [31:0] data);
    begin

        // drive read requests
        @(negedge CLK);
        bpif.addr = addr;
        bpif.ren = 1;
        bpif.wen = 0;
        bpif.strobe = 4'hF;

        // sample read response
        @(posedge CLK);
        #1;
        data = bpif.rdata;

        // check for error
        check("read error", 0, bpif.error);

        // only reading buffer_data at 0x10 should trigger rx fifo pop
        check("RX FIFO pop", (addr == 32'h10), rx_ren);

        // end read
        @(negedge CLK);
        bpif.ren = 0;
        #1;
        check("RX FIFO pop returns to zero", 0, rx_ren);
    end
    endtask

    // self checking
    task check(input string name, input [31:0] expected, input [31:0] actual);
    begin
        if (expected === actual) begin
            $display("PASS: %s Expected=%h Actual=%h", name, expected, actual);
            pass_count++;
        end
        else begin
            $display("FAIL: %s Expected=%h Actual=%h", name, expected, actual);
            fail_count++;
        end
    end
    endtask

    initial begin
        $dumpfile("reg_map.vcd");
        $dumpvars(0, reg_map_tb);
        CLK = 0;
        nRST = 0;
        bpif.addr = '0;
        bpif.wdata = '0;
        bpif.wen = 0;
        bpif.ren = 0;
        bpif.strobe = 4'hF;

        tx_full = 0;
        tx_empty = 1;
        rx_full = 0;
        rx_empty = 1;
        tx_count = 0;
        rx_count = 0;
        rx_rdata = 32'hDEADBEEF;
        protocol_busy = 0;
        protocol_done = 0;
        protocol_error = 0;

        reset();
        #1;
        check("mode reset", 0, mode_sel);
        check("divider reset", 0, clkdiv);
        check("SPI length reset", 8, spi_length);
        check("transfer count reset", 0, transfer_count);

        write(32'h00, 32'h2, 4'b1111, 0);
        check("mode_sel write", 32'd2, {29'b0, mode_sel});

        // try for clkdiv = 16 bits
        write(32'h04, 32'h12345678, 4'b1111, 0); // write to clkdiv
        check("clkdiv write", 32'h00005678, clkdiv);
        read(32'h04, rdata);
        check("clkdiv read", 32'h00005678, rdata);

        // spi config
        write(32'h24, 32'hAAAAAAAA, 4'b1111, 0);
        check("spi_config write", 32'h000000AA, spi_config);
        read(32'h24, rdata);
        check("spi_config read", 32'h000000AA, rdata);

        // i2c config
        write(32'h28, 32'h00000001, 4'b1111, 0);
        check("i2c_config write", 1, i2c_config);
        read(32'h28, rdata);
        check("i2c_config read", 1, rdata);

        // i2c addr
        write(32'h2C, 32'h000000D2, 4'b1111, 0);
        check("i2c_addr write", 32'h52, i2c_addr);
        read(32'h2C, rdata);
        check("i2c_addr read", 32'h52, rdata);

        write(32'h10, 32'hBBBBBBBB, 4'b1111, 0);

        // RX FIFO contains one entry
        // reading buffer data should return value driven on rx_Data    
        rx_empty = 0;
        rx_count = 1;
        read(32'h10, rdata);
        check("RX data path", 32'hDEADBEEF, rdata);

        // write to a nonexistent address, expect error
        write(32'h4C, 32'hDEADBEEF, 4'b1111, 1);

        // write to a read-only register expect error
        write(32'h08, 32'h1, 4'b1111, 1); // Read-only register.

        // check protocol busy status
        protocol_busy = 1;
        read(32'h08, rdata);
        check("protocol busy status", 1, rdata);

        // check done status
        protocol_busy = 0;
        protocol_done = 1;
        read(32'h08, rdata);
        check("protocol done status", 2, rdata);

        // check error status
        protocol_done = 0;
        protocol_error = 1;
        read(32'h08, rdata);
        check("protocol error status", 4, rdata);
        protocol_error = 0;
        read(32'h08, rdata);
        check("protocol error input deasserted", 0, rdata);

        // test FIFO flags and counts
        // FIFO status bits:
        // [3] TX full, [2] TX empty, [1] RX full, [0] RX empty.

        // both fifos empty
        tx_full = 0; tx_empty = 1; rx_full = 0; rx_empty = 1;
        read(32'h0C, rdata);
        check("FIFO empty flags", 32'b0101, rdata);

        // both fifos full
        tx_full = 1; tx_empty = 0; rx_full = 1; rx_empty = 0;
        read(32'h0C, rdata);
        check("FIFO full flags", 32'b1010, rdata);

        // both are partially occupied
        tx_full = 0; tx_empty = 0; rx_full = 0; rx_empty = 0;
        rx_count = 3;
        tx_count = 9;
        read(32'h34, rdata);
        check("RX count read", 3, rdata);
        read(32'h38, rdata);
        check("TX count read", 9, rdata);

        // store transfer count of 10
        // verify output to controller and data back to software
        write(32'h1C, 32'd10, 4'b1111, 0);
        check("transfer_count write", 32'd10, transfer_count);
        read(32'h1C, rdata);
        check("transfer_count read", 32'd10, rdata);

        // verify minimum SPI length
        write(32'h20, 32'd5, 4'b1111, 0);
        check("minimum SPI length", 5, spi_length);

        // verify maximum SPI length
        write(32'h20, 32'd32, 4'b1111, 0);
        read(32'h20, rdata);
        check("maximum SPI length", 32, rdata);

        // attempt SPI length under minimum
        write(32'h20, 32'd4, 4'b1111, 1);
        check("SPI length unchanged after bad write (4)", 32, spi_length);

        // attempt SPI length above maximum
        write(32'h20, 32'd33, 4'b1111, 1);
        check("SPI length unchanged after bad write (33)", 32, spi_length);

        // verify FIFO command signals
        write(32'h14, 32'd1, 4'b1111, 0); // Flush RX only
        write(32'h14, 32'd2, 4'b1111, 0); // Flush TX only
        write(32'h14, 32'd3, 4'b1111, 0); // Flush both
        write(32'h14, 32'd0, 4'b1111, 0); // flush nothing

        // verify start
        write(32'h18, 32'd1, 4'b1111, 0); // START.
        write(32'h18, 32'd0, 4'b1111, 0); // verify no start

        // status clear signals
        write(32'h30, 32'd2, 4'b1111, 0); // 010: Clear done.
        write(32'h30, 32'd4, 4'b1111, 0); // 100: Clear error.
        write(32'h30, 32'd6, 4'b1111, 0); // 110: Clear both.
        write(32'h30, 32'd0, 4'b1111, 0); // 000: clear none

        // check abort signals
        write(32'h3C, 32'd1, 4'b1111, 0); // ABORT.
        write(32'h3C, 32'd0, 4'b1111, 0);

        // check that transfer_count stays at the configured value
        read(32'h1C, rdata);
        check("configured transfer count stays the same", 10, rdata);

        $display("---------------------------------");
        $display("TEST COMPLETE");
        $display("PASS: %0d", pass_count);
        $display("FAIL: %0d", fail_count);
        $display("---------------------------------");

        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        #20;
        if (fail_count != 0)
            $fatal(1, "Register map tests failed");
        $finish;
    end
endmodule
