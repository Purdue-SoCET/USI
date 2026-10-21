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
    // [1:0]: 0=none, 1=odd, 2=even; [2]: active-high 
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

    tx_state_t tx_state;
    rx_state_t rx_state;
    logic rx_meta, rx_sync, rx_previous;
    logic cts_meta, cts_sync;
    logic baud_valid, tx_start, rx_start;
    logic [CLKDIV_BITS-1:0] tx_period, rx_period, tx_timer, rx_timer;
    logic [2:0] tx_index, rx_index;
    logic [1:0] tx_parity_mode, rx_parity_mode;
    logic tx_parity, rx_bad;
    logic expected_rx_parity;

    always_ff @(posedge CLK or negedge nRST) begin
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
        (tx_state == TX_IDLE) && !dp_status.tx_active && dp_status.tx_fifo_valid &&
        (!uart_config[2] || cts_sync);
    assign rx_start = uart_en && baud_valid && !abort && !rx_flush &&
        (rx_state == RX_IDLE) && rx_previous && !rx_sync &&
        !dp_status.rx_active && !dp_status.rx_byte_valid;
    assign busy = uart_en &&
        ((tx_state != TX_IDLE) || (rx_state != RX_IDLE) || tx_start || rx_start);
    assign expected_rx_parity = (^dp_status.rx_byte) ^ (rx_parity_mode == 2'd1);
    assign uart_rts = uart_en && baud_valid && uart_config[2] &&
        dp_status.rx_fifo_ready && !abort && !rx_flush;

    // The datapath stores only the eight payload bits. Start, parity and stop
    always_comb begin
        uart_tx = 1'b1;
        if (uart_en && !abort && !tx_flush) begin
            case (tx_state)
                TX_START: uart_tx = 1'b0;
                TX_DATA: uart_tx = dp_status.tx_bit;
                TX_PARITY: uart_tx = tx_parity ^ (tx_parity_mode == 2'd1);
                default: ;
            endcase
        end

        dp_cmd = '0;
        dp_cmd.bit_length = 4'd8;
        dp_cmd.lsb_first = 1'b1;
        dp_cmd.tx_from_fifo = 1'b1;
        dp_cmd.tx_load = tx_start;
        if (uart_en && !abort && !tx_flush)
            dp_cmd.tx_shift = (tx_state == TX_DATA) && (tx_timer == '0);

        if (uart_en && !abort && !rx_flush) begin
            case (rx_state)
                RX_START: dp_cmd.rx_begin = (rx_timer == '0) && !rx_sync;
                RX_DATA: dp_cmd.rx_sample = (rx_timer == '0);
                RX_STOP: begin
                    if (rx_timer == '0) begin
                        if (rx_sync && !rx_bad && dp_status.rx_byte_valid && dp_status.rx_fifo_ready)
                            dp_cmd.rx_commit = 1'b1;
                        else
                            dp_cmd.rx_discard = 1'b1;
                    end
                end
                default: ;
            endcase
        end
    end

    // TX and RX need independent baud phases for full duplex
    always_ff @(posedge CLK or negedge nRST) begin
        if (!nRST) begin
            tx_state <= TX_IDLE;
            tx_period <= '0;
            tx_timer <= '0;
            tx_index <= '0;
            tx_parity_mode <= '0;
            tx_parity <= 1'b0;
        end else if (!uart_en || abort || tx_flush) begin
            tx_state <= TX_IDLE;
            tx_timer <= '0;
            tx_index <= '0;
            tx_parity <= 1'b0;
        end else begin
            if ((tx_state != TX_IDLE) && (tx_timer != '0))
                tx_timer <= tx_timer - 1'b1;
            case (tx_state)
                TX_IDLE: begin
                    if (tx_start) begin
                        tx_state <= TX_START;
                        tx_period <= clkdiv;
                        tx_timer <= clkdiv - 1'b1;
                        tx_parity_mode <= uart_config[1:0];
                        tx_index <= '0;
                        tx_parity <= 1'b0;
                    end
                end
                TX_START: begin
                    if (tx_timer == '0) begin
                        tx_state <= TX_DATA;
                        tx_timer <= tx_period - 1'b1;
                    end
                end
                TX_DATA: begin
                    if (tx_timer == '0) begin
                        tx_timer <= tx_period - 1'b1;
                        tx_parity <= tx_parity ^ dp_status.tx_bit;
                        tx_index <= tx_index + 1'b1;
                        if (tx_index == 3'd7)
                            tx_state <= (tx_parity_mode == 0) ? TX_STOP : TX_PARITY;
                    end
                end
                TX_PARITY: begin
                    if (tx_timer == '0) begin
                        tx_state <= TX_STOP;
                        tx_timer <= tx_period - 1'b1;
                    end
                end
                TX_STOP: if (tx_timer == '0) tx_state <= TX_IDLE;
                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    always_ff @(posedge CLK or negedge nRST) begin
        if (!nRST) begin
            rx_state <= RX_IDLE;
            rx_period <= '0;
            rx_timer <= '0;
            rx_index <= '0;
            rx_parity_mode <= '0;
            rx_bad <= 1'b0;
        end else if (!uart_en || abort || rx_flush) begin
            rx_state <= RX_IDLE;
            rx_timer <= '0;
            rx_index <= '0;
            rx_bad <= 1'b0;
        end else begin
            if ((rx_state != RX_IDLE) && (rx_timer != '0))
                rx_timer <= rx_timer - 1'b1;
            case (rx_state)
                RX_IDLE: begin
                    if (rx_start) begin
                        rx_state <= RX_START;
                        rx_period <= clkdiv;
                        rx_timer <= (clkdiv >> 1) - 1'b1;
                        rx_parity_mode <= uart_config[1:0];
                        rx_index <= '0;
                        rx_bad <= 1'b0;
                    end
                end
                RX_START: begin
                    if (rx_timer == '0) begin
                        rx_state <= rx_sync ? RX_IDLE : RX_DATA;
                        rx_timer <= rx_period - 1'b1;
                    end
                end
                RX_DATA: begin
                    if (rx_timer == '0) begin
                        rx_timer <= rx_period - 1'b1;
                        rx_index <= rx_index + 1'b1;
                        if (rx_index == 3'd7)
                            rx_state <= (rx_parity_mode == 0) ? RX_STOP : RX_PARITY;
                    end
                end
                RX_PARITY: begin
                    if (rx_timer == '0) begin
                        rx_bad <= (rx_sync != expected_rx_parity);
                        rx_state <= RX_STOP;
                        rx_timer <= rx_period - 1'b1;
                    end
                end
                RX_STOP: if (rx_timer == '0) rx_state <= RX_IDLE;
                default: rx_state <= RX_IDLE;
            endcase
        end
    end

    always_ff @(posedge CLK or negedge nRST) begin
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
                if (!tx_flush && (tx_state == TX_STOP) && (tx_timer == '0))
                    frame_done <= 1'b1;
                if (!rx_flush) begin
                    if ((rx_state == RX_PARITY) && (rx_timer == '0) && (rx_sync != expected_rx_parity))
                        parity_error <= 1'b1;
                    if ((rx_state == RX_STOP) && (rx_timer == '0)) begin
                        if (!rx_sync)
                            frame_error <= 1'b1;
                        else if (!rx_bad && (!dp_status.rx_byte_valid || !dp_status.rx_fifo_ready))
                            rx_overrun <= 1'b1;
                        if (dp_cmd.rx_commit)
                            frame_done <= 1'b1;
                    end
                end
            end
        end
    end
endmodule
