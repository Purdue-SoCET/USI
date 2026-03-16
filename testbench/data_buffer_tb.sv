module data_buffer_tb;

    logic CLK;
    logic nRST;
    logic [1:0] mode_sel;
    logic [7:0] data_in;
    logic [31:0] buffer_write;
    logic push;
    logic pop;
    logic clear;
    logic load;
    logic send;
    logic [7:0] data_out;
    logic [31:0] buffer_read;
    logic [7:0] buffer_occupancy;
    logic [31:0] pop_word;
    logic [7:0] send_byte;

    data_buffer dut (
        .CLK(CLK),
        .nRST(nRST),
        .mode_sel(mode_sel),
        .data_in(data_in),
        .buffer_write(buffer_write),
        .push(push),
        .pop(pop),
        .clear(clear),
        .load(load),
        .send(send),
        .data_out(data_out),
        .buffer_read(buffer_read),
        .buffer_occupancy(buffer_occupancy)
    );

    always #5 CLK = ~CLK;

    task reset_dut;
    begin
        nRST = 1'b0;
        mode_sel = 2'b0;
        data_in = 8'h0;
        buffer_write = 32'h0;
        push = 1'b0;
        pop = 1'b0;
        clear = 1'b0;
        load = 1'b0;
        send = 1'b0;
        pop_word = 32'h0;
        send_byte = 8'h0;

        repeat (2) @(posedge CLK);
        nRST = 1'b1;
        @(posedge CLK);
    end
    endtask

    task pulse_load(input logic [7:0] din);
    begin
        @(negedge CLK);
        data_in = din;
        load = 1'b1;
        @(posedge CLK);
        @(negedge CLK);
        load = 1'b0;
        data_in = 8'h0;
    end
    endtask

    task pulse_push(input logic [31:0] din);
    begin
        @(negedge CLK);
        buffer_write = din;
        push = 1'b1;
        @(posedge CLK);
        @(negedge CLK);
        push = 1'b0;
        buffer_write = 32'h0;
    end
    endtask

    task pulse_clear;
    begin
        @(negedge CLK);
        clear = 1'b1;
        @(posedge CLK);
        @(negedge CLK);
        clear = 1'b0;
    end
    endtask

    task pulse_pop_capture(output logic [31:0] dout);
    begin
        @(negedge CLK);
        pop = 1'b1;
        #1;
        dout = buffer_read;
        @(posedge CLK);
        @(negedge CLK);
        pop = 1'b0;
    end
    endtask

    task pulse_send_capture(output logic [7:0] dout);
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

    initial begin
        $dumpfile("waveform.fst");
        $dumpvars(0, data_buffer_tb);
        CLK = 1'b0;
        reset_dut();

        $display("==================================================");
        $display("TEST 1: Reset values");
        $display("==================================================");
        if (buffer_occupancy !== 8'd0)
            $error("Reset failed: occupancy = %0d, expected 0", buffer_occupancy);
        else
            $display("PASS: reset occupancy correct");

        $display("==================================================");
        $display("TEST 2: Non-I2C mode RX load path (mode != 10)");
        $display("==================================================");
        mode_sel = 2'b00;

        pulse_load(8'h11);
        pulse_load(8'h22);
        pulse_load(8'h33);
        pulse_load(8'h44);

        @(posedge CLK);
        if (buffer_occupancy !== 8'd4)
            $error("RX load occupancy wrong: got %0d expected 4", buffer_occupancy);
        else
            $display("PASS: RX load occupancy correct");

        $display("==================================================");
        $display("TEST 3: Non-I2C mode pop 32-bit word from RX side");
        $display("==================================================");
        pulse_pop_capture(pop_word);
        $display("buffer_read = 0x%08h", pop_word);

        if (pop_word !== 32'h44332211)
            $error("RX pop wrong: got 0x%08h expected 0x44332211", pop_word);
        else
            $display("PASS: RX pop data correct");

        @(posedge CLK);
        if (buffer_occupancy !== 8'd0)
            $error("RX pop occupancy wrong: got %0d expected 0", buffer_occupancy);
        else
            $display("PASS: RX pop occupancy correct");

        $display("==================================================");
        $display("TEST 4: Non-I2C mode TX push path");
        $display("==================================================");
        pulse_push(32'hA1B2C3D4);

        @(posedge CLK);
        if (buffer_occupancy !== 8'd4)
            $error("TX push occupancy wrong: got %0d expected 4", buffer_occupancy);
        else
            $display("PASS: TX push changed occupancy");

        $display("==================================================");
        $display("TEST 5: Non-I2C mode send bytes from TX side");
        $display("==================================================");
        pulse_send_capture(send_byte);
        $display("data_out after send = 0x%02h", send_byte);

        if (send_byte !== 8'hD4)
            $error("TX send wrong first byte: got 0x%02h expected 0xD4", send_byte);
        else
            $display("PASS: TX send first byte correct");

        @(posedge CLK);
        if (buffer_occupancy !== 8'd3)
            $error("TX send occupancy wrong: got %0d expected 3", buffer_occupancy);
        else
            $display("PASS: TX send occupancy correct");

        $display("==================================================");
        $display("TEST 6: Non-I2C RX/TX split behavior");
        $display("==================================================");

        pulse_clear();
        @(posedge CLK);

        mode_sel = 2'b0;

        pulse_push(32'h11223344);
        
        pulse_load(8'hAA);
        pulse_load(8'hBB);
        pulse_load(8'hCC);
        pulse_load(8'hDD);

        @(posedge CLK);
        $display("Combined occupancy after RX load + TX push = %0d", buffer_occupancy);

        if (buffer_occupancy !== 8'd8)
            $error("Split test occupancy wrong after fill: got %0d expected 8", buffer_occupancy);
        else
            $display("PASS: combined occupancy correct after RX/TX fill");

        pulse_pop_capture(pop_word);
        $display("RX pop during split test = 0x%08h", pop_word);

        if (pop_word !== 32'hDDCCBBAA)
            $error("Split test RX pop wrong: got 0x%08h expected 0xDDCCBBAA", pop_word);
        else
            $display("PASS: RX side returned only RX data");

        @(posedge CLK);
        if (buffer_occupancy !== 8'd4)
            $error("Split test occupancy wrong after RX pop: got %0d expected 4", buffer_occupancy);
        else
            $display("PASS: occupancy correct after RX pop");

        pulse_send_capture(send_byte);
        $display("TX send during split test = 0x%02h", send_byte);

        if (send_byte !== 8'h44)
            $error("Split test TX send wrong: got 0x%02h expected 0x44", send_byte);
        else
            $display("PASS: TX side returned only TX data");

        @(posedge CLK);
        if (buffer_occupancy !== 8'd3)
            $error("Split test occupancy wrong after TX send: got %0d expected 3", buffer_occupancy);
        else
            $display("PASS: occupancy correct after TX send");

        pulse_send_capture(send_byte);
        if (send_byte !== 8'h33)
            $error("Split test TX second send wrong: got 0x%02h expected 0x33", send_byte);

        pulse_send_capture(send_byte);
        if (send_byte !== 8'h22)
            $error("Split test TX third send wrong: got 0x%02h expected 0x22", send_byte);

        pulse_send_capture(send_byte);
        if (send_byte !== 8'h11)
            $error("Split test TX fourth send wrong: got 0x%02h expected 0x11", send_byte);

        @(posedge CLK);
        if (buffer_occupancy !== 8'd0)
            $error("Split test final occupancy wrong: got %0d expected 0", buffer_occupancy);
        else
            $display("PASS: RX and TX partitions stayed independent");

        $display("==================================================");
        $display("TEST 7: I2C mode shared buffer behavior (mode == 10)");
        $display("==================================================");
        pulse_clear();
        @(posedge CLK);

        if (buffer_occupancy !== 8'd0)
            $error("Clear before I2C test failed: got %0d expected 0", buffer_occupancy);

        mode_sel = 2'b10;

        pulse_load(8'h55);
        pulse_load(8'h66);
        pulse_push(32'h11223344);

        @(posedge CLK);
        $display("I2C mode occupancy after load/load/push = %0d", buffer_occupancy);

        if (buffer_occupancy !== 8'd6)
            $error("I2C mixed occupancy wrong: got %0d expected 6", buffer_occupancy);
        else
            $display("PASS: I2C mixed occupancy correct");

        pulse_send_capture(send_byte);
        $display("I2C mode data_out after send = 0x%02h", send_byte);

        if (send_byte !== 8'h55)
            $error("I2C send wrong first byte: got 0x%02h expected 0x55", send_byte);
        else
            $display("PASS: I2C send first byte correct");

        @(posedge CLK);
        if (buffer_occupancy !== 8'd5)
            $error("I2C send occupancy wrong: got %0d expected 5", buffer_occupancy);
        else
            $display("PASS: I2C send occupancy correct");

        pulse_pop_capture(pop_word);
        $display("I2C mode buffer_read after pop = 0x%08h", pop_word);

        if (pop_word !== 32'h22334466)
            $error("I2C pop wrong: got 0x%08h expected 0x22334466", pop_word);
        else
            $display("PASS: I2C pop data correct");

        @(posedge CLK);
        if (buffer_occupancy !== 8'd1)
            $error("I2C pop occupancy wrong: got %0d expected 1", buffer_occupancy);
        else
            $display("PASS: I2C pop occupancy correct");

        $display("==================================================");
        $display("TEST 8: Clear");
        $display("==================================================");
        pulse_clear();
        @(posedge CLK);

        if (buffer_occupancy !== 8'd0)
            $error("Clear failed: occupancy = %0d expected 0", buffer_occupancy);
        else
            $display("PASS: clear reset occupancy");

        $display("==================================================");
        $display("TEST 9: Fill RX region near limit in non-I2C mode");
        $display("==================================================");
        mode_sel = 2'b00;

        repeat (130) begin
            pulse_load($random[7:0]);
        end

        @(posedge CLK);
        $display("Occupancy after repeated loads = %0d", buffer_occupancy);
        if (buffer_occupancy !== 8'd128)
            $error("RX partition limit wrong: got %0d expected 128", buffer_occupancy);
        else
            $display("PASS: RX partition limit respected");

        $display("==================================================");
        $display("TEST 10: Fill TX region near limit in non-I2C mode");
        $display("==================================================");
        pulse_clear();
        @(posedge CLK);

        repeat (40) begin
            pulse_push($random);
        end

        @(posedge CLK);
        $display("Occupancy after repeated pushes = %0d", buffer_occupancy);
        if (buffer_occupancy !== 8'd128)
            $error("TX partition limit wrong: got %0d expected 128", buffer_occupancy);
        else
            $display("PASS: TX pushes completed");

        $display("==================================================");
        $display("Simulation finished");
        $display("==================================================");
        $finish;
    end

endmodule