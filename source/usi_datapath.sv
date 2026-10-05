package usi_datapath_pkg;
    typedef enum logic [2:0] {
        MODE_IDLE = 3'd0,
        MODE_UART = 3'd1,
        MODE_SPI  = 3'd2,
        MODE_I2C  = 3'd3
    } usi_mode_t;

    typedef struct packed {
        logic       tx_load;
        logic       tx_from_fifo;
        logic [7:0] tx_immediate;
        logic       tx_shift;
        logic       rx_begin;
        logic       rx_sample;
        logic       rx_commit;
        logic       rx_discard;
        logic       lsb_first;
        logic [3:0] bit_length;
    } dp_cmd_t;

    typedef struct packed {
        logic       tx_fifo_valid;
        logic       rx_fifo_ready;
        logic       tx_active;
        logic       rx_active;
        logic       tx_bit;
        logic [7:0] rx_byte;
        logic       rx_byte_valid;
        logic       tx_load_done;
        logic       tx_load_failed;
        logic       tx_done;
        logic       rx_begin_done;
        logic       rx_begin_failed;
        logic       rx_done;
        logic       rx_commit_done;
        logic       rx_commit_failed;
    } dp_status_t;
endpackage

module usi_datapath #(
    parameter unsigned TX_FIFO_SIZE = 16,
    parameter unsigned RX_FIFO_SIZE = 16
)(
    input logic CLK,
    input logic nRST,
    input usi_datapath_pkg::usi_mode_t active_mode,
    input logic dp_clear,
    input usi_datapath_pkg::dp_cmd_t uart_dp_cmd,
    input usi_datapath_pkg::dp_cmd_t spi_dp_cmd,
    input usi_datapath_pkg::dp_cmd_t i2c_dp_cmd,
    input logic rx_bit_i,
    output usi_datapath_pkg::dp_status_t dp_status,

    // Regmap interface. FIFO size and count in bytes
    input logic [31:0] tx_wdata,
    input logic tx_wen,
    input logic rx_ren,
    input logic tx_flush,
    input logic rx_flush,
    input logic error_clear,
    output logic [31:0] rx_rdata,
    output logic [2:0] rx_read_valid_bytes,
    output logic tx_full,
    output logic tx_empty,
    output logic rx_full,
    output logic rx_empty,
    output logic fifo_error,
    output logic [$clog2(TX_FIFO_SIZE+1)-1:0] tx_count,
    output logic [$clog2(RX_FIFO_SIZE+1)-1:0] rx_count
);
    import usi_datapath_pkg::*;

    dp_cmd_t selected_dp_cmd;
    usi_mode_t previous_mode;
    logic mode_valid, mode_changed, bit_length_valid;
    logic engine_clear, tx_clear, rx_clear;
    logic [7:0] tx_fifo_rdata, tx_load_data, tx_payload;
    logic [7:0] rx_parallel_data, rx_byte;
    logic tx_shift_bit;
    logic tx_pop, rx_push;
    logic tx_load_accept, tx_shift_accept;
    logic rx_begin_accept, rx_sample_accept, rx_commit_accept;
    logic tx_active, rx_active, rx_byte_valid;
    logic tx_lsb_first, rx_lsb_first;
    logic [3:0] tx_bits_left, rx_bits_left;
    logic [2:0] chunk_padding, rx_padding;
    logic tx_load_done, tx_load_failed, tx_done;
    logic rx_begin_done, rx_begin_failed, rx_done;
    logic rx_commit_done, rx_commit_failed;
    logic tx_overrun, tx_underrun, rx_overrun, rx_underrun;

    // Active protocol sends requests, other protocols are idle
    always_comb begin
        selected_dp_cmd = '0;
        mode_valid = 1'b1;
        case (active_mode)
            MODE_UART: selected_dp_cmd = uart_dp_cmd;
            MODE_SPI: selected_dp_cmd = spi_dp_cmd;`
            MODE_I2C: selected_dp_cmd = i2c_dp_cmd;
            default: mode_valid = 1'b0;
        endcase
    end

    always_ff @(posedge CLK or negedge nRST) begin
        if (!nRST)
            previous_mode <= MODE_IDLE;
        else
            previous_mode <= active_mode;
    end

    // Changing protocols ignores commands on the handoff edge 
    // Abort/clear cancels active data but preserves FIFOs
    // Directional flush cancels that shifter AND clears FIFO
    assign mode_changed = (active_mode != previous_mode);
    assign engine_clear = !nRST || dp_clear || mode_changed || !mode_valid;
    assign tx_clear = engine_clear || tx_flush;
    assign rx_clear = engine_clear || rx_flush || selected_dp_cmd.rx_discard;
    assign bit_length_valid = (selected_dp_cmd.bit_length >= 4'd1) && (selected_dp_cmd.bit_length <= 4'd8);
    assign chunk_padding = 3'(4'd8 - selected_dp_cmd.bit_length);
    assign tx_active = (tx_bits_left != 4'd0);
    assign rx_active = (rx_bits_left != 4'd0);

    // Load >> shift
    assign tx_load_accept = !tx_clear && selected_dp_cmd.tx_load && bit_length_valid && !tx_active && (!selected_dp_cmd.tx_from_fifo || !tx_empty);
    assign tx_shift_accept = !tx_clear && selected_dp_cmd.tx_shift && tx_active && !selected_dp_cmd.tx_load;
    assign tx_pop = tx_load_accept && selected_dp_cmd.tx_from_fifo;
    assign tx_payload = selected_dp_cmd.tx_from_fifo ? tx_fifo_rdata : selected_dp_cmd.tx_immediate;
    assign tx_load_data = selected_dp_cmd.lsb_first ? tx_payload : (tx_payload << chunk_padding);

    // RX chunk stays in the shifter until discard/commit
    // Old chunk is queued while the shifter clears 
    // Discard >> Begin >> Sample 
    assign rx_commit_accept = !rx_clear && selected_dp_cmd.rx_commit && rx_byte_valid && !rx_full;
    assign rx_begin_accept = !rx_clear && selected_dp_cmd.rx_begin && bit_length_valid && !rx_active && (!rx_byte_valid || rx_commit_accept);
    assign rx_sample_accept = !rx_clear && selected_dp_cmd.rx_sample && rx_active && !selected_dp_cmd.rx_begin;
    assign rx_push = rx_commit_accept;
    assign rx_byte = rx_lsb_first ? (rx_parallel_data >> rx_padding) : rx_parallel_data;

    // Software writes four bytes, low lane first
    asym_fifo #(
        .READ_BYTES(1),
        .WRITE_BYTES(4),
        .DEPTH_BYTES(TX_FIFO_SIZE)
    ) tx_fifo (
        .CLK(CLK),
        .nRST(nRST),
        .WEN(tx_wen),
        .REN(tx_pop),
        .clear_underrun(error_clear),
        .clear_overrun(error_clear),
        .flush(tx_flush),
        .wdata(tx_wdata),
        .full(tx_full),
        .empty(tx_empty),
        .underrun(tx_underrun),
        .overrun(tx_overrun),
        .count(tx_count),
        .rdata(tx_fifo_rdata),
        .read_valid_bytes()
    );

    // RX commits one byte
    // Bus read drains up to four bytes, zero-fills unused lanes
    // Concurrent commit is queued after the read
    asym_fifo #(
        .READ_BYTES(4),
        .WRITE_BYTES(1),
        .DEPTH_BYTES(RX_FIFO_SIZE),
        .ALLOW_PARTIAL_READ(1'b1)
    ) rx_fifo (
        .CLK(CLK),
        .nRST(nRST),
        .WEN(rx_push),
        .REN(rx_ren),
        .clear_underrun(error_clear),
        .clear_overrun(error_clear),
        .flush(rx_flush),
        .wdata(rx_byte),
        .full(rx_full),
        .empty(rx_empty),
        .underrun(rx_underrun),
        .overrun(rx_overrun),
        .count(rx_count),
        .rdata(rx_rdata),
        .read_valid_bytes(rx_read_valid_bytes)
    );

    shift_register tx_sr (
        .CLK(CLK),
        .nRST(nRST),
        .parallel_load(tx_clear || tx_load_accept),
        .parallel_in(tx_clear ? 8'b0 : tx_load_data),
        .shift_en(tx_shift_accept),
        .msb_first(!tx_lsb_first),
        .shift_in(1'b0),
        .shift_out(tx_shift_bit),
        .parallel_out()
    );

    shift_register rx_sr (
        .CLK(CLK),
        .nRST(nRST),
        .parallel_load(rx_clear || rx_begin_accept),
        .parallel_in(8'b0),
        .shift_en(rx_sample_accept),
        .msb_first(!rx_lsb_first),
        .shift_in(rx_bit_i),
        .shift_out(),
        .parallel_out(rx_parallel_data)
    );

    always_ff @(posedge CLK or negedge nRST) begin
        if (!nRST) begin
            tx_bits_left <= '0;
            tx_lsb_first <= 1'b0;
            tx_load_done <= 1'b0;
            tx_load_failed <= 1'b0;
            tx_done <= 1'b0;
        end else begin
            tx_load_done <= tx_load_accept;
            tx_load_failed <= !tx_clear && selected_dp_cmd.tx_load && !tx_load_accept;
            tx_done <= tx_shift_accept && (tx_bits_left == 4'd1);

            if (tx_clear) begin
                tx_bits_left <= '0;
                tx_lsb_first <= 1'b0;
            end else if (tx_load_accept) begin
                tx_bits_left <= selected_dp_cmd.bit_length;
                tx_lsb_first <= selected_dp_cmd.lsb_first;
            end else if (tx_shift_accept) begin
                tx_bits_left <= tx_bits_left - 4'd1;
            end
        end
    end

    always_ff @(posedge CLK or negedge nRST) begin
        if (!nRST) begin
            rx_bits_left <= '0;
            rx_byte_valid <= 1'b0;
            rx_lsb_first <= 1'b0;
            rx_padding <= '0;
            rx_begin_done <= 1'b0;
            rx_begin_failed <= 1'b0;
            rx_done <= 1'b0;
            rx_commit_done <= 1'b0;
            rx_commit_failed <= 1'b0;
        end else begin
            rx_begin_done <= rx_begin_accept;
            rx_begin_failed <= !rx_clear && selected_dp_cmd.rx_begin && !rx_begin_accept;
            rx_done <= rx_sample_accept && (rx_bits_left == 4'd1);
            rx_commit_done <= rx_commit_accept;
            rx_commit_failed <= !rx_clear && selected_dp_cmd.rx_commit && !rx_commit_accept;

            if (rx_clear) begin
                rx_bits_left <= '0;
                rx_byte_valid <= 1'b0;
                rx_lsb_first <= 1'b0;
                rx_padding <= '0;
            end else begin
                if (rx_commit_accept)
                    rx_byte_valid <= 1'b0;
                if (rx_begin_accept) begin
                    rx_bits_left <= selected_dp_cmd.bit_length;
                    rx_byte_valid <= 1'b0;
                    rx_lsb_first <= selected_dp_cmd.lsb_first;
                    rx_padding <= chunk_padding;
                end else if (rx_sample_accept) begin
                    rx_bits_left <= rx_bits_left - 4'd1;
                    if (rx_bits_left == 4'd1)
                        rx_byte_valid <= 1'b1;
                end
            end
        end
    end

    // Completion/failure strobes for one cycle after the request edge
    // fifo_error and protocol errors bundled together in register_map.procol_error
    // Error >> Clear
    assign fifo_error = tx_overrun || tx_underrun || rx_overrun || rx_underrun;
    always_comb begin
        dp_status = '0;
        dp_status.tx_fifo_valid = !tx_empty && !tx_flush;
        dp_status.rx_fifo_ready = !rx_full && !rx_flush;
        dp_status.tx_active = tx_active && !tx_clear;
        dp_status.rx_active = rx_active && !rx_clear;
        dp_status.tx_bit = (tx_active && !tx_clear) ? tx_shift_bit : 1'b1;
        dp_status.rx_byte = rx_clear ? 8'b0 : rx_byte;
        dp_status.rx_byte_valid = rx_byte_valid && !rx_clear;
        dp_status.tx_load_done = tx_load_done && !tx_clear;
        dp_status.tx_load_failed = tx_load_failed && !tx_clear;
        dp_status.tx_done = tx_done && !tx_clear;
        dp_status.rx_begin_done = rx_begin_done && !rx_clear;
        dp_status.rx_begin_failed = rx_begin_failed && !rx_clear;
        dp_status.rx_done = rx_done && !rx_clear;
        dp_status.rx_commit_done = rx_commit_done && !rx_clear;
        dp_status.rx_commit_failed = rx_commit_failed && !rx_clear;
    end
endmodule
