module shift_register_tb;

    // Define Parameters
    localparam CLK_PERIOD = 2.5;
    localparam PROPAGATION_DELAY = 0.8; // Allow for 800 ps for FF propagation delay
    localparam SERIAL_CLK_PERIOD = 5;

    // Declare DUT Signals
    logic CLK;
    logic nRST;
    logic parallel_load;
    logic [7:0] parallel_in;
    logic shift_en;
    logic msb_first;
    logic shift_in;
    logic shift_out;
    logic [7:0] parallel_out;

    // Declare Test Case Signals
    integer tb_test_num;
    string  tb_test_case;
    int     tb_bit_num;
    int     tb_error_num;

    // Declare the Test Bench Signals for Expected Results
    logic [7:0] exp_parallel_out;
    logic exp_shift_out;

    shift_register DUT (.*);

    always #(CLK_PERIOD/2.0) CLK = ~CLK;

    task reset_dut();
    begin
        nRST = 0;
        repeat(2) @(posedge CLK);
        #PROPAGATION_DELAY;
        nRST = 1;
        repeat(2) @(posedge CLK);
        #PROPAGATION_DELAY;
    end
    endtask

    task serial_pulse();
    begin
        shift_en = 1;
        @(posedge CLK); #PROPAGATION_DELAY;
        shift_en = 0;
        repeat (SERIAL_CLK_PERIOD) @(posedge CLK);
        #PROPAGATION_DELAY;
    end
    endtask

    task check_shift_out;
    begin
        if (shift_out == exp_shift_out) begin
            $write("%c[32m", 8'd27);
            $display("Test case #%0d, %s: Correct shift output.", tb_test_num, tb_test_case);
        end
        else begin
            tb_error_num = tb_error_num + 1;
            $write("%c[31m", 8'd27);
            $display("ERROR: Test case #%0d, %s: Incorrect shift output. Expected: %b Actual: %b", tb_test_num, tb_test_case, exp_shift_out, shift_out);
        end
    end
    endtask

    task check_parallel_out;
    begin
        if (parallel_out == exp_parallel_out) begin
            $write("%c[32m", 8'd27);
            $display("Test case #%0d, %s: Correct parallel output.", tb_test_num, tb_test_case);
        end
        else begin
            tb_error_num = tb_error_num + 1;
            $write("%c[31m", 8'd27);
            $display("ERROR: Test case #%0d, %s: Incorrect parallel output. Expected: %b Actual: %b", tb_test_num, tb_test_case, exp_parallel_out, parallel_out);
        end
    end
    endtask

    task rx_byte(
        input logic [7:0] value
    );
    begin
        for (tb_bit_num = 0; tb_bit_num < 8; tb_bit_num++) begin
            shift_in = msb_first ? value[7 - tb_bit_num] : value[tb_bit_num];
            serial_pulse();
        end
        exp_parallel_out = value;
        check_parallel_out();
    end
    endtask

    task tx_byte(
        input logic [7:0] value
    );
    begin
        parallel_load = 1'b1;
        parallel_in = value;
        @(posedge CLK); #PROPAGATION_DELAY;
        parallel_load = 1'b0;
        parallel_in = 8'b0;
        repeat (10) @(posedge CLK); #PROPAGATION_DELAY;
        for (tb_bit_num = 0; tb_bit_num < 8; tb_bit_num++) begin
            exp_shift_out = msb_first ? value[7 - tb_bit_num] : value[tb_bit_num];
            check_shift_out();
            serial_pulse();
        end
    end
    endtask

    initial begin
        $dumpfile("waveform.fst");
        $dumpvars(0, shift_register_tb);
        // Initialize test signals
        nRST             = 1'b1;
        parallel_load    = 1'b0;
        parallel_in      = 8'b0;
        shift_en         = 1'b0;
        msb_first        = 1'b0;
        shift_in        = 1'b0;
        tb_test_num      = 0;
        tb_test_case     = "Testbench intialization";
        tb_bit_num       = -1;
        tb_error_num     = 0;
        exp_parallel_out = 8'b0;
        exp_shift_out   = 1'b0;
        #(0.1);

        // Test 0:
        tb_test_case = "Power on Reset";
        reset_dut();
        check_parallel_out();
        check_shift_out();

        // Test 1:
        tb_test_num  = tb_test_num + 1;
        tb_test_case = "Parallel load 0xFF";
        parallel_in = 8'hFF;
        parallel_load = 1'b1;
        exp_parallel_out = 8'hFF;
        @(posedge CLK); #PROPAGATION_DELAY;
        parallel_load = 1'b0;
        check_parallel_out();

        // Test 2:
        tb_test_num  = tb_test_num + 1;
        tb_test_case = "Parallel load 0x00";
        parallel_in = 8'h00;
        parallel_load = 1'b1;
        exp_parallel_out = 8'h00;
        @(posedge CLK); #PROPAGATION_DELAY;
        parallel_load = 1'b0;
        check_parallel_out();

        // Test 3:
        tb_test_num  = tb_test_num + 1;
        tb_test_case = "shift in LSB first";
        rx_byte(8'h45);
        rx_byte(8'hFF);
        rx_byte(8'h00);

        // Test 4:
        tb_test_num  = tb_test_num + 1;
        tb_test_case = "shift in MSB first";
        msb_first = 1'b1;
        rx_byte(8'h98);
        rx_byte(8'hFF);
        rx_byte(8'h00);

        // Test 5:
        tb_test_num  = tb_test_num + 1;
        tb_test_case = "Hold parallel out";
        shift_in = 1'b1;
        repeat (10) @(posedge CLK); #PROPAGATION_DELAY;
        exp_parallel_out = 8'b0;
        check_parallel_out();

        // Test 6:
        tb_test_num  = tb_test_num + 1;
        tb_test_case = "shift out MSB first";
        tx_byte(8'h72);
        tx_byte(8'hFF);
        tx_byte(8'h00);

        // Test 7:
        tb_test_num  = tb_test_num + 1;
        tb_test_case = "shift out LSB first";
        msb_first = 1'b0;
        tx_byte(8'hB3);
        tx_byte(8'hFF);
        tx_byte(8'h00);
        
        $write("%c[0m", 8'd27);
        $display("===============================");
        $display("Simulation finished: %0d errors", tb_error_num);
        $display("===============================");
        $finish;
    end

endmodule