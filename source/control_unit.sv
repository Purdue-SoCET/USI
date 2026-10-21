module control_unit (
    input logic CLK,
    input logic nRST,
    input logic [2:0] mode_sel,
    input logic uart_busy,
    input logic spi_busy,
    input logic i2c_busy,
    output usi_datapath_pkg::usi_mode_t active_mode,
    output logic protocol_busy
);
    import usi_datapath_pkg::*;

    always_comb begin
        protocol_busy = 1'b0;
        case (active_mode)
            MODE_UART: protocol_busy = uart_busy;
            MODE_SPI: protocol_busy = spi_busy;
            MODE_I2C: protocol_busy = i2c_busy;
            default: ;
        endcase
    end

    always_ff @(posedge CLK or negedge nRST) begin
        if (!nRST)
            active_mode <= MODE_IDLE;
        else if (!protocol_busy) begin
            case (mode_sel)
                MODE_IDLE, MODE_UART, MODE_SPI, MODE_I2C:
                    active_mode <= usi_mode_t'(mode_sel);
                default: active_mode <= MODE_IDLE;
            endcase
        end
    end
endmodule
