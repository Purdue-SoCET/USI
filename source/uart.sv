module uart (
    input logic CLK,
    input logic nRST,
    input logic uart_en,
    input logic serial_tick,
    input logic uart_rx,
    input logic [1:0] parity_mode,
    input logic flow_control_en,
    input logic uart_cts,
    input logic rx_full,
    input logic tx_empty,
    input logic [7:0] tx_rdata,
    input logic [7:0] rx_byte,
    input logic clear_parity_error,
    input logic clear_frame_error,
    output logic tx_load,
    output logic [7:0] tx_data,
    output logic tx_shift_en,
    output logic tx_REN,
    output logic rx_shift_en,
    output logic rx_WEN,
    output logic parity_error,
    output logic frame_error,
    output logic uart_rts,
    output logic tx_active,
    output logic rx_active
);

    typedef enum logic [1:0] {
        IDLE, START, DATA, PARITY
    } uart_state_t;

    uart_state_t rx_state, next_rx_state;
    uart_state_t tx_state, next_tx_state;

    logic [2:0] tx_bit_count, next_tx_bit_count;
    logic [2:0] rx_bit_count, next_rx_bit_count;
    logic parity_bit, next_parity_bit;
    logic next_frame_error, next_parity_error;
    logic next_rx_WEN;

    always_ff @(posedge CLK, negedge nRST) begin
        if (~nRST) begin
            tx_state <= IDLE;
            rx_state <= IDLE;
            tx_bit_count <= 3'b0;
            rx_bit_count <= 3'b0;
            parity_bit <= 1'b0;
            parity_error <= 1'b0;
            frame_error <= 1'b0;
            rx_WEN <= 1'b0;
        end
        else begin
            tx_state <= next_tx_state;
            rx_state <= next_rx_state;
            tx_bit_count <= next_tx_bit_count;
            rx_bit_count <= next_rx_bit_count;
            parity_bit <= next_parity_bit;
            parity_error <= next_parity_error;
            frame_error <= next_frame_error;
            rx_WEN <= next_rx_WEN;
        end
    end

// TX Logic
    always_comb begin : TX_State_Transitions 
        next_tx_state = tx_state;
        case(tx_state)
            IDLE: begin
                if (!tx_empty && uart_cts && uart_en && serial_tick) begin
                    next_tx_state = START;
                end
            end
            START: begin
                if (serial_tick) begin
                    next_tx_state = DATA;
                end
            end
            DATA: begin
                if (serial_tick && tx_bit_count == 3'd7) begin
                    next_tx_state = (^parity_mode) ? PARITY : IDLE;
                end
            end
            PARITY: begin
                if (serial_tick) begin
                    next_tx_state = IDLE;
                end
            end
        endcase
    end

    always_comb begin : TX_Outputs
        next_tx_bit_count = tx_bit_count;
        tx_data = 8'hFF;
        tx_load = 1'b0;
        tx_REN = 1'b0;
        next_parity_bit = parity_bit;
        tx_shift_en = 1'b0;
        tx_active = 1'b1;
        case(tx_state)
            IDLE: begin
                tx_load = 1'b1;
                tx_active = 1'b0;
            end
            START: begin
                tx_data[0] = 1'b0;
                tx_load = 1'b1;
                if (serial_tick) begin
                    tx_data = tx_rdata;
                    tx_REN = 1'b1;
                end
                case(parity_mode) 
                    2'b01: next_parity_bit = ~(^tx_rdata); // odd parity
                    2'b10: next_parity_bit = ^tx_rdata; // even parity
                    default: next_parity_bit = parity_bit;
                endcase
            end
            DATA: begin
                if (serial_tick) begin
                    next_tx_bit_count = tx_bit_count + 1;
                    tx_shift_en = 1'b1;
                end
            end
            PARITY: begin
                tx_data[0] = parity_bit;
                tx_load = 1'b1;
                if (serial_tick) begin
                    tx_shift_en = 1'b1;
                end
            end
        endcase
    end

// RX Logic - IDLE is the stop bit state, START is the waiting state
    always_comb begin
        next_rx_state = rx_state;
        case(rx_state)
            IDLE: begin
                if (serial_tick && uart_en && !rx_full && uart_rx == 1'b1) begin
                    next_rx_state = START;
                end
            end
            START: begin
                if (serial_tick && uart_rx == 1'b0) begin
                    next_rx_state = DATA;
                end
            end
            DATA: begin
                if (serial_tick && rx_bit_count == 3'd7) begin
                    next_rx_state = (^parity_mode) ? PARITY : IDLE;
                end
            end
            PARITY: begin
                if (serial_tick) begin
                    next_rx_state = IDLE;
                end
            end
        endcase
    end

    always_comb begin
        next_rx_WEN = 1'b0;
        next_parity_error = parity_error;
        next_frame_error = frame_error;
        next_rx_bit_count = rx_bit_count;
        rx_shift_en = 1'b0;
        rx_active = 1'b1;
        if (clear_frame_error) begin
            next_frame_error = 1'b0;
        end
        if (clear_parity_error) begin
            next_parity_error = 1'b0;
        end
        case(rx_state)
            IDLE: begin
                if (serial_tick && uart_rx == 1'b0 && uart_en && !rx_full) begin
                    next_frame_error = 1'b1;
                end
            end
            START: begin
                rx_active = 1'b0;
            end
            DATA: begin
                if (serial_tick) begin
                    next_rx_bit_count = rx_bit_count + 1;
                    rx_shift_en = 1'b1;
                    if (rx_bit_count == 3'd7) begin
                        next_rx_WEN = 1'b1;
                    end
                end
            end
            PARITY: begin
                if (serial_tick) begin
                    case(parity_mode)
                        2'b01: next_parity_error = (uart_rx ^ (^rx_byte)) ? parity_error : 1'b1;
                        2'b10: next_parity_error = (uart_rx ^ (^rx_byte)) ? 1'b1 : parity_error;
                        default: next_parity_error = parity_error;
                    endcase
                end
            end
        endcase
    end

    assign uart_rts = (flow_control_en) ? ~rx_full : 1'b0;

endmodule