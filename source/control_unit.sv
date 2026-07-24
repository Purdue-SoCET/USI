module control_unit (
    input logic CLK,
    input logic nRST,
    input logic [1:0] mode_sel,

    input logic uart_tx_load,
    input logic [7:0] uart_tx_data,
    input logic uart_tx_shift_en,
    input logic uart_tx_REN,
    input logic uart_rx_shift_en,
    input logic uart_rx_WEN,
    input logic uart_tx_active,
    input logic uart_rx_active,

    input logic spi_active,

    input logic i2c_active,

    output logic [1:0] mode_active,
    output logic clkdiv_en,
    output logic tx_parallel_load,
    output logic [7:0] tx_parallel_in,
    output logic tx_shift_en,
    output logic tx_shift_in,
    output logic tx_REN,
    output logic msb_first,
    output logic rx_shift_en,
    output logic rx_WEN
);

    typedef enum logic [1:0] {
        IDLE, UART, SPI, I2C
    } state_t;

    state_t curr_state, next_state;

    always_ff @(posedge CLK, negedge nRST) begin
        if (~nRST) begin
            curr_state <= IDLE;
        end
        else begin
            curr_state <= next_state;
        end
    end

    always_comb begin
        next_state = curr_state;
        case (curr_state)
            IDLE: begin
                next_state = state_t'(mode_sel);
            end
            UART: begin
                if (!uart_rx_active && !uart_tx_active) begin
                    next_state = state_t'(mode_sel);
                end
            end
            SPI: begin
                if (!spi_active) begin
                    next_state = state_t'(mode_sel);
                end
            end
            I2C: begin
                if (!i2c_active) begin
                    next_state = state_t'(mode_sel);
                end
            end
        endcase
    end

    always_comb begin
        tx_parallel_load    = 1'b0;
        tx_parallel_in      = 8'b0;
        tx_shift_en         = 1'b0;
        tx_shift_in         = 1'b0;
        tx_REN              = 1'b0;
        msb_first           = 1'b0;
        rx_shift_en         = 1'b0;
        rx_WEN              = 1'b0;
        clkdiv_en           = 1'b1;
        case (curr_state)
            IDLE: begin
                clkdiv_en = 1'b0;
            end
            UART: begin
                tx_parallel_load    = uart_tx_load;
                tx_parallel_in      = uart_tx_data;
                tx_shift_en         = uart_tx_shift_en;
                tx_shift_in         = 1'b1;
                tx_REN              = uart_tx_REN;
                msb_first           = 1'b0;
                rx_shift_en         = uart_rx_shift_en;
                rx_WEN              = uart_rx_WEN;
            end
            SPI: begin
                
            end
            I2C: begin
                
            end
        endcase
    end

    assign mode_active = curr_state;

endmodule