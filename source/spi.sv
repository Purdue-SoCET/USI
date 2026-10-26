// SPI master: Mode 0, 8 bits, MSB first.
// One TX byte and one RX byte per accepted start.
// clkdiv: CLK cycles per SCLK half period, minimum 8.
module spi #(
    parameter int CLKDIV_BITS = 16
)(
    input logic CLK,
    input logic nRST,
    input logic spi_en,
    input logic start,
    input logic abort,
    input logic tx_flush,
    input logic rx_flush,
    input logic [CLKDIV_BITS-1:0] clkdiv,
    input logic spi_miso,
    input logic error_clear,

    input usi_datapath_pkg::dp_status_t dp_status,
    output usi_datapath_pkg::dp_cmd_t dp_cmd,

    output logic rx_bit,
    output logic spi_mosi,
    output logic spi_sclk,
    output logic spi_cs_n,
    output logic busy,
    output logic frame_done,
    output logic dp_error,
    output logic dp_clear_req
);

    typedef enum logic [1:0] {
        SPI_IDLE, SPI_TRANSFER, SPI_HOLD, SPI_COMMIT
    } spi_state_t;

    spi_state_t spi_state, next_spi_state;

    logic miso_meta, miso_sync;
    logic clkdiv_valid, transfer_start, cancel_transfer;
    logic transfer_failed, rx_ready_to_commit;

    logic [CLKDIV_BITS-1:0] spi_period, spi_timer;
    logic [2:0] bit_index;
    logic sclk_level;

    // Synchronize the external MISO input.
    always_ff @(posedge CLK or negedge nRST) begin : INPUT_SYNC
        if (!nRST) begin
            miso_meta <= 1'b0;
            miso_sync <= 1'b0;
        end else begin
            miso_meta <= spi_miso;
            miso_sync <= miso_meta;
        end
    end

    assign rx_bit = miso_sync;
    assign clkdiv_valid = (clkdiv >= CLKDIV_BITS'(8));
    assign cancel_transfer = !spi_en || abort || tx_flush || rx_flush;

    assign transfer_start = !cancel_transfer && !dp_clear_req &&
        clkdiv_valid && start && (spi_state == SPI_IDLE) &&
        dp_status.tx_fifo_valid && dp_status.rx_fifo_ready &&
        !dp_status.tx_active && !dp_status.rx_active &&
        !dp_status.rx_byte_valid;

    assign busy = spi_en &&
        ((spi_state != SPI_IDLE) || transfer_start || dp_clear_req);

    assign rx_ready_to_commit = dp_status.rx_byte_valid &&
        dp_status.rx_fifo_ready &&
        !dp_status.tx_active && !dp_status.rx_active;

    // Check datapath requests and received-byte availability.
    assign transfer_failed =
        ((spi_state == SPI_TRANSFER) &&
            (dp_status.tx_load_failed || dp_status.rx_begin_failed)) ||
        ((spi_state == SPI_HOLD) &&
            (spi_timer == '0) && !rx_ready_to_commit) ||
        ((spi_state == SPI_COMMIT) &&
            dp_status.rx_commit_failed);

    always_comb begin : SPI_Next_State
        next_spi_state = spi_state;

        case (spi_state)
            SPI_IDLE: begin
                if (transfer_start) begin
                    next_spi_state = SPI_TRANSFER;
                end
            end

            SPI_TRANSFER: begin
                if (spi_timer == '0 && sclk_level &&
                    bit_index == 3'd7) begin
                    next_spi_state = SPI_HOLD;
                end
            end

            SPI_HOLD: begin
                if (spi_timer == '0) begin
                    next_spi_state = SPI_COMMIT;
                end
            end

            SPI_COMMIT: begin
                if (dp_status.rx_commit_done) begin
                    next_spi_state = SPI_IDLE;
                end
            end

            default: next_spi_state = SPI_IDLE;
        endcase
    end

    always_comb begin : STATE_OUTPUTS
        // Default pin outputs
        spi_mosi = 1'b1;
        spi_sclk = 1'b0;
        spi_cs_n = 1'b1;

        // Default datapath configuration
        dp_cmd = '0;
        dp_cmd.bit_length = 4'd8;
        dp_cmd.lsb_first = 1'b0;
        dp_cmd.tx_from_fifo = 1'b1;

        if (nRST && !cancel_transfer && !dp_clear_req) begin
            case (spi_state)
                SPI_IDLE: begin
                    // Load TX data and prepare RX at the same edge.
                    dp_cmd.tx_load = transfer_start;
                    dp_cmd.rx_begin = transfer_start;
                end

                SPI_TRANSFER: begin
                    spi_cs_n = 1'b0;
                    spi_sclk = sclk_level;
                    spi_mosi = dp_status.tx_bit;

                    if (spi_timer == '0 && !transfer_failed) begin
                        if (!sclk_level) begin
                            // Rising edge: sample MISO.
                            dp_cmd.rx_sample = 1'b1;
                        end else begin
                            // Falling edge: advance MOSI.
                            dp_cmd.tx_shift = 1'b1;
                        end
                    end
                end

                SPI_HOLD: begin
                    spi_cs_n = 1'b0;

                    if (spi_timer == '0 && rx_ready_to_commit) begin
                        // Store the received byte in the RX FIFO.
                        dp_cmd.rx_commit = 1'b1;
                    end
                end

                default: begin
                    // Keep default values: no request.
                end
            endcase
        end
    end

    always_ff @(posedge CLK or negedge nRST) begin : State_Register
        if (!nRST) begin
            spi_state <= SPI_IDLE;
        end else if (cancel_transfer || transfer_failed) begin
            spi_state <= SPI_IDLE;
        end else begin
            spi_state <= next_spi_state;
        end
    end

    // SPI clock timer and bit counter.
    always_ff @(posedge CLK or negedge nRST) begin : SPI_Counter_And_Clock
        if (!nRST) begin
            spi_period <= '0;
            spi_timer <= '0;
            bit_index <= '0;
            sclk_level <= 1'b0;
        end else if (cancel_transfer || transfer_failed) begin
            spi_timer <= '0;
            bit_index <= '0;
            sclk_level <= 1'b0;
        end else begin
            if ((spi_state == SPI_TRANSFER || spi_state == SPI_HOLD) &&
                (spi_timer != '0)) begin
                spi_timer <= spi_timer - 1'b1;
            end

            case (spi_state)
                SPI_IDLE: begin
                    if (transfer_start) begin
                        spi_period <= clkdiv;
                        spi_timer <= clkdiv - 1'b1;
                        bit_index <= '0;
                        sclk_level <= 1'b0;
                    end
                end

                SPI_TRANSFER: begin
                    if (spi_timer == '0) begin
                        spi_timer <= spi_period - 1'b1;
                        sclk_level <= ~sclk_level;

                        if (sclk_level) begin
                            // Keep the index at seven after the final bit.
                            if (bit_index == 3'd7) begin
                                bit_index <= bit_index;
                            end else begin
                                bit_index <= bit_index + 1'b1;
                            end
                        end
                    end
                end

                default: begin
                    // No additional updates.
                end
            endcase
        end
    end

    // Error flag, completion pulse, and datapath cleanup.
    always_ff @(posedge CLK or negedge nRST) begin : ERROR_FLAGS
        if (!nRST) begin
            dp_error <= 1'b0;
            frame_done <= 1'b0;
            dp_clear_req <= 1'b0;
        end else begin
            frame_done <= 1'b0;
            dp_clear_req <= 1'b0;

            if (error_clear) begin
                dp_error <= 1'b0;
            end

            // Cancel both datapath shifters after an interrupted frame.
            if ((cancel_transfer && spi_state != SPI_IDLE) ||
                transfer_failed) begin
                dp_clear_req <= 1'b1;
            end

            // A new error takes priority over error_clear.
            if (!cancel_transfer && transfer_failed) begin
                dp_error <= 1'b1;
            end

            // Report completion after the RX commit is acknowledged.
            if (!cancel_transfer && !transfer_failed &&
                spi_state == SPI_COMMIT &&
                dp_status.rx_commit_done) begin
                frame_done <= 1'b1;
            end
        end
    end

endmodule