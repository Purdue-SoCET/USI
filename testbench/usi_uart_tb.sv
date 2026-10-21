`timescale 1ns/1ps

module usi_uart_tb #(
    parameter int unsigned FIFO_SIZE = 256
);
    localparam time CLOCK_PERIOD = 10ns;
    logic CLK = 1'b0;
    logic nRST = 1'b0;
    bus_protocol_if bpif();
    logic uart_rx, uart_tx, uart_rts;
    logic uart_cts = 1'b1;
    logic spi_miso = 1'b0;
    logic spi_mosi, spi_sclk, spi_cs;
    tri1 i2c_sda, i2c_scl;
    int unsigned checks = 0;

    USI #(.FIFO_SIZE(FIFO_SIZE)) dut (.*);
    uart_peer peer (.nRST(nRST), .tx(uart_tx), .rx(uart_rx));
    always #(CLOCK_PERIOD/2) CLK = !CLK;

    task automatic check(input logic condition, input string description);
        checks++;
        if (condition !== 1'b1)
            $fatal(1, "%s", description);
    endtask

    task automatic bus_idle;
        bpif.wen = 1'b0;
        bpif.ren = 1'b0;
        bpif.addr = '0;
        bpif.wdata = '0;
        bpif.strobe = 4'hF;
    endtask

    // Sample before, read head after (acceptance edge)
    task automatic write_reg(input logic [31:0] address, input logic [31:0] value,
                             input logic expected_error = 1'b0, input logic [3:0] strobe = 4'hF);
        @(negedge CLK);
        bpif.addr = address;
        bpif.wdata = value;
        bpif.strobe = strobe;
        bpif.wen = 1'b1;
        bpif.ren = 1'b0;
        #1;
        check(!bpif.request_stall && bpif.error == expected_error,
            $sformatf("write %02h=%08h: error=%0b expected=%0b", address, value, bpif.error, expected_error));
        @(posedge CLK);
        @(negedge CLK);
        bus_idle();
        #1;
    endtask

    task automatic read_reg(input logic [31:0] address, output logic [31:0] value);
        @(negedge CLK);
        bpif.addr = address;
        bpif.ren = 1'b1;
        bpif.wen = 1'b0;
        bpif.strobe = 4'hF;
        #1;
        check(!bpif.request_stall && !bpif.error, $sformatf("read %02h accepted", address));
        value = bpif.rdata;
        @(posedge CLK);
        @(negedge CLK);
        bus_idle();
        #1;
    endtask

    task automatic expect_reg(input logic [31:0] address, input logic [31:0] expected);
        logic [31:0] value;
        read_reg(address, value);
        check(value == expected, $sformatf("register %02h: got %08h expected %08h", address, value, expected));
    endtask

    task automatic wait_idle;
        logic [31:0] status;
        for (int attempt = 0; attempt < 2000; attempt++) begin
            read_reg(32'h08, status);
            if (!status[0]) return;
        end
        $fatal(1, "timeout waiting for protocol idle");
    endtask

    task automatic expect_tx(input logic [7:0] expected);
        logic [7:0] observed;
        for (int attempt = 0; attempt < 2000; attempt++) begin
            if (peer.received.size() != 0) begin
                observed = peer.received.pop_front();
                check(observed == expected, $sformatf("TX got %02h expected %02h", observed, expected));
                return;
            end
            @(negedge CLK);
        end
        $fatal(1, "timeout waiting for TX byte %02h", expected);
    endtask

    task automatic wait_rx_count(input int unsigned expected);
        logic [31:0] count;
        for (int attempt = 0; attempt < 200; attempt++) begin
            read_reg(32'h34, count);
            if (count >= expected) return;
        end
        $fatal(1, "timeout waiting for RX count %0d", expected);
    endtask

    task automatic configure_uart(input int unsigned divisor, input logic [2:0] config_bits = '0);
        wait_idle();
        peer.bit_period = CLOCK_PERIOD * divisor;
        peer.parity_mode = config_bits[1:0];
        write_reg(32'h04, divisor);
        write_reg(32'h40, {29'b0, config_bits});
        write_reg(32'h00, 32'd1);
        repeat (4) @(negedge CLK);
    endtask

    task automatic reset_dut;
        @(negedge CLK);
        bus_idle();
        peer.monitor_enable = 1'b0;
        peer.rx = 1'b1;
        uart_cts = 1'b1;
        nRST = 1'b0;
        repeat (4) @(negedge CLK);
        nRST = 1'b1;
        repeat (4) @(negedge CLK);
        peer.received.delete();
        peer.monitor_enable = 1'b1;
        expect_reg(32'h00, 0);
        expect_reg(32'h08, 0);
        expect_reg(32'h34, 0);
        expect_reg(32'h38, 0);
        expect_reg(32'h44, FIFO_SIZE/2);
        check(uart_tx && spi_cs && !spi_sclk && !spi_mosi && i2c_sda && i2c_scl, "idle pads are safe");
    endtask

    initial begin : tests
        logic [31:0] status;
        time skew_period;
        reset_dut();
        write_reg(32'h00, 32'd2, 1'b1); // SPI not wired yet
        expect_reg(32'h00, 0);
        write_reg(32'h10, 32'h44332211);
        expect_reg(32'h38, 4);
        configure_uart(20);
        expect_tx(8'h11);
        expect_tx(8'h22);
        expect_tx(8'h33);
        expect_tx(8'h44);
        read_reg(32'h08, status);
        check(status[0], "protocol remains busy through the stop bit");
        wait_idle();
        expect_reg(32'h38, 0);
        expect_reg(32'h08, 2);
        write_reg(32'h30, 2);
        expect_reg(32'h08, 0);

        #3;
        peer.send_byte(8'hD3, peer.bit_period);
        expect_reg(32'h34, 1);
        expect_reg(32'h10, 32'h000000D3);
        expect_reg(32'h48, 1);
        expect_reg(32'h34, 0);
        for (int bytes = 2; bytes <= 4; bytes++) begin
            status = '0;
            for (int lane = 0; lane < bytes; lane++) begin
                peer.send_byte(8'(8'h81+lane), peer.bit_period);
                status[8*lane +: 8] = 8'(8'h81+lane);
            end
            expect_reg(32'h48, 32'(bytes-1)); 
            expect_reg(32'h10, status);
            expect_reg(32'h48, 32'(bytes));
        end

        fork
            begin
                #7;
                for (int lane = 0; lane < 4; lane++)
                    peer.send_byte(8'(8'hF0+lane), peer.bit_period);
            end
            begin
                write_reg(32'h10, 32'hC33C5AA5);
                expect_tx(8'hA5);
                expect_tx(8'h5A);
                expect_tx(8'h3C);
                expect_tx(8'hC3);
            end
        join
        wait_idle();
        expect_reg(32'h10, 32'hF3F2F1F0);

        for (int parity = 1; parity <= 2; parity++) begin
            configure_uart(20, 3'(parity));
            write_reg(32'h10, 32'h0080FFA5);
            expect_tx(8'hA5);
            expect_tx(8'hFF);
            expect_tx(8'h80);
            expect_tx(8'h00);
            wait_idle();
            peer.send_byte(8'h85, peer.bit_period, 2'(parity));
            expect_reg(32'h10, 32'h85);
            peer.send_byte(8'h5C, peer.bit_period, 2'(parity), 1'b1);
            expect_reg(32'h34, 0);
            read_reg(32'h08, status);
            check(status[2], "bad parity sets sticky protocol error and drops frame");
            write_reg(32'h30, 4);
            read_reg(32'h08, status);
            check(!status[2], "error clear clears parity error");
        end
        write_reg(32'h40, 3, 1'b1); // Reserved for parity encoding
        configure_uart(20);
        peer.send_byte(8'h00, peer.bit_period, 0, 1'b0, 1'b1);
        expect_reg(32'h34, 0);
        read_reg(32'h08, status);
        check(status[2], "low stop bit sets framing error and drops frame");
        write_reg(32'h30, 4);
        peer.send_byte(8'hA6, peer.bit_period);
        expect_reg(32'h10, 32'hA6);

        peer.rx = 1'b0;
        #(peer.bit_period/4);
        peer.rx = 1'b1;
        #(peer.bit_period*2);
        expect_reg(32'h34, 0);
        read_reg(32'h08, status);
        check(!status[2], "false start ignored without error");
        write_reg(32'h10, 32'hDEADBEEF, 1'b1, 4'b0001);
        expect_reg(32'h38, 0);

        configure_uart(20, 3'd4);
        uart_cts = 1'b0;
        repeat (4) @(negedge CLK);
        write_reg(32'h10, 32'h44332211);
        #(peer.bit_period*12);
        check(uart_tx && peer.received.size() == 0, "CTS blocks new TX frames");
        expect_reg(32'h38, 4);
        write_reg(32'h44, 0, 1'b1); 
        uart_cts = 1'b1;
        @(negedge uart_tx);
        #(peer.bit_period*2);
        uart_cts = 1'b0;
        expect_tx(8'h11);
        wait_idle();
        expect_reg(32'h38, 3);
        check(uart_tx, "CTS deassertion does not truncate current frame");
        uart_cts = 1'b1;
        expect_tx(8'h22);
        expect_tx(8'h33);
        expect_tx(8'h44);
        wait_idle();

        write_reg(32'h44, 5);
        expect_reg(32'h44, 5);
        check(uart_rts, "RTS grants RX when space is available");
        for (int lane = 0; lane < 5; lane++)
            peer.send_byte(8'(8'hA0+lane), peer.bit_period);
        expect_reg(32'h34, 5);
        check(!uart_rts, "RTS deasserts at RX full");
        peer.send_byte(8'hFE, peer.bit_period);
        expect_reg(32'h34, 5);
        read_reg(32'h08, status);
        check(status[2], "RX overrun is reported without overwriting queued data");
        expect_reg(32'h10, 32'hA3A2A1A0);
        peer.send_byte(8'hA5, peer.bit_period);
        expect_reg(32'h10, 32'h0000A5A4);
        check(uart_rts, "RTS recovers after drain");
        write_reg(32'h30, 4);

        fork
            peer.send_byte(8'h00, peer.bit_period);
            begin
                #(peer.bit_period*2);
                write_reg(32'h04, 31, 1'b1);
                write_reg(32'h40, 2, 1'b1);
                write_reg(32'h00, 0, 1'b1);
                write_reg(32'h44, 0, 1'b1);
                write_reg(32'h3C, 1); // Abort drops only the inflight chunk
            end
        join
        wait_idle();
        expect_reg(32'h04, 20);
        expect_reg(32'h34, 0);
        expect_reg(32'h44, 5);
        write_reg(32'h44, FIFO_SIZE+1, 1'b1);

        configure_uart(20);
        write_reg(32'h44, FIFO_SIZE);
        for (int lane = 0; lane < FIFO_SIZE; lane++)
            peer.send_byte(8'(lane), peer.bit_period);
        expect_reg(32'h34, FIFO_SIZE);
        expect_reg(32'h44, FIFO_SIZE);
        write_reg(32'h44, 0, 1'b1);
        write_reg(32'h14, 1); 
        expect_reg(32'h34, 0);
        expect_reg(32'h44, FIFO_SIZE);
        write_reg(32'h44, 0);
        configure_uart(20, 3'd4);
        uart_cts = 1'b0;
        repeat (4) @(negedge CLK);
        write_reg(32'h10, 32'h76543210);
        expect_reg(32'h38, 4);
        write_reg(32'h14, 2);
        expect_reg(32'h38, 0);
        expect_reg(32'h44, 0);
        uart_cts = 1'b1;
        write_reg(32'h44, FIFO_SIZE/2);

        for (int speed = 0; speed < 3; speed++) begin
            configure_uart(speed == 0 ? 8 : speed == 1 ? 13 : 31);
            write_reg(32'h10, 32'hFF0055AA);
            expect_tx(8'hAA);
            expect_tx(8'h55);
            expect_tx(8'h00);
            expect_tx(8'hFF);
            wait_idle();
            #3;
            skew_period = (peer.bit_period*102)/100;
            peer.send_byte(8'h55, skew_period);
            wait_rx_count(1);
            expect_reg(32'h10, 32'h55);
            #7;
            skew_period = (peer.bit_period*98)/100;
            peer.send_byte(8'hA5, skew_period);
            wait_rx_count(1);
            expect_reg(32'h10, 32'hA5);
        end
        wait_idle();
        check(peer.received.size() == 0, "no unexpected extra TX bytes");
        read_reg(32'h08, status);
        check(!status[2], "clean traffic leaves no protocol error");

        peer.monitor_enable = 1'b0;
        write_reg(32'h10, 32'h12345678);
        fork
            peer.send_byte(8'h00, peer.bit_period);
            begin
                #(peer.bit_period*2);
                @(negedge CLK);
                nRST = 1'b0;
                repeat (4) @(negedge CLK);
                nRST = 1'b1;
            end
        join
        reset_dut();
        $display("usi_uart_tb PASS: FIFO_SIZE=%0d, %0d checks, %0d decoded TX frames", FIFO_SIZE, checks, peer.frames);
        $finish;
    end

    initial begin
        #5ms;
        $fatal(1, "UART integration test watchdog expired");
    end
endmodule
