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
        logic [15:0] tx_immediate;
        logic       tx_shift;
        logic       rx_begin;
        logic       rx_sample;
        logic       rx_commit;
        logic       rx_discard;
        logic       lsb_first;
        logic [4:0] bit_length;
    } dp_cmd_t;

    typedef struct packed {
        logic       tx_fifo_valid;
        logic       rx_fifo_ready;
        logic       tx_active;
        logic       rx_active;
        logic       tx_bit;
        logic [15:0] rx_byte;
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
    parameter unsigned FIFO_SIZE = 256 
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

    // Regmap interface. size and counts are in bytes.
    input logic [31:0] tx_wdata,
    input logic tx_wen,
    input logic rx_ren,
    input logic tx_flush,
    input logic rx_flush,
    input logic error_clear,
    input logic protocol_busy,
    input logic split_apply,
    input logic [$clog2(FIFO_SIZE+1)-1:0] fifo_tx_start,
    output logic split_ready,
    output logic [31:0] rx_rdata,
    output logic [2:0] rx_read_valid_bytes,
    output logic tx_full,
    output logic tx_empty,
    output logic rx_full,
    output logic rx_empty,
    output logic fifo_error,
    output logic [$clog2(FIFO_SIZE+1)-1:0] tx_count,
    output logic [$clog2(FIFO_SIZE+1)-1:0] rx_count
);
    import usi_datapath_pkg::*;

    localparam int COUNT_BITS = $clog2(FIFO_SIZE+1);

    dp_cmd_t selected_dp_cmd;
    usi_mode_t previous_mode;
    logic mode_valid, mode_changed, bit_length_valid;
    logic engine_clear, tx_clear, rx_clear, rx_path_clear;
    logic [15:0] tx_fifo_rdata;
    logic [15:0] tx_load_data, tx_payload;
    logic [15:0] rx_parallel_data, rx_byte;
    logic [1:0] requested_bytes, rx_fifo_bytes;
    logic tx_shift_bit;
    logic tx_pop, rx_push;
    logic tx_load_accept, tx_shift_accept;
    logic rx_begin_accept, rx_sample_accept, rx_commit_accept;
    logic tx_active, rx_active, rx_byte_valid;
    logic tx_lsb_first, rx_lsb_first;
    logic [4:0] tx_bits_left, rx_bits_left;
    logic [3:0] chunk_padding, rx_padding;
    logic tx_load_done, tx_load_failed, tx_done;
    logic rx_begin_done, rx_begin_failed, rx_done;
    logic rx_commit_done, rx_commit_failed;
    logic tx_overrun, rx_underrun;
    logic fifo_busy, command_pending;
    logic rx_space_available;

    generate
        if (FIFO_SIZE < 4) begin : INVALID_FIFO_SIZE
            $error("%m: FIFO_SIZE must be at least four bytes");
        end
    endgenerate

    always_comb begin
        selected_dp_cmd = '0;
        mode_valid = 1'b1;
        case (active_mode)
            MODE_UART: selected_dp_cmd = uart_dp_cmd;
            MODE_SPI: selected_dp_cmd = spi_dp_cmd;
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
    assign mode_changed = (active_mode != previous_mode);
    assign engine_clear = !nRST || dp_clear || mode_changed || !mode_valid;
    assign tx_clear = engine_clear || tx_flush;
    assign rx_path_clear = engine_clear || rx_flush;
    assign rx_clear = rx_path_clear || selected_dp_cmd.rx_discard;
    assign bit_length_valid = (selected_dp_cmd.bit_length >= 5'd1) && (selected_dp_cmd.bit_length <= 5'd16);
    assign chunk_padding = 4'(5'd16 - selected_dp_cmd.bit_length);
    assign tx_active = (tx_bits_left != 5'd0);
    assign rx_active = (rx_bits_left != 5'd0);

    // FIFO accounting stays byte-based: 1-8 bits use one byte, 9-16 use two.
    // RX size follows the latched chunk, including commit + begin on one edge.
    assign requested_bytes = (selected_dp_cmd.bit_length > 5'd8) ? 2'd2 : 2'd1;
    assign rx_fifo_bytes = (rx_active || rx_byte_valid) ?
        ((rx_padding < 4'd8) ? 2'd2 : 2'd1) : requested_bytes;

    // Load >> shift
    assign tx_load_accept = !tx_clear && selected_dp_cmd.tx_load && bit_length_valid && !tx_active &&
        (!selected_dp_cmd.tx_from_fifo || (tx_count >= COUNT_BITS'(requested_bytes)));
    assign tx_shift_accept = !tx_clear && selected_dp_cmd.tx_shift && tx_active && !selected_dp_cmd.tx_load;
    assign tx_pop = tx_load_accept && selected_dp_cmd.tx_from_fifo;
    assign tx_payload = selected_dp_cmd.tx_from_fifo ? tx_fifo_rdata : selected_dp_cmd.tx_immediate;
    assign tx_load_data = selected_dp_cmd.lsb_first ? tx_payload : (tx_payload << chunk_padding);

    // Old chunk is queued while the shifter clears 
    // Discard >> Begin >> Sample 
    assign rx_commit_accept = !rx_clear && selected_dp_cmd.rx_commit && rx_byte_valid && !rx_full;
    assign rx_begin_accept = !rx_clear && selected_dp_cmd.rx_begin && bit_length_valid && !rx_active && (!rx_byte_valid || rx_commit_accept);
    assign rx_sample_accept = !rx_clear && selected_dp_cmd.rx_sample && rx_active && !selected_dp_cmd.rx_begin;
    assign rx_push = rx_commit_accept;
    assign rx_byte = rx_lsb_first ? (rx_parallel_data >> rx_padding) : rx_parallel_data;

    // Repartition between transactions
    assign command_pending = selected_dp_cmd.tx_load || selected_dp_cmd.tx_shift ||
        selected_dp_cmd.rx_begin || selected_dp_cmd.rx_sample ||
        selected_dp_cmd.rx_commit || selected_dp_cmd.rx_discard;
    assign fifo_busy = protocol_busy || tx_active || rx_active || rx_byte_valid || command_pending;
    assign split_ready = nRST && !fifo_busy && !dp_clear && !mode_changed &&
        tx_empty && rx_empty && !tx_wen && !rx_ren && !tx_flush && !rx_flush &&
        (fifo_tx_start <= COUNT_BITS'(FIFO_SIZE));

    split_fifo #(
        .DEPTH_BYTES(FIFO_SIZE),
        .BUSIF_BYTES(4),
        .DP_BYTES(2)
    ) shared_fifo (
        .clk(CLK),
        .nRST(nRST),
        .tx_wdata(tx_wdata),
        .tx_push(tx_wen),
        .tx_pop(tx_pop),
        .tx_flush(tx_flush),
        .tx_pop_num_bytes(requested_bytes),
        .tx_rdata(tx_fifo_rdata),
        .tx_empty(tx_empty),
        .tx_full(tx_full),
        .tx_occupancy(tx_count),
        .rx_wdata(rx_byte),
        .rx_push(rx_push),
        .rx_pop(rx_ren),
        .rx_flush(rx_flush),
        .rx_push_num_bytes(rx_fifo_bytes),
        .rx_rdata(rx_rdata),
        .rx_empty(rx_empty),
        .rx_full(rx_full),
        .rx_space_available(rx_space_available),
        .rx_occupancy(rx_count),
        .dp_busy(fifo_busy),
        .split_apply(split_apply && split_ready),
        .fifo_tx_start(fifo_tx_start)
    );

    assign rx_read_valid_bytes = (rx_count >= 4) ? 3'd4 : 3'(rx_count);

    always_ff @(posedge CLK or negedge nRST) begin
        if (!nRST) begin
            tx_overrun <= 1'b0;
            rx_underrun <= 1'b0;
        end else begin
            tx_overrun <= !tx_flush && ((tx_wen && tx_full) || (tx_overrun && !error_clear));
            rx_underrun <= !rx_flush && ((rx_ren && rx_empty) || (rx_underrun && !error_clear));
        end
    end

    shift_register tx_sr (
        .CLK(CLK),
        .nRST(nRST),
        .parallel_load(tx_clear || tx_load_accept),
        .parallel_in(tx_clear ? 16'b0 : tx_load_data),
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
        .parallel_in(16'b0),
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
            tx_done <= tx_shift_accept && (tx_bits_left == 5'd1);

            if (tx_clear) begin
                tx_bits_left <= '0;
                tx_lsb_first <= 1'b0;
            end else if (tx_load_accept) begin
                tx_bits_left <= selected_dp_cmd.bit_length;
                tx_lsb_first <= selected_dp_cmd.lsb_first;
            end else if (tx_shift_accept) begin
                tx_bits_left <= tx_bits_left - 5'd1;
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
            rx_done <= rx_sample_accept && (rx_bits_left == 5'd1);
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
                    rx_bits_left <= rx_bits_left - 5'd1;
                    if (rx_bits_left == 5'd1)
                        rx_byte_valid <= 1'b1;
                end
            end
        end
    end

    // fifo_error and protocol errors bundled together in register_map.procol_error
    // Error >> Clear
    assign fifo_error = tx_overrun || rx_underrun;
    always_comb begin
        dp_status = '0;
        dp_status.tx_fifo_valid = (tx_count >= COUNT_BITS'(requested_bytes)) && !tx_clear;
        dp_status.rx_fifo_ready = rx_space_available && !rx_path_clear;
        dp_status.tx_active = tx_active && !tx_clear;
        dp_status.rx_active = rx_active && !rx_path_clear;
        dp_status.tx_bit = (tx_active && !tx_clear) ? tx_shift_bit : 1'b1;
        dp_status.rx_byte = rx_path_clear ? 16'b0 : rx_byte;
        dp_status.rx_byte_valid = rx_byte_valid && !rx_path_clear;
        dp_status.tx_load_done = tx_load_done && !tx_clear;
        dp_status.tx_load_failed = tx_load_failed && !tx_clear;
        dp_status.tx_done = tx_done && !tx_clear;
        dp_status.rx_begin_done = rx_begin_done && !rx_path_clear;
        dp_status.rx_begin_failed = rx_begin_failed && !rx_path_clear;
        dp_status.rx_done = rx_done && !rx_path_clear;
        dp_status.rx_commit_done = rx_commit_done && !rx_path_clear;
        dp_status.rx_commit_failed = rx_commit_failed && !rx_path_clear;
    end
endmodule
