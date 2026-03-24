module top (
    input  logic       clk,
    input  logic       n_rst,
    input  logic       enable,
    input  logic       tx_req,
    input  logic       rx_activity,
    input  logic [1:0] mode,
    input  logic       uart_done,
    input  logic       uart_err,
    input  logic       i2c_done,
    input  logic       i2c_err,
    input  logic       spi_done,
    input  logic       spi_err,

    output logic       usi_busy,
    output logic       engines_off,
    output logic       latch_mode,
    output logic       uart_en,
    output logic       i2c_en,
    output logic       spi_en
);

    typedef enum logic [2:0] {
        IDLE,
        LATCH,
        UART_ENGINE,
        I2C_ENGINE,
        SPI_ENGINE,
        RETURN_IDLE
    } state_t;

    state_t state, next_state;

    logic [1:0] latched_mode;

    // ---------------------------
    // State register
    // ---------------------------
    always_ff @(posedge clk or negedge n_rst) begin
        if (!n_rst) begin
            state <= IDLE;
            latched_mode <= 2'b00;
        end else begin
            state <= next_state;

            if (state == LATCH)
                latched_mode <= mode;
        end
    end

    // ---------------------------
    // Next-state logic
    // ---------------------------
    always_comb begin
        next_state = state;

        case (state)
            IDLE: begin
                if (enable && (tx_req || rx_activity))
                    next_state = LATCH;
            end

            LATCH: begin
                case (mode)
                    2'b00: next_state = UART_ENGINE;
                    2'b01: next_state = SPI_ENGINE;
                    2'b10: next_state = I2C_ENGINE;
                    default: next_state = RETURN_IDLE;
                endcase
            end

            UART_ENGINE: begin
                if (uart_done || uart_err)
                    next_state = RETURN_IDLE;
            end

            SPI_ENGINE: begin
                if (spi_done || spi_err)
                    next_state = RETURN_IDLE;
            end

            I2C_ENGINE: begin
                if (i2c_done || i2c_err)
                    next_state = RETURN_IDLE;
            end

            RETURN_IDLE: begin
                next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    // ---------------------------
    // Output logic
    // ---------------------------
    always_comb begin
        // defaults
        usi_busy    = 1'b0;
        engines_off = 1'b0;
        latch_mode  = 1'b0;
        uart_en     = 1'b0;
        i2c_en      = 1'b0;
        spi_en      = 1'b0;

        case (state)
            IDLE: begin
                engines_off = 1'b1;
            end

            LATCH: begin
                latch_mode = 1'b1;
                usi_busy   = 1'b1;
            end

            UART_ENGINE: begin
                usi_busy = 1'b1;
                uart_en  = 1'b1;
            end

            SPI_ENGINE: begin
                usi_busy = 1'b1;
                spi_en   = 1'b1;
            end

            I2C_ENGINE: begin
                usi_busy = 1'b1;
                i2c_en   = 1'b1;
            end

            RETURN_IDLE: begin
                usi_busy = 1'b0;
            end

            default: begin
                engines_off = 1'b1;
            end
        endcase
    end

endmodule