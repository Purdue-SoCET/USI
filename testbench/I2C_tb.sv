`timescale 1ns/1ps

module I2C_tb;

    localparam CLK_PERIOD = 20ns;
    localparam WAIT_LIMIT = 4096;

    import usi_datapath_pkg::*;

    logic clk;
    logic n_rst;
    logic rwconfig;
    logic addr_config;
    logic en;
    logic [15:0] div;
    logic scl_in;
    logic read_done;
    logic scl;
    dp_cmd_t dp_out;
    dp_status_t dp_in;

    I2C DUT(.*);

    always begin
        clk = 0;
        #(CLK_PERIOD / 2);
        clk = 1;
        #(CLK_PERIOD / 2);
    end

    task reset_dut;
        en = 0;
        read_done = 0;
        dp_in = '0;
        dp_in.tx_fifo_valid = 1;
        dp_in.rx_fifo_ready = 1;
        dp_in.tx_bit = 1;
        n_rst = 0;
        @(negedge clk);
        n_rst = 1;
        @(negedge clk);
        n_rst = 0;
        @(negedge clk);
        n_rst = 1;
        @(negedge clk);
    endtask

    task wait_state;
        input logic [2:0] expected_state;
        int cycles;
    begin
        cycles = 0;
        while(DUT.state !== expected_state && cycles < WAIT_LIMIT) begin
            @(negedge clk);
            cycles++;
        end
        if(DUT.state !== expected_state) begin
            $fatal(1, "test %0d timeout, expected state %0d got %0d",
                testNum, expected_state, DUT.state);
        end
    end
    endtask

    task check_TX;
        input logic [7:0] expected_data;
        input logic from_fifo;
        input logic en_shift;
    begin
        if(dp_out.tx_load !== 1'b1 || dp_out.tx_from_fifo !== from_fifo ||
            dp_out.tx_immediate !== expected_data || dp_out.tx_shift !== en_shift) begin
            $fatal(1, "test %d TX fail in state %d: expected load=1 fifo=%b data=%h shift=%b, got %b %b %h %b",
                testNum, DUT.state, from_fifo, expected_data, en_shift,
                dp_out.tx_load, dp_out.tx_from_fifo, dp_out.tx_immediate, dp_out.tx_shift);
        end
    end
    endtask

    task check_RX;
        input logic rbegin;
        input logic sample;
        input logic commit;
        input logic discard;
    begin
        if(dp_out.lsb_first !== 1'b0 || dp_out.rx_begin !== rbegin ||
            dp_out.rx_sample !== sample || dp_out.rx_commit !== commit ||
            dp_out.rx_discard !== discard) begin
            $fatal(1, "test %0d RX fail in state %0d: expected MSB first, begin=%b sample=%b commit=%b discard=%b, got %b %b %b %b %b",
                testNum, DUT.state, rbegin, sample, commit, discard,
                dp_out.lsb_first, dp_out.rx_begin, dp_out.rx_sample,
                dp_out.rx_commit, dp_out.rx_discard);
        end
    end
    endtask

    task check_RSET;
    begin
        wait_state(DUT.RSET);
        check_TX(8'd1, 0, 0);
        check_RX(1, 0, 0, 0);
        if(scl !== 1'b1)
            $fatal(1, "test %0d RSET fail, SCL should be high", testNum);

        dp_in.rx_begin_failed = 1;
        dp_in.rx_begin_done = 0;
        @(negedge clk);
        if(DUT.state !== DUT.RSET)
            $fatal(1, "test %0d RSET fail, did not wait for RX begin", testNum);
        check_RX(1, 0, 0, 0);
        dp_in.rx_begin_failed = 0;
        dp_in.rx_begin_done = 1;
        @(negedge clk);
        dp_in.rx_begin_done = 0;
    end
    endtask

    task test_I2C;
        input logic [6:0] addr;
        input logic rw;
        int cycles;
    begin
        rwconfig = rw;
        scl_in = 1;
        reset_dut;

        check_TX(8'd1, 0, 1);
        check_RX(0, 0, 0, 0);
        if(scl !== 1'b1)
            $fatal(1, "test %0d IDLE fail", testNum);

        en = 1;
        @(negedge clk);
        wait_state(DUT.START);
        check_TX(8'd0, 0, 1);
        check_RX(0, 0, 0, 0);
        if(scl !== 1'b1)
            $fatal(1, "test %0d START fail", testNum);
        en = 0;

        wait_state(DUT.ADDR);
        check_TX(8'hFF, 1, 1);
        check_RX(0, 0, 0, 0);
        wait_state(DUT.RWBIT);
        check_TX(rw ? 8'd0 : 8'd1, 0, 1);
        check_RX(0, 0, 0, 0);

        dp_in.rx_byte = 0;
        dp_in.rx_byte_valid = 1;
        if(rw) check_RSET;
        wait_state(DUT.AWK);
        if(rw) check_RX(0, 1, 0, 0);
        else begin
            check_TX(8'd0, 0, 1);
            check_RX(0, 0, 0, 0);
        end
        dp_in.tx_fifo_valid = (rand_limit != 0);
        read_done = (rand_limit == 0);

        for(int i = 0; i < rand_limit; i++) begin
            if(!rw) check_RSET;
            wait_state(DUT.DATA);
            dp_in.rx_byte_valid = 0;
            dp_in.rx_done = 0;
            cycles = 0;
            while(DUT.state === DUT.DATA && cycles < WAIT_LIMIT) begin
                if(rw) begin
                    if(DUT.count_out[0]) check_TX(8'hFF, 1, 0);
                    else check_TX(8'd1, 0, 1);
                    check_RX(0, 0, 0, 0);
                end else begin
                    check_RX(0, 1, 0, 0);
                    dp_in.rx_byte = fifo_data[i];
                    dp_in.rx_byte_valid = 1;
                    dp_in.rx_done = 1;
                end
                @(negedge clk);
                cycles++;
            end
            if(DUT.state === DUT.DATA)
                $fatal(1, "test %0d DATA timeout", testNum);
            dp_in.rx_done = 0;

            wait_state(DUT.AWK);
            dp_in.rx_byte = 0;
            dp_in.rx_byte_valid = 1;
            dp_in.tx_fifo_valid = (i != rand_limit - 1);
            read_done = (i == rand_limit - 1);
            if(rw) check_RX(0, 1, 0, 0);
            else begin
                check_TX(8'd0, 0, 1);
                check_RX(0, 0, 0, 0);
            end
        end

        wait_state(DUT.STOP);
        check_TX(8'd0, 1, 0);
        check_RX(0, 0, 0, 0);
        @(negedge clk);
        if(scl !== 1'b1)
            $fatal(1, "test %0d STOP fail", testNum);
        wait_state(DUT.IDLE);
        check_TX(8'd1, 0, 1);
        check_RX(0, 0, 0, 0);
        $display("test %0d PASS, addr %h write %b bytes %0d", testNum, addr, rw, rand_limit);
    end
    endtask

    int testNum;
    logic [7:0] fifo_data [0:255];
    logic [7:0] rand_addr_rw;
    int rand_limit;

    initial begin
        n_rst = 1;
        testNum = 0;
        rwconfig = 1;
        addr_config = 1;
        en = 0;
        div = 16'd8;
        scl_in = 1;
        read_done = 0;
        dp_in = '0;

        for(int i = 0; i < 256; i++) begin
            testNum++;
            rand_addr_rw = 8'($urandom_range(0, 255));
            rand_limit = $urandom_range(0, 255);
            for(int j = 0; j < rand_limit; j++) begin
                fifo_data[j] = 8'($urandom_range(0, 255));
            end
            test_I2C(rand_addr_rw[6:0], rand_addr_rw[7]);
        end
        $display("All %0d I2C tests passed", testNum);
        $finish;
    end
endmodule
