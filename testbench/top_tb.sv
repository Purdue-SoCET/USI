
module top_tb;

    logic CLK;
    logic nRST;

    bus_protocol_if bpif();

    top DUT (
        .CLK(CLK),
        .nRST(nRST),
        .bpif(bpif)
    );

    initial CLK = 0;
    always #5 CLK = ~CLK;

    task reset;
    begin
        nRST = 0;
        bpif.wen = 0;
        bpif.ren = 0;
        bpif.addr = 0;
        bpif.wdata = 0;
        bpif.strobe = 4'hF;
        #20;
        nRST = 1;
    end
    endtask

    task write(input [31:0] addr, input [31:0] data);
    begin
        @(negedge CLK);
        bpif.addr  = addr;
        bpif.wdata = data;
        bpif.wen   = 1;
        bpif.ren   = 0;
        bpif.strobe = 4'hF;

        @(negedge CLK);
        bpif.wen = 0;
    end
    endtask

    task read(input [31:0] addr, output [31:0] data);
    begin
        @(negedge CLK);
        bpif.addr = addr;
        bpif.ren  = 1;
        bpif.wen  = 0;

        @(negedge CLK);
        data = bpif.rdata;

        bpif.ren = 0;
    end
    endtask

    logic [31:0] rdata;

    initial begin
        $display("Starting top-level testbench");

        reset();

        write(32'h0, 32'h1);
        write(32'h4, 32'h12345678);
        write(32'h8, 32'hAAAAAAAA);
        write(32'hC, 32'hDEADBEEF);

        read(32'h0, rdata);
        $display("Read mode_sel = %h", rdata);

        read(32'h4, rdata);
        $display("Read clkdiv = %h", rdata);

        read(32'h8, rdata);
        $display("Read configuration = %h", rdata);

        read(32'hC, rdata);
        $display("Read tx_data = %h", rdata);

        read(32'h10, rdata);
        $display("Read buffer_read = %h", rdata);

        read(32'h14, rdata);
        $display("Read error_reg = %h", rdata);

        $display("Simulation finished successfully");
        #20;
        $finish;
    end

endmodule