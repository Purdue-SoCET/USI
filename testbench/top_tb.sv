module top_tb;

    logic CLK;
    logic nRST;

    logic load;
    logic send;
    logic [7:0] data_in;
    logic rx_line;
    logic spi_miso;

    logic tx_out;
    logic spi_mosi;
    logic serial_clk;
    logic [3:0] spi_cs_n;
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
        .rx_line(rx_line),
        .spi_miso(spi_miso),
        .tx_out(tx_out),
        .spi_mosi(spi_mosi),
        .serial_clk(serial_clk),
        .spi_cs_n(spi_cs_n),
        .data_out(data_out),
        .buffer_occupancy(buffer_occupancy)
    );

    initial CLK = 1'b0;
    always #5 CLK = ~CLK;

    int pass = 0;
    int fail = 0;

    logic [31:0] rdata;
    logic [7:0] occ_before;
    logic [7:0] occ_after;

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
        rx_line = 1'b1;
        spi_miso = 1'b0;

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
        #1;

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

    task pulse_send;
    begin
        @(negedge CLK);
        send = 1'b1;

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

        check("serial_clk placeholder", 32'h00000000, {31'h0, serial_clk});
        check("spi_mosi placeholder",   32'h00000000, {31'h0, spi_mosi});
        check("spi_cs_n placeholder",   32'h0000000F, {28'h0, spi_cs_n});

        write(32'h0, 32'h00000002, 4'hF);
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

        @(posedge CLK);
        check("buffer occupancy after 4 loads", 32'h00000004, {24'h0, buffer_occupancy});

        read(32'h10, rdata);
        check("buffer read/pop", 32'h44332211, rdata);

        @(posedge CLK);
        check("buffer occupancy after pop", 32'h00000000, {24'h0, buffer_occupancy});

        write(32'hC, 32'hAABBCCDD, 4'hF);
        read(32'hC, rdata);
        check("tx_data", 32'hAABBCCDD, rdata);

        @(posedge CLK);
        check("buffer occupancy after tx write push", 32'h00000004, {24'h0, buffer_occupancy});

        pulse_send();
        check("serial_clk after send pulse", 32'h00000000, {31'h0, serial_clk});
        check("spi_mosi after send pulse",   32'h00000000, {31'h0, spi_mosi});
        check("spi_cs_n after send pulse",   32'h0000000F, {28'h0, spi_cs_n});

        @(posedge CLK);
        occ_before = buffer_occupancy;

        load_byte(8'h55);
        load_byte(8'h66);

        @(posedge CLK);
        occ_after = buffer_occupancy;
        check("buffer occupancy increment by 2", 32'h00000002, {24'h0, (occ_after - occ_before)});
        check("buffer occupancy final", 32'h00000005, {24'h0, buffer_occupancy});

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

endmodule