`timescale 1ns/1ps

module usi_bus_exerciser_tb;
    localparam int unsigned DIVISOR = 868;
    localparam int unsigned TIMEOUT = 8;
    localparam logic [31:0] ECHO_WORD = 32'hA1B2C3D4;

    logic CLK = 1'b0;
    logic nRST = 1'b0;
    logic [31:0] bus_addr, bus_wdata, bus_rdata;
    logic [3:0] bus_strobe;
    logic bus_wen, bus_ren, bus_error, bus_request_stall;
    logic ready, fault;
    logic variable_stalls = 1'b1;
    logic force_stall = 1'b0;
    logic corrupt_readback = 1'b0;
    logic inject_bus_error = 1'b0;
    logic inject_protocol_error = 1'b0;
    logic tx_blocked = 1'b0;
    logic rx_offer = 1'b0;
    logic rx_consumed;
    logic [31:0] divisor_reg, config_reg, mode_reg;
    logic [31:0] tx_words [0:3];
    int unsigned request_age, accepted, stalled_edges;
    int unsigned tx_writes, rx_reads, fifo_reads;
    int unsigned divisor_writes, config_writes, mode_writes;
    int cycle_number, mode_write_cycle;
    int unsigned checks = 0;
    logic previous_stall, previous_accept;
    logic [69:0] stalled_controls;
    wire request = bus_wen || bus_ren;

    usi_bus_exerciser #(
        .UART_DIVISOR(DIVISOR), .BUS_TIMEOUT_CYCLES(TIMEOUT)
    ) dut (.*);
    always #5 CLK = !CLK;

    task automatic check(input logic condition, input string description);
        checks++;
        if (condition !== 1'b1)
            $fatal(1, "%s", description);
    endtask

    always_comb begin
        bus_request_stall = request && (force_stall ||
            (variable_stalls && request_age < (accepted % 3 + 1)));
        bus_rdata = '0;
        bus_error = request && inject_bus_error && (bus_addr == 32'h10);
        case (bus_addr)
            32'h00: bus_rdata = mode_reg;
            32'h04: bus_rdata = divisor_reg ^ (corrupt_readback ? 32'd1 : 32'd0);
            32'h08: bus_rdata = inject_protocol_error ? 32'd4 : 32'd0;
            32'h0C: bus_rdata = tx_blocked ? 32'd8 : 32'd0;
            32'h10: bus_rdata = (rx_offer && !rx_consumed) ? ECHO_WORD : 32'hDEADBEEF;
            32'h34: bus_rdata = (rx_offer && !rx_consumed) ? 32'd4 : 32'd0;
            32'h40: bus_rdata = config_reg;
            default: bus_error = request;
        endcase
    end

    always @(posedge CLK) begin
        if (!nRST) begin
            request_age <= 0;
            accepted <= 0;
            stalled_edges <= 0;
            tx_writes <= 0;
            rx_reads <= 0;
            fifo_reads <= 0;
            divisor_writes <= 0;
            config_writes <= 0;
            mode_writes <= 0;
            divisor_reg <= 0;
            config_reg <= 0;
            mode_reg <= 0;
            rx_consumed <= 0;
            previous_stall <= 0;
            previous_accept <= 0;
            stalled_controls <= '0;
            cycle_number <= 0;
            mode_write_cycle <= -100;
            for (int i = 0; i < 4; i++) tx_words[i] <= '0;
        end else begin
            cycle_number <= cycle_number + 1;
            check(!(bus_wen && bus_ren), "read and write requests are exclusive");
            if (request) check(bus_strobe == 4'hF, "full-word strobes on every request");
            if (previous_stall && !fault) begin
                check(request, "stalled request remains asserted until acceptance");
                check({bus_addr, bus_wdata, bus_strobe, bus_wen, bus_ren} == stalled_controls,
                    "request controls remain stable through stalls");
            end
            if (previous_accept)
                check(!request, "accepted transactions have an idle gap");
            previous_stall <= request && bus_request_stall;
            previous_accept <= request && !bus_request_stall;
            stalled_controls <= {bus_addr, bus_wdata, bus_strobe, bus_wen, bus_ren};

            if (request && bus_request_stall) begin
                request_age <= request_age + 1;
                stalled_edges <= stalled_edges + 1;
            end else begin
                request_age <= 0;
            end
            if (request && !bus_request_stall) begin
                accepted <= accepted + 1;
                if (!bus_error) begin
                    if (bus_wen) begin
                        case (bus_addr)
                            32'h04: begin
                                divisor_reg <= bus_wdata;
                                divisor_writes <= divisor_writes + 1;
                            end
                            32'h40: begin
                                config_reg <= bus_wdata;
                                config_writes <= config_writes + 1;
                            end
                            32'h00: begin
                                check(bus_wdata == 1, "controller selects UART only");
                                mode_reg <= bus_wdata;
                                mode_writes <= mode_writes + 1;
                                mode_write_cycle <= cycle_number;
                            end
                            32'h10: begin
                                check(!tx_blocked, "controller respects TX backpressure");
                                check(tx_writes < 4, "no unexpected repeated FIFO writes");
                                tx_words[tx_writes] <= bus_wdata;
                                tx_writes <= tx_writes + 1;
                            end
                            default: $fatal(1, "unexpected write address %h", bus_addr);
                        endcase
                    end else begin
                        if (bus_addr == 32'h04)
                            check(cycle_number - mode_write_cycle >= 3,
                                "mode handoff gets at least two complete idle clocks");
                        if (bus_addr == 32'h0C) fifo_reads <= fifo_reads + 1;
                        if (bus_addr == 32'h10) begin
                            check(rx_offer && !rx_consumed, "RX pop occurs only when four bytes exist");
                            rx_consumed <= 1;
                            rx_reads <= rx_reads + 1;
                        end
                    end
                end
            end
        end
    end

    task automatic reset_dut;
        @(negedge CLK);
        nRST = 0;
        rx_offer = 0;
        repeat (3) @(negedge CLK);
        nRST = 1;
    endtask

    task automatic await_ready;
        for (int i = 0; i < 300; i++) begin
            @(negedge CLK);
            check(!fault, "healthy initialization does not fault");
            if (ready) begin
                check(divisor_reg == DIVISOR && config_reg == 0 && mode_reg == 1,
                    "ready follows correct configuration");
                return;
            end
        end
        $fatal(1, "timeout waiting for ready");
    endtask

    task automatic await_tx_count(input int unsigned expected);
        for (int i = 0; i < 500; i++) begin
            @(negedge CLK);
            check(!fault, "healthy traffic does not fault");
            if (tx_writes == expected) return;
        end
        $fatal(1, "timeout waiting for %0d FIFO writes", expected);
    endtask

    task automatic await_fault;
        for (int i = 0; i < 300; i++) begin
            @(negedge CLK);
            if (fault) begin
                check(!ready, "fault extinguishes ready");
                check(!request, "fault retires requests");
                return;
            end
        end
        $fatal(1, "timeout waiting for injected fault");
    endtask

    task automatic check_halted;
        force_stall = 0;
        inject_bus_error = 0;
        inject_protocol_error = 0;
        corrupt_readback = 0;
        repeat (12) begin
            @(negedge CLK);
            check(fault && !ready && !request, "fault holds until reset");
        end
    endtask

    initial begin
        tx_blocked = 1;
        reset_dut();
        await_ready();
        for (int i = 0; i < 100 && fifo_reads < 3; i++) @(negedge CLK);
        check(fifo_reads >= 3 && tx_writes == 0, "full TX queue postpones banner without duplicating writes");
        tx_blocked = 0;
        await_tx_count(1);
        check(tx_words[0] == 32'h0A495355, "banner has exact low-byte-first contents");
        rx_offer = 1;
        await_tx_count(2);
        check(tx_words[1] == ECHO_WORD && rx_reads == 1,
            "stalled echo captures pre-pop data exactly once");
        repeat (60) @(negedge CLK);
        check(tx_writes == 2 && rx_reads == 1, "drained input produces no extra banner or echo");
        check(divisor_writes == 1 && config_writes == 1 && mode_writes == 1,
            "stalled configuration writes are accepted exactly once");
        check(stalled_edges > 0, "variable-latency bus was exercised");

        corrupt_readback = 1;
        reset_dut();
        await_fault();
        check(tx_writes == 0, "bad readback prevents banner");
        check_halted();

        inject_bus_error = 1;
        reset_dut();
        await_fault();
        check(tx_writes == 0, "rejected FIFO write is not recorded as accepted");
        check_halted();

        reset_dut();
        await_tx_count(1);
        inject_protocol_error = 1;
        await_fault();
        check(tx_writes == 1, "protocol failure prevents additional data writes");
        check_halted();

        force_stall = 1;
        reset_dut();
        await_fault();
        check(stalled_edges == TIMEOUT && accepted == 0,
            "permanently stalled request times out at the configured bound");
        check_halted();

        variable_stalls = 0;
        reset_dut();
        await_ready();
        await_tx_count(1);
        repeat (30) @(negedge CLK);
        check(tx_writes == 1 && tx_words[0] == 32'h0A495355 && !fault,
            "reset recovers the controller on a zero-wait bus");
        $display("usi_bus_exerciser_tb PASS: %0d checks", checks);
        $finish;
    end

    initial begin
        #100us;
        $fatal(1, "controller test watchdog expired");
    end
endmodule
