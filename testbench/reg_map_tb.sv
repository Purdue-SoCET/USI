module reg_map_tb;

    logic CLK;
    logic nRST;
    logic ctrl_unit_error;

    logic [1:0] mode_sel;
    logic [31:0] clkdiv;
    logic [31:0] parameters;
    logic [31:0] tx_data;
    logic [31:0] error_reg;
    logic [31:0] buffer_read;

    bus_protocol_if bpif();

    int pass_count = 0;
    int fail_count = 0;

    reg_map DUT (
        .bpif(bpif),
        .CLK(CLK),
        .nRST(nRST),
        .ctrl_unit_error(ctrl_unit_error),
        .mode_sel(mode_sel),
        .clkdiv(clkdiv),
        .parameters(parameters),
        .tx_data(tx_data),
        .error_reg(error_reg),
        .buffer_read(buffer_read)
    );

    always #5 CLK = ~CLK;

    task reset();
    begin
        nRST = 0;
        #20;
        nRST = 1;
    end
    endtask


    task write(input [31:0] addr, input [31:0] data, input [3:0] strb);
    begin
        @(negedge CLK);
        bpif.addr   = addr;
        bpif.wdata  = data;
        bpif.strobe = strb;
        bpif.wen    = 1;
        bpif.ren    = 0;

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


    task check(input string name, input [31:0] expected, input [31:0] actual);
    begin
        if(expected === actual) begin
            $display("PASS: %s Expected=%h Actual=%h", name, expected, actual);
            pass_count++;
        end
        else begin
            $display("FAIL: %s Expected=%h Actual=%h", name, expected, actual);
            fail_count++;
        end
    end
    endtask


    logic [31:0] rdata;

    initial begin

        CLK = 0;
        bpif.wen = 0;
        bpif.ren = 0;
        bpif.strobe = 4'hF;
        ctrl_unit_error = 0;

        reset();

        write(32'h0, 32'h2, 4'b0001);
        check("mode_sel write", 32'd2, {30'b0, mode_sel});

        write(32'h4, 32'h12345678, 4'b1111);
        check("clkdiv write", 32'h12345678, clkdiv);

        write(32'h8, 32'hAAAAAAAA, 4'b1111);
        check("parameters write", 32'hAAAAAAAA, parameters);

        write(32'hC, 32'hBBBBBBBB, 4'b1111);
        check("tx_data write", 32'hBBBBBBBB, tx_data);

        read(32'h4, rdata);
        check("clkdiv read", 32'h12345678, rdata);

        write(32'h4, 32'hFFFF0000, 4'b0011);
        read(32'h4, rdata);
        check("strobe partial write", 32'h12340000, rdata);

        write(32'h20, 32'hDEADBEEF, 4'b1111);

        if(bpif.error)
            $display("PASS: bus error detected");
        else begin
            $display("FAIL: bus error not detected");
            fail_count++;
        end

        ctrl_unit_error = 1;
        @(negedge CLK);
        @(negedge CLK); 
        ctrl_unit_error = 0;


        read(32'h14, rdata);
        check("error_reg cleared", 0, rdata);

        $display("---------------------------------");
        $display("TEST COMPLETE");
        $display("PASS: %0d", pass_count);
        $display("FAIL: %0d", fail_count);
        $display("---------------------------------");

        if(fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        #20;
        $finish;

    end

endmodule