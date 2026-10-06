timescale 1ns/1ps

module usi_datapath_tb;
    import usi_datapath_pkg::*;
    localparam logic [7:0] UART_BYTE = 8'h11;
    localparam logic [7:0] SPI_TX_BYTE = 8'hA5;
    localparam logic [7:0] SPI_RX_BYTE = 8'hD3;

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
    logic [31:0] rx_rdata;
    logic [2:0] rx_read_valid_bytes;
    logic tx_flush = 1'b0;
    logic rx_flush = 1'b0;
    logic error_clear = 1'b0;
    logic tx_full, tx_empty, rx_full, rx_empty;
    logic fifo_error;
    logic [3:0] tx_count;
    logic [2:0] rx_count;

    usi_datapath #(.TX_FIFO_SIZE(8), .RX_FIFO_SIZE(4)) dut (.*);

    task automatic tick;
        #1 CLK = 1'b1;
        #1 CLK = 1'b0;
        #1;
    endtask

    task automatic drive_command(input dp_cmd_t command);
        case (active_mode)
            MODE_UART: uart_dp_cmd = command;
            MODE_SPI: spi_dp_cmd = command;
            MODE_I2C: i2c_dp_cmd = command;
            default: begin 
                uart_dp_cmd = command;
                spi_dp_cmd = command;
                i2c_dp_cmd = command;
            end
        endcase
    endtask

    task automatic reset_dut(input usi_mode_t mode);
        uart_dp_cmd = '0;
        spi_dp_cmd = '0;
        i2c_dp_cmd = '0;
        tx_wen = 1'b0;
        rx_ren = 1'b0;
        tx_flush = 1'b0;
        rx_flush = 1'b0;
        dp_clear = 1'b0;
        error_clear = 1'b0;
        active_mode = MODE_IDLE;
        nRST = 1'b0;
        tick();
        nRST = 1'b1;
        tick();
        active_mode = mode;
        tick();
        expect_true(tx_empty && rx_empty && !fifo_error && !dp_status.tx_active && !dp_status.rx_active && !dp_status.rx_byte_valid, "reset clears datapath and FIFO state");
    endtask

endmodule
