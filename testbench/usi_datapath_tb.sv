`timescale 1ns/1ps

module usi_datapath_tb #(
    parameter int unsigned FIFO_SIZE = 256
);
    import usi_datapath_pkg::*;
    localparam int COUNT_BITS = $clog2(FIFO_SIZE+1);

    logic CLK = 1'b0;
    logic nRST = 1'b0;
    usi_mode_t active_mode = MODE_IDLE;
    logic dp_clear = 1'b0;
    dp_cmd_t uart_dp_cmd = '0;
    dp_cmd_t spi_dp_cmd = '0;
    dp_cmd_t i2c_dp_cmd = '0;
    logic rx_bit_i = 1'b0;
    dp_status_t dp_status;
    logic [31:0] tx_wdata = '0;
    logic tx_wen = 1'b0;
    logic rx_ren = 1'b0;
    logic tx_flush = 1'b0;
    logic rx_flush = 1'b0;
    logic error_clear = 1'b0;
    logic protocol_busy = 1'b0;
    logic split_apply = 1'b0;
    logic [COUNT_BITS-1:0] fifo_tx_start = COUNT_BITS'(FIFO_SIZE/2);
    logic split_ready;
    logic [31:0] rx_rdata;
    logic [2:0] rx_read_valid_bytes;
    logic tx_full, tx_empty, rx_full, rx_empty;
    logic fifo_error;
    logic [COUNT_BITS-1:0] tx_count, rx_count;
    int unsigned checks = 0;

    usi_datapath #(.FIFO_SIZE(FIFO_SIZE)) dut (.*);

    task automatic expect_true(input logic condition, input string description);
        checks++;
        if (condition !== 1'b1)
            $fatal(1, "%s (TX count=%0d, RX count=%0d)", description, tx_count, rx_count);
    endtask

    task automatic tick;
        #1 CLK = 1'b1;
        #1 CLK = 1'b0;
        #1;
    endtask

    task automatic drive_command(input dp_cmd_t command);
        uart_dp_cmd = '0;
        spi_dp_cmd = '0;
        i2c_dp_cmd = '0;
        case (active_mode)
            MODE_UART: uart_dp_cmd = command;
            MODE_SPI: spi_dp_cmd = command;
            MODE_I2C: i2c_dp_cmd = command;
            default: ;
        endcase
    endtask

    task automatic issue(input dp_cmd_t command);
        drive_command(command);
        tick();
        drive_command('0);
        #1;
    endtask

    task automatic reset_dut(input usi_mode_t mode);
        drive_command('0);
        tx_wen = 1'b0;
        rx_ren = 1'b0;
        tx_flush = 1'b0;
        rx_flush = 1'b0;
        dp_clear = 1'b0;
        error_clear = 1'b0;
        protocol_busy = 1'b0;
        split_apply = 1'b0;
        fifo_tx_start = COUNT_BITS'(FIFO_SIZE/2);
        active_mode = MODE_IDLE;
        nRST = 1'b0;
        tick();
        nRST = 1'b1;
        tick();
        active_mode = mode;
        tick();
        expect_true(tx_empty && rx_empty && !fifo_error && !dp_status.tx_active &&
            !dp_status.rx_active && !dp_status.rx_byte_valid, "reset clears queues and shifters");
        expect_true(dut.shared_fifo.tx_start == COUNT_BITS'(FIFO_SIZE/2), "reset restores equal split");
    endtask

    task automatic set_split(input int unsigned boundary);
        fifo_tx_start = COUNT_BITS'(boundary);
        #1;
        expect_true(split_ready, "idle and empty datapath accepts split");
        split_apply = 1'b1;
        tick();
        split_apply = 1'b0;
        expect_true(dut.shared_fifo.tx_start == COUNT_BITS'(boundary), "split applied to storage");
    endtask

    task automatic reject_split;
        logic [COUNT_BITS-1:0] old_boundary;
        old_boundary = dut.shared_fifo.tx_start;
        #1;
        expect_true(!split_ready, "unsafe split is not ready");
        split_apply = 1'b1;
        tick();
        split_apply = 1'b0;
        expect_true(dut.shared_fifo.tx_start == old_boundary, "unsafe split leaves partition unchanged");
    endtask

    task automatic write_tx(input logic [31:0] value);
        tx_wdata = value;
        tx_wen = 1'b1;
        tick();
        tx_wen = 1'b0;
        #1;
    endtask

    task automatic load_tx(input logic from_fifo, input logic [7:0] value,
                           input int unsigned bits = 8, input logic lsb = 1'b1);
        dp_cmd_t command;
        command = '0;
        command.tx_load = 1'b1;
        command.tx_from_fifo = from_fifo;
        command.tx_immediate = value;
        command.bit_length = 4'(bits);
        command.lsb_first = lsb;
        issue(command);
        expect_true(dp_status.tx_load_done && dp_status.tx_active && !dp_status.tx_load_failed,
            "TX load accepted");
    endtask

    task automatic shift_tx(input logic [7:0] value, input int unsigned bits = 8,
                            input logic lsb = 1'b1);
        dp_cmd_t command;
        command = '0;
        command.tx_shift = 1'b1;
        for (int bit_number = 0; bit_number < int'(bits); bit_number++) begin
            expect_true(dp_status.tx_bit == value[lsb ? bit_number : int'(bits)-1-bit_number],
                $sformatf("TX serial bit matches selected order: byte=%02h bit=%0d observed=%0b",
                    value, bit_number, dp_status.tx_bit));
            issue(command);
            expect_true(dp_status.tx_done == (bit_number == int'(bits)-1), "TX done on final shift only");
        end
        expect_true(!dp_status.tx_active && dp_status.tx_bit, "TX returns to idle after chunk");
    endtask

    task automatic receive_byte(input logic [7:0] value, input int unsigned bits = 8,
                                input logic lsb = 1'b1, input logic commit = 1'b1);
        dp_cmd_t command;
        command = '0;
        command.rx_begin = 1'b1;
        command.bit_length = 4'(bits);
        command.lsb_first = lsb;
        issue(command);
        expect_true(dp_status.rx_begin_done && !dp_status.rx_begin_failed, "RX begin accepted");
        command = '0;
        command.rx_sample = 1'b1;
        for (int bit_number = 0; bit_number < int'(bits); bit_number++) begin
            rx_bit_i = value[lsb ? bit_number : int'(bits)-1-bit_number];
            issue(command);
            expect_true(dp_status.rx_done == (bit_number == int'(bits)-1), "RX done on final sample only");
        end
        expect_true(dp_status.rx_byte_valid && !dp_status.rx_active &&
            dp_status.rx_byte == (value & (8'hFF >> (8-bits))), "RX chunk is right aligned and held");
        if (commit) begin
            command = '0;
            command.rx_commit = 1'b1;
            issue(command);
            expect_true(dp_status.rx_commit_done && !dp_status.rx_byte_valid, "RX commit queues one byte");
        end
    endtask

    task automatic read_rx(input logic [31:0] value, input int unsigned valid_bytes);
        #1;
        expect_true(rx_rdata == value && rx_read_valid_bytes == 3'(valid_bytes),
            "RX bus head and valid-byte count match");
        rx_ren = 1'b1;
        tick();
        rx_ren = 1'b0;
        #1;
    endtask

    initial begin : tests
        dp_cmd_t command;
        logic [7:0] tx_value, rx_value;
        logic [31:0] expected_word;

        for (int mode = 1; mode <= 3; mode++) begin
            reset_dut(usi_mode_t'(mode));
            for (int order = 0; order < 2; order++) begin
                for (int bits = 1; bits <= 8; bits++) begin
                    tx_value = 8'hA5;
                    rx_value = 8'hD3 & (8'hFF >> (8-bits));
                    command = '0;
                    command.tx_load = 1'b1;
                    command.tx_immediate = tx_value;
                    command.rx_begin = 1'b1;
                    command.bit_length = 4'(bits);
                    command.lsb_first = 1'(order);
                    issue(command);
                    expect_true(dp_status.tx_load_done && dp_status.rx_begin_done, "duplex start accepted");
                    command = '0;
                    command.tx_shift = 1'b1;
                    command.rx_sample = 1'b1;
                    command.lsb_first = !1'(order);
                    command.bit_length = 4'd1;
                    for (int bit_number = 0; bit_number < bits; bit_number++) begin
                        expect_true(dp_status.tx_bit == tx_value[order != 0 ? bit_number : bits-1-bit_number],
                            "duplex TX bit order is latched");
                        rx_bit_i = rx_value[order != 0 ? bit_number : bits-1-bit_number];
                        issue(command);
                        expect_true(dp_status.tx_done == (bit_number == bits-1) &&
                            dp_status.rx_done == (bit_number == bits-1), "duplex completion timing");
                    end
                    expect_true(dp_status.rx_byte_valid && dp_status.rx_byte == rx_value &&
                        !dp_status.tx_active && !dp_status.rx_active, "duplex result matches");
                    command = '0;
                    command.rx_commit = 1'b1;
                    issue(command);
                    expect_true(dp_status.rx_commit_done && rx_count == COUNT_BITS'(1), "duplex commit is one byte");
                    read_rx({24'b0, rx_value}, 1);
                end
            end
        end

        reset_dut(MODE_UART);
        write_tx(32'h44332211);
        expect_true(tx_count == COUNT_BITS'(4), "bus write queues four bytes");
        for (int lane = 0; lane < 4; lane++) begin
            load_tx(1'b1, '0);
            expect_true(tx_count == COUNT_BITS'(3-lane), "FIFO-backed load pops exactly one byte");
            shift_tx(8'(8'h11*(lane+1)));
        end
        expect_true(tx_empty && !fifo_error, "TX word drained without error");

        for (int bytes = 1; bytes <= 4; bytes++) begin
            expected_word = '0;
            for (int lane = 0; lane < bytes; lane++) begin
                receive_byte(8'(8'h60+lane));
                expected_word[8*lane +: 8] = 8'(8'h60+lane);
            end
            read_rx(expected_word, bytes);
            expect_true(rx_empty && rx_read_valid_bytes == 0 && rx_rdata == 0, "partial read drains RX");
        end

        command = '0;
        command.tx_load = 1'b1;
        command.tx_from_fifo = 1'b1;
        command.bit_length = 4'd8;
        issue(command);
        expect_true(dp_status.tx_load_failed && tx_empty && !fifo_error, "empty TX load fails without FIFO access");
        for (int invalid_length = 0; invalid_length <= 9; invalid_length += 9) begin
            command = '0;
            command.tx_load = 1'b1;
            command.rx_begin = 1'b1;
            command.bit_length = 4'(invalid_length);
            issue(command);
            expect_true(dp_status.tx_load_failed && dp_status.rx_begin_failed &&
                !dp_status.tx_active && !dp_status.rx_active, "invalid chunk lengths rejected");
        end
        command = '0;
        command.tx_shift = 1'b1;
        command.rx_sample = 1'b1;
        issue(command);
        expect_true(!dp_status.tx_done && !dp_status.rx_done, "idle shifts ignored");
        receive_byte(8'h81, 8, 1'b1, 1'b0);
        command = '0;
        command.rx_begin = 1'b1;
        command.bit_length = 4'd8;
        issue(command);
        expect_true(dp_status.rx_begin_failed && dp_status.rx_byte_valid && dp_status.rx_byte == 8'h81,
            "RX begin cannot overwrite pending byte");
        command = '0;
        command.rx_discard = 1'b1;
        issue(command);

        command = '0;
        command.tx_load = 1'b1;
        command.rx_begin = 1'b1;
        command.bit_length = 4'd8;
        spi_dp_cmd = command;
        i2c_dp_cmd = command;
        set_split(5);
        expect_true(!dp_status.tx_active && !dp_status.rx_active, "inactive protocol commands ignored");
        drive_command('0);
        for (int lane = 0; lane < 5; lane++)
            receive_byte(8'(lane));
        expect_true(rx_full && rx_count == COUNT_BITS'(5), "odd-sized RX partition fills exactly");
        read_rx(32'h03020100, 4);
        receive_byte(8'h05);
        receive_byte(8'h06);
        read_rx(32'h00060504, 3);

        fifo_tx_start = '0;
        protocol_busy = 1'b1;
        reject_split();
        protocol_busy = 1'b0;
        tick();
        expect_true(dut.shared_fifo.tx_start == COUNT_BITS'(5), "rejected request is not deferred");
        load_tx(1'b0, 8'hC7);
        reject_split();
        shift_tx(8'hC7);
        command = '0;
        command.tx_load = 1'b1;
        command.bit_length = 4'd1;
        drive_command(command);
        reject_split();
        drive_command('0);
        shift_tx(8'h00, 1, 1'b0);
        command = '0;
        command.rx_begin = 1'b1;
        command.bit_length = 4'd1;
        issue(command);
        reject_split();
        command = '0;
        command.rx_discard = 1'b1;
        issue(command);
        receive_byte(8'h5A, 8, 1'b1, 1'b0);
        reject_split();
        command = '0;
        command.rx_discard = 1'b1;
        issue(command);
        dp_clear = 1'b1;
        reject_split();
        dp_clear = 1'b0;
        tx_flush = 1'b1;
        reject_split();
        tx_flush = 1'b0;
        rx_flush = 1'b1;
        reject_split();
        rx_flush = 1'b0;
        tx_wen = 1'b1;
        reject_split();
        tx_wen = 1'b0;
        reject_split();
        tx_flush = 1'b1;
        tick();
        tx_flush = 1'b0;
        rx_ren = 1'b1;
        reject_split();
        rx_ren = 1'b0;
        error_clear = 1'b1;
        tick();
        error_clear = 1'b0;
        active_mode = MODE_SPI;
        reject_split();
        fifo_tx_start = COUNT_BITS'(FIFO_SIZE+1);
        reject_split();
        set_split(0);
        expect_true(rx_full && rx_empty && !tx_full, "all-TX partition disables RX storage");
        command = '0;
        command.rx_begin = 1'b1;
        command.bit_length = 4'd1;
        issue(command);
        command = '0;
        command.rx_sample = 1'b1;
        rx_bit_i = 1'b1;
        issue(command);
        expect_true(dp_status.rx_byte_valid && dp_status.rx_byte == 1, "all-TX mode can still sample ACK bits");
        command = '0;
        command.rx_discard = 1'b1;
        issue(command);

        for (int word_number = 0; word_number < FIFO_SIZE/4; word_number++) begin
            expected_word = '0;
            for (int lane = 0; lane < 4; lane++)
                expected_word[8*lane +: 8] = 8'(4*word_number+lane);
            write_tx(expected_word);
        end
        expect_true(tx_count == COUNT_BITS'(FIFO_SIZE) && tx_full, "all-TX full depth count");
        write_tx(32'hDEADBEEF);
        expect_true(fifo_error && tx_count == COUNT_BITS'(FIFO_SIZE), "overflow rejected and sticky");
        error_clear = 1'b1;
        write_tx(32'hDEADBEEF);
        expect_true(fifo_error, "new software error wins error clear");
        tick();
        error_clear = 1'b0;
        expect_true(!fifo_error, "error clear removes old error");
        for (int byte_number = 0; byte_number < FIFO_SIZE; byte_number++) begin
            load_tx(1'b1, '0);
            shift_tx(8'(byte_number));
        end
        write_tx(32'h87654321);
        load_tx(1'b1, '0);
        shift_tx(8'h21);
        tx_flush = 1'b1;
        tick();
        tx_flush = 1'b0;

        set_split(FIFO_SIZE);
        protocol_busy = 1'b1;
        expect_true(tx_full && tx_empty && !rx_full, "all-RX partition disables TX storage");
        load_tx(1'b0, 8'hFF);
        shift_tx(8'hFF); 
        for (int byte_number = 0; byte_number < FIFO_SIZE; byte_number++)
            receive_byte(8'(byte_number));
        expect_true(rx_count == COUNT_BITS'(FIFO_SIZE) && rx_full, "all-RX full depth count");
        receive_byte(8'hE7, 8, 1'b1, 1'b0);
        command = '0;
        command.rx_commit = 1'b1;
        issue(command);
        expect_true(dp_status.rx_commit_failed && dp_status.rx_byte_valid && !fifo_error &&
            rx_count == COUNT_BITS'(FIFO_SIZE), "full RX holds rejected chunk for retry");
        expect_true(rx_rdata == 32'h03020100, "full RX presents oldest data");
        rx_ren = 1'b1;
        issue(command);
        rx_ren = 1'b0;
        expect_true(dp_status.rx_commit_done && !dp_status.rx_byte_valid &&
            rx_count == COUNT_BITS'(FIFO_SIZE-3), "RX pop and commit share edge safely");
        for (int byte_number = 4; byte_number < FIFO_SIZE; byte_number += 4) begin
            expected_word = '0;
            for (int lane = 0; lane < 4; lane++)
                expected_word[8*lane +: 8] = 8'(byte_number+lane);
            read_rx(expected_word, 4);
        end
        read_rx(32'h000000E7, 1);
        rx_ren = 1'b1;
        tick();
        rx_ren = 1'b0;
        expect_true(fifo_error, "empty software RX read sets sticky error");
        tx_flush = 1'b1;
        tick();
        tx_flush = 1'b0;
        expect_true(fifo_error, "TX flush does not clear RX error");
        rx_flush = 1'b1;
        tick();
        rx_flush = 1'b0;
        expect_true(!fifo_error, "RX flush clears RX error");
        protocol_busy = 1'b0;

        set_split(FIFO_SIZE-4);
        write_tx(32'h04030201);
        for (int lane = 1; lane <= 3; lane++) begin
            load_tx(1'b1, '0);
            shift_tx(8'(lane));
        end
        expect_true(tx_full && tx_count == 1, "less than a bus word free reports TX full");
        tx_wdata = 32'hA4A3A2A1;
        tx_wen = 1'b1;
        command = '0;
        command.tx_load = 1'b1;
        command.tx_from_fifo = 1'b1;
        command.bit_length = 4'd8;
        command.lsb_first = 1'b1;
        issue(command);
        tx_wen = 1'b0;
        expect_true(dp_status.tx_load_done && tx_count == 4 && !fifo_error, "TX pop supplies write credit");
        shift_tx(8'h04);
        for (int lane = 0; lane < 4; lane++) begin
            load_tx(1'b1, '0);
            shift_tx(8'(8'hA1+lane));
        end

        set_split(FIFO_SIZE/2);
        write_tx(32'h44332211);
        receive_byte(8'h81);
        receive_byte(8'h82);
        receive_byte(8'h83);
        receive_byte(8'hA6, 8, 1'b1, 1'b0);
        expect_true(rx_rdata == 32'h00838281, "concurrent RX read presents old head");
        tx_wdata = 32'h88776655;
        tx_wen = 1'b1;
        rx_ren = 1'b1;
        command = '0;
        command.tx_load = 1'b1;
        command.tx_from_fifo = 1'b1;
        command.rx_commit = 1'b1;
        command.rx_begin = 1'b1;
        command.bit_length = 4'd3;
        issue(command);
        tx_wen = 1'b0;
        rx_ren = 1'b0;
        expect_true(dp_status.tx_load_done && dp_status.rx_commit_done && dp_status.rx_begin_done &&
            tx_count == 7 && rx_count == 1 && !fifo_error, "all four queue operations accepted");
        command = '0;
        command.tx_shift = 1'b1;
        command.rx_sample = 1'b1;
        for (int bit_number = 2; bit_number >= 0; bit_number--) begin
            tx_value = 8'h11;
            rx_value = 8'h05;
            expect_true(dp_status.tx_bit == tx_value[bit_number], "concurrent TX uses pre-pop byte");
            rx_bit_i = rx_value[bit_number];
            issue(command);
        end
        expect_true(dp_status.rx_byte_valid && dp_status.rx_byte == 8'h05, "new RX configuration latched");
        command = '0;
        command.rx_commit = 1'b1;
        issue(command);
        read_rx(32'h000005A6, 2);
        for (int lane = 2; lane <= 8; lane++) begin
            load_tx(1'b1, '0);
            shift_tx(8'(8'h11*lane));
        end

        set_split(FIFO_SIZE/2);
        write_tx(32'h76543210);
        receive_byte(8'hAB);
        load_tx(1'b1, '0);
        command = '0;
        command.rx_begin = 1'b1;
        command.bit_length = 4'd8;
        issue(command);
        dp_clear = 1'b1;
        tick();
        dp_clear = 1'b0;
        expect_true(!dp_status.tx_active && !dp_status.rx_active && tx_count == 3 && rx_count == 1,
            "datapath clear preserves FIFO data");
        command = '0;
        command.tx_load = 1'b1;
        command.tx_from_fifo = 1'b1;
        command.bit_length = 4'd8;
        active_mode = MODE_I2C;
        drive_command(command);
        tick();
        drive_command('0);
        expect_true(!dp_status.tx_active && tx_count == 3 && rx_count == 1, "handoff suppresses new command");
        tx_flush = 1'b1;
        tick();
        tx_flush = 1'b0;
        expect_true(tx_empty && rx_count == 1, "TX flush preserves RX queue");
        read_rx(32'h000000AB, 1);
        active_mode = MODE_IDLE;
        tick();
        set_split(0);

        $display("usi_datapath_tb PASS: FIFO_SIZE=%0d, %0d checks", FIFO_SIZE, checks);
        $finish;
    end
endmodule
