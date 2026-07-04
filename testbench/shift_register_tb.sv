module shift_register_tb;
    logic CLK;
    logic nRST;
    logic start;
    logic [7:0] parallel_in;
    logic shift_en;
    logic msb_first;
    logic serial_in;
    logic serial_out;
    logic [7:0] parallel_out;
    logic done;

    shift_register DUT (.*);

    always #5 CLK = ~CLK;

    task reset_dut();
    begin
        nRST = 0;
        start = 0;
        parallel_in = '0;
        shift_en = 0;
        msb_first = 0;
        serial_in = 0;
        repeat(2) @(negedge CLK);
    end
    endtask

    initial begin
        $dumpfile("waveform.fst");
        $dumpvars(0, shift_register_tb);
        reset_dut();
        $display("===================");
        $display("Simulation finished");
        $display("===================");
        $finish;
    end

endmodule