module uart #(
    parameter int CLKDIV_BITS = 16
)(
    input logic CLK,
    input logic nRST,
    input logic uart_en,
    input logic abort,
    input logic tx_flush,
    input logic rx_flush,
    input logic [CLKDIV_BITS-1:0] clkdiv,
    // [1:0]: 0=none, 1=odd, 2=even; [2]: enable flow control
    input logic [2:0] uart_config,
    input logic uart_rx,
    input logic uart_cts,
    input logic error_clear,

    input usi_datapath_pkg::dp_status_t dp_status,
    output usi_datapath_pkg::dp_cmd_t dp_cmd,

    output logic rx_bit,
    output logic uart_tx,
    output logic uart_rts,
    output logic busy,
    output logic frame_done,
    output logic parity_error,
    output logic frame_error,
    output logic rx_overrun
);

    typedef enum logic [2:0] {
        TX_IDLE, TX_START, TX_DATA, TX_PARITY, TX_STOP
    } tx_state_t;

    typedef enum logic [2:0] {
        RX_IDLE, RX_START, RX_DATA, RX_PARITY, RX_STOP
    } rx_state_t;

    tx_state_t tx_state, next_tx_state;
    rx_state_t rx_state, next_rx_state;

    logic rx_meta, rx_sync, rx_previous;
    logic cts_meta, cts_sync;
    logic baud_valid, tx_start, rx_start;

    logic [CLKDIV_BITS-1:0] tx_period, rx_period;
    logic [CLKDIV_BITS-1:0] tx_timer, rx_timer;
    logic [2:0] tx_index, rx_index;
    logic [1:0] tx_parity_mode, rx_parity_mode;

    logic tx_parity, rx_bad;
    logic expected_rx_parity;

    // Synchronize external RX and CTS inputs.
    always_ff @(posedge CLK or negedge nRST) begin : INPUT_SYNC
        if (!nRST) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
            rx_previous <= 1'b1;
            cts_meta <= 1'b0;
            cts_sync <= 1'b0;
        end else begin
            rx_meta <= uart_rx;
            rx_sync <= rx_meta;
            rx_previous <= rx_sync;
            cts_meta <= uart_cts;
            cts_sync <= cts_meta;
        end
    end

    assign rx_bit = rx_sync;
    assign baud_valid = (clkdiv >= CLKDIV_BITS'(8));

    assign tx_start = uart_en && baud_valid && !abort && !tx_flush &&
        (tx_state == TX_IDLE) && !dp_status.tx_active &&
        dp_status.tx_fifo_valid && (!uart_config[2] || cts_sync);

    assign rx_start = uart_en && baud_valid && !abort && !rx_flush &&
        (rx_state == RX_IDLE) && rx_previous && !rx_sync &&
        !dp_status.rx_active && !dp_status.rx_byte_valid;

    assign busy = uart_en &&
        ((tx_state != TX_IDLE) || (rx_state != RX_IDLE) ||
        tx_start || rx_start);

    assign uart_rts = uart_en && baud_valid && uart_config[2] &&
        dp_status.rx_fifo_ready && !abort && !rx_flush;

    always_comb begin : TX_Next_State
        next_tx_state = tx_state;

        case (tx_state)
            TX_IDLE: begin
                if (tx_start) begin
                    next_tx_state = TX_START;
                end
            end

            TX_START: begin
                if (tx_timer == '0) begin
                    next_tx_state = TX_DATA;
                end
            end

            TX_DATA: begin
                if (tx_timer == '0 && tx_index == 3'd7) begin
                    next_tx_state = (tx_parity_mode == 0)
                        ? TX_STOP : TX_PARITY;
                end
            end

            TX_PARITY: begin
                if (tx_timer == '0) begin
                    next_tx_state = TX_STOP;
                end
            end

            TX_STOP: begin
                if (tx_timer == '0) begin
                    next_tx_state = TX_IDLE;
                end
            end

            default: next_tx_state = TX_IDLE;
        endcase
    end

    always_comb begin : RX_Next_State
        next_rx_state = rx_state;

        case (rx_state)
            RX_IDLE: begin
                if (rx_start) begin
                    next_rx_state = RX_START;
                end
            end

            RX_START: begin
                if (rx_timer == '0) begin
                    next_rx_state = rx_sync ? RX_IDLE : RX_DATA;
                end
            end

            RX_DATA: begin
                if (rx_timer == '0 && rx_index == 3'd7) begin
                    next_rx_state = (rx_parity_mode == 0)
                        ? RX_STOP : RX_PARITY;
                end
            end

            RX_PARITY: begin
                if (rx_timer == '0) begin
                    next_rx_state = RX_STOP;
                end
            end

            RX_STOP: begin
                if (rx_timer == '0) begin
                    next_rx_state = RX_IDLE;
                end
            end

            default: next_rx_state = RX_IDLE;
        endcase
    end

    always_comb begin : STATE_OUTPUTS
        // Default configuration
        dp_cmd = '0;
        dp_cmd.bit_length = 4'd8;
        dp_cmd.lsb_first = 1'b1;
        dp_cmd.tx_from_fifo = 1'b1;
        dp_cmd.tx_load = tx_start;

        // Default TX output
        uart_tx = 1'b1;

        // TX outputs
        if (uart_en && !abort && !tx_flush) begin
            dp_cmd.tx_shift =
                (tx_state == TX_DATA) && (tx_timer == '0);

            case (tx_state)
                TX_START: begin
                    uart_tx = 1'b0;
                end

                TX_DATA: begin
                    uart_tx = dp_status.tx_bit;
                end

                TX_PARITY: begin
                    // Invert the data XOR for odd parity.
                    uart_tx = tx_parity ^ (tx_parity_mode == 2'd1);
                end

                default: begin
                    uart_tx = 1'b1;
                end
            endcase
        end

        // RX outputs
        if (uart_en && !abort && !rx_flush) begin
            case (rx_state)
                RX_START: begin
                    // Confirm the start bit at its midpoint.
                    dp_cmd.rx_begin = (rx_timer == '0) && !rx_sync;
                end

                RX_DATA: begin
                    dp_cmd.rx_sample = (rx_timer == '0);
                end

                RX_STOP: begin
                    if (rx_timer == '0) begin
                        if (rx_sync && !rx_bad &&
                            dp_status.rx_byte_valid &&
                            dp_status.rx_fifo_ready) begin
                            dp_cmd.rx_commit = 1'b1;
                        end else begin
                            dp_cmd.rx_discard = 1'b1;
                        end
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
            tx_state <= TX_IDLE;
            rx_state <= RX_IDLE;
        end else begin
            if (!uart_en || abort || tx_flush) begin
                tx_state <= TX_IDLE;
            end else begin
                tx_state <= next_tx_state;
            end

            if (!uart_en || abort || rx_flush) begin
                rx_state <= RX_IDLE;
            end else begin
                rx_state <= next_rx_state;
            end
        end
    end

    always_comb begin : PARITY_CHECK
        // Even parity uses the data XOR; odd parity inverts it.
        expected_rx_parity =
            (^dp_status.rx_byte) ^ (rx_parity_mode == 2'd1);
    end

    // TX bit counter, baud timer, and parity calculation.
    always_ff @(posedge CLK or negedge nRST) begin : TX_Counter_And_Parity
        if (!nRST) begin
            tx_period <= '0;
            tx_timer <= '0;
            tx_index <= '0;
            tx_parity_mode <= '0;
            tx_parity <= 1'b0;
        end else if (!uart_en || abort || tx_flush) begin
            tx_timer <= '0;
            tx_index <= '0;
            tx_parity <= 1'b0;
        end else begin
            if ((tx_state != TX_IDLE) && (tx_timer != '0)) begin
                tx_timer <= tx_timer - 1'b1;
            end

            case (tx_state)
                TX_IDLE: begin
                    if (tx_start) begin
                        tx_period <= clkdiv;
                        tx_timer <= clkdiv - 1'b1;
                        tx_parity_mode <= uart_config[1:0];
                        tx_index <= '0;
                        tx_parity <= 1'b0;
                    end
                end

                TX_START: begin
                    if (tx_timer == '0) begin
                        tx_timer <= tx_period - 1'b1;
                    end
                end

                TX_DATA: begin
                    if (tx_timer == '0) begin
                        tx_timer <= tx_period - 1'b1;
                        tx_parity <= tx_parity ^ dp_status.tx_bit;
                        tx_index <= tx_index + 1'b1;
                    end
                end

                TX_PARITY: begin
                    if (tx_timer == '0) begin
                        tx_timer <= tx_period - 1'b1;
                    end
                end

                default: begin
                    // No additional updates.
                end
            endcase
        end
    end

    // RX bit counter, baud timer, and saved parity result.
    always_ff @(posedge CLK or negedge nRST) begin : RX_Counter_And_Parity
        if (!nRST) begin
            rx_period <= '0;
            rx_timer <= '0;
            rx_index <= '0;
            rx_parity_mode <= '0;
            rx_bad <= 1'b0;
        end else if (!uart_en || abort || rx_flush) begin
            rx_timer <= '0;
            rx_index <= '0;
            rx_bad <= 1'b0;
        end else begin
            if ((rx_state != RX_IDLE) && (rx_timer != '0)) begin
                rx_timer <= rx_timer - 1'b1;
            end

            case (rx_state)
                RX_IDLE: begin
                    if (rx_start) begin
                        rx_period <= clkdiv;
                        rx_timer <= (clkdiv >> 1) - 1'b1;
                        rx_parity_mode <= uart_config[1:0];
                        rx_index <= '0;
                        rx_bad <= 1'b0;
                    end
                end

                RX_START: begin
                    if (rx_timer == '0) begin
                        rx_timer <= rx_period - 1'b1;
                    end
                end

                RX_DATA: begin
                    if (rx_timer == '0) begin
                        rx_timer <= rx_period - 1'b1;
                        rx_index <= rx_index + 1'b1;
                    end
                end

                RX_PARITY: begin
                    if (rx_timer == '0) begin
                        rx_bad <= (rx_sync != expected_rx_parity);
                        rx_timer <= rx_period - 1'b1;
                    end
                end

                default: begin
                    // No additional updates.
                end
            endcase
        end
    end

    always_ff @(posedge CLK or negedge nRST) begin : ERROR_FLAGS
        if (!nRST) begin
            parity_error <= 1'b0;
            frame_error <= 1'b0;
            rx_overrun <= 1'b0;
            frame_done <= 1'b0;
        end else begin
            frame_done <= 1'b0;

            if (error_clear) begin
                parity_error <= 1'b0;
                frame_error <= 1'b0;
                rx_overrun <= 1'b0;
            end

            if (uart_en && !abort) begin
                if (!tx_flush &&
                    (tx_state == TX_STOP) && (tx_timer == '0)) begin
                    frame_done <= 1'b1;
                end

                if (!rx_flush) begin
                    if ((rx_state == RX_PARITY) &&
                        (rx_timer == '0) &&
                        (rx_sync != expected_rx_parity)) begin
                        parity_error <= 1'b1;
                    end

                    if ((rx_state == RX_STOP) && (rx_timer == '0)) begin
                        if (!rx_sync) begin
                            frame_error <= 1'b1;
                        end else if (!rx_bad &&
                            (!dp_status.rx_byte_valid ||
                            !dp_status.rx_fifo_ready)) begin
                            rx_overrun <= 1'b1;
                        end

                        if (dp_cmd.rx_commit) begin
                            frame_done <= 1'b1;
                        end
                    end
                end
            end
        end
    end

endmodule
