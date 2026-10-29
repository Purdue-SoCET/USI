`timescale 1ns/1ps

module tb_wrapper;

    logic        CLOCK_50;
    logic [3:0]  KEY;
    logic [17:0] SW;
    logic [17:0] LEDR;
    logic [7:0]  LEDG;

    wrapper dut (
        .CLOCK_50(CLOCK_50),
        .KEY(KEY),
        .SW(SW),
        .LEDR(LEDR),
        .LEDG(LEDG)
    );

    initial begin
        CLOCK_50 = 1'b0;
        forever #10 CLOCK_50 = ~CLOCK_50;
    end

    task press_key0;
        begin
            KEY[0] = 1'b0;
            repeat (3) @(posedge CLOCK_50);
            KEY[0] = 1'b1;
            repeat (3) @(posedge CLOCK_50);
        end
    endtask

    task press_key1;
        begin
            KEY[1] = 1'b0;
            repeat (3) @(posedge CLOCK_50);
            KEY[1] = 1'b1;
            repeat (3) @(posedge CLOCK_50);
        end
    endtask

    task press_key2;
        begin
            KEY[2] = 1'b0;
            repeat (3) @(posedge CLOCK_50);
            KEY[2] = 1'b1;
            repeat (3) @(posedge CLOCK_50);
        end
    endtask

    task load_lower16(input [14:0] val);
        begin
            SW[16]   = 1'b0;
            SW[14:0] = val;
            press_key0();
        end
    endtask

    task load_upper16(input [14:0] val);
        begin
            SW[16]   = 1'b1;
            SW[14:0] = val;
            press_key0();
        end
    endtask

    task select_addr(input [2:0] sel);
        begin
            SW[17:15] = sel;
            @(posedge CLOCK_50);
        end
    endtask

    initial begin
        KEY = 4'b1111;
        SW  = 18'h0;

        repeat (25) @(posedge CLOCK_50);

        load_lower16(15'h1234);
        load_upper16(15'h5678);

        select_addr(3'b010);
        press_key2();
        repeat (6) @(posedge CLOCK_50);

        select_addr(3'b001);
        press_key1();
        repeat (6) @(posedge CLOCK_50);

        select_addr(3'b100);
        press_key1();
        repeat (6) @(posedge CLOCK_50);

        select_addr(3'b011);
        press_key2();
        repeat (6) @(posedge CLOCK_50);

        $finish;
    end

endmodule