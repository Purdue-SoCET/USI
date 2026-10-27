`timescale 1ns/1ps

module urbana_usi_uart_tb #(
    parameter int unsigned UART_DIVISOR = 20
);
    localparam time CLOCK_PERIOD = 10ns;
    localparam time BIT_PERIOD = CLOCK_PERIOD * UART_DIVISOR;
    localparam int WAIT_CYCLES = UART_DIVISOR * 120 + 2048;

    logic clk_100mhz = 1'b0;
    logic btn_reset = 1'b0;
    logic uart_rx, uart_tx;
    logic led_heartbeat, led_ready, led_error;
    logic previous_accept;
    int unsigned checks = 0;
    int unsigned accepted_accesses = 0;

    urbana_usi_uart_top #(
        .UART_DIVISOR(UART_DIVISOR),
        .HEARTBEAT_HALF_PERIOD_CYCLES(32)
    ) dut (.*);

    uart_peer peer (
        .nRST(dut.reset_n),
        .tx(uart_tx),
        .rx(uart_rx)
    );

    always #(CLOCK_PERIOD/2) clk_100mhz = !clk_100mhz;

    task automatic check(input logic condition, input string description);
        checks++;
        if (condition !== 1'b1)
            $fatal(1, "%s", description);
    endtask

    task automatic wait_ready;
        for (int attempt = 0; attempt < WAIT_CYCLES; attempt++) begin
            @(negedge clk_100mhz);
            check(!led_error, "initialization has no error");
            if (led_ready) begin
                check(32'(dut.usi.clkdiv) == UART_DIVISOR, "divisor configured through bus");
                check(dut.usi.uart_config == 0, "8N1 without flow control configured");
                check(dut.usi.mode_sel == 1, "UART mode selected through bus");
                check(dut.usi.fifo_tx_start == 128, "default RX/TX split preserved");
                return;
            end
        end
        $fatal(1, "timeout waiting for ready");
    endtask

    task automatic expect_tx(input logic [7:0] expected);
        logic [7:0] observed;
        for (int attempt = 0; attempt < WAIT_CYCLES; attempt++) begin
            if (peer.received.size() != 0) begin
                observed = peer.received.pop_front();
                check(observed == expected,
                    $sformatf("TX received %02h, expected %02h", observed, expected));
                return;
            end
            @(negedge clk_100mhz);
        end
        $fatal(1, "timeout waiting for TX byte %02h", expected);
    endtask

    task automatic expect_banner;
        expect_tx(8'h55); // U
        expect_tx(8'h53); // S
        expect_tx(8'h49); // I
        expect_tx(8'h0A); // newline
    endtask

    task automatic expect_quiet(input int unsigned bit_periods = 12);
        #(BIT_PERIOD * bit_periods);
        check(uart_tx && peer.received.size() == 0, "no extra TX bytes");
    endtask

    task automatic send_byte(input logic [7:0] value);
        #3;
        peer.send_byte(value, BIT_PERIOD);
    endtask

    task automatic wait_error;
        for (int attempt = 0; attempt < WAIT_CYCLES; attempt++) begin
            @(negedge clk_100mhz);
            if (led_error) begin
                check(!led_ready, "fault deasserts ready");
                return;
            end
        end
        $fatal(1, "timeout waiting for error indication");
    endtask

    task automatic reset_and_restart;
        @(negedge clk_100mhz);
        peer.monitor_enable = 1'b0;
        btn_reset = 1'b1;
        #(BIT_PERIOD * 2);
        check(!led_ready && !led_error && uart_tx, "button reset clears status and idles TX");
        peer.received.delete();
        peer.earliest_next_start = 0;
        peer.rx = 1'b1;
        peer.monitor_enable = 1'b1;
        @(negedge clk_100mhz);
        btn_reset = 1'b0;
        wait_ready();
        expect_banner();
        expect_quiet();
    endtask

    always @(posedge clk_100mhz) begin
        if (!dut.reset_n) begin
            previous_accept = 1'b0;
        end else begin
            check(!(dut.bpif.wen && dut.bpif.ren), "bus directions are mutually exclusive");
            if (dut.bpif.wen || dut.bpif.ren) begin
                check(dut.bpif.strobe == 4'hF, "bus uses full-word strobes");
                check(!led_error, "faulted controller issues no requests");
            end
            if ((dut.bpif.wen || dut.bpif.ren) && !dut.bpif.request_stall) begin
                accepted_accesses++;
                check(!previous_accept, "idle cycle separates accepted accesses");
                check(!dut.bpif.error, "all harness accesses are accepted without bus errors");
                if (dut.bpif.wen && dut.bpif.addr == 32'h00)
                    check(dut.bpif.wdata == 1, "harness selects UART only");
                if (dut.bpif.ren && dut.bpif.addr == 32'h10)
                    check(dut.usi.rx_count >= 4, "echo reads contain a full four-byte block");
                previous_accept = 1'b1;
            end else begin
                previous_accept = 1'b0;
            end
        end
    end

    initial begin : tests
        previous_accept = 1'b0;
        peer.bit_period = BIT_PERIOD;
        peer.parity_mode = 0;
        wait_ready();
        expect_banner();
        expect_quiet();

        send_byte(8'h00);
        expect_quiet();
        check(dut.usi.rx_count == 1, "one received byte held");
        send_byte(8'h55);
        expect_quiet();
        check(dut.usi.rx_count == 2, "two received bytes held");
        send_byte(8'hAA);
        expect_quiet();
        check(dut.usi.rx_count == 3, "three received bytes held");
        send_byte(8'hFF);
        expect_tx(8'h00);
        expect_tx(8'h55);
        expect_tx(8'hAA);
        expect_tx(8'hFF);
        expect_quiet();
        check(dut.usi.rx_count == 0 && !led_error, "binary echo drains RX cleanly");

        fork
            begin
                for (int lane = 0; lane < 8; lane++)
                    send_byte(8'(8'h31 + lane));
            end
            begin
                for (int lane = 0; lane < 8; lane++)
                    expect_tx(8'(8'h31 + lane));
            end
        join
        expect_quiet();
        check(led_ready && !led_error && dut.usi.rx_count == 0, "back-to-back blocks echoed in order");

        for (int lane = 0; lane < 4; lane++)
            send_byte(8'(8'hA0 + lane));
        fork
            peer.send_byte(8'h00, BIT_PERIOD);
            begin
                for (int attempt = 0; attempt < WAIT_CYCLES; attempt++) begin
                    @(negedge clk_100mhz);
                    if (!uart_tx) break;
                    if (attempt == WAIT_CYCLES-1)
                        $fatal(1, "timeout waiting for TX before mid-frame reset");
                end
                #(BIT_PERIOD * 2);
                peer.monitor_enable = 1'b0;
                btn_reset = 1'b1;
                repeat (4) @(negedge clk_100mhz);
                check(!led_ready && !led_error && uart_tx, "mid-frame reset cancels active traffic");
            end
        join
        #(BIT_PERIOD * 2);
        peer.received.delete();
        peer.earliest_next_start = 0;
        peer.monitor_enable = 1'b1;
        @(negedge clk_100mhz);
        btn_reset = 1'b0;
        wait_ready();
        expect_banner();
        expect_quiet();
        check(dut.usi.rx_count == 0 && dut.usi.tx_count == 0,
            "reset removes old queues and no old data follows the banner");

        #3;
        peer.send_byte(8'h00, BIT_PERIOD, 0, 1'b0, 1'b1);
        wait_error();
        expect_quiet();
        for (int lane = 0; lane < 4; lane++)
            send_byte(8'(lane));
        expect_quiet();
        check(led_error && !led_ready, "fault remains latched and controller halts echo");
        reset_and_restart();
        check(led_ready && !led_error, "reset recovers from fault");
        check(accepted_accesses != 0, "hardware controller generated bus accesses");

        $display("urbana_usi_uart_tb PASS: UART_DIVISOR=%0d, %0d checks, %0d accepted accesses, %0d decoded TX frames",
            UART_DIVISOR, checks, accepted_accesses, peer.frames);
        $finish;
    end

    initial begin
        #(CLOCK_PERIOD * UART_DIVISOR * 1500);
        $fatal(1, "Urbana UART harness watchdog expired");
    end
endmodule
