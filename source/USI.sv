module USI #(
    parameter unsigned FIFO_SIZE = 256,
    parameter int CLKDIV_BITS = 16
)(
    bus_protocol_if.peripheral_vital bpif,
    input logic CLK,
    input logic nRST,
    input logic uart_rx,
    output logic uart_tx,
    input logic uart_cts,
    output logic uart_rts,
    input logic spi_miso,
    output logic spi_mosi,
    output logic spi_sclk,
    output logic spi_cs,
    inout wire i2c_sda,
    inout wire i2c_scl
);
    import usi_datapath_pkg::*;
    logic [2:0] mode_sel, uart_config;
    usi_mode_t active_mode;
    logic [CLKDIV_BITS-1:0] clkdiv;
    logic [31:0] tx_wdata, rx_rdata;
    logic [2:0] rx_read_valid_bytes;
    logic [$clog2(FIFO_SIZE+1)-1:0] tx_count, rx_count, fifo_tx_start;
    logic tx_full, tx_empty, rx_full, rx_empty;
    logic tx_wen, rx_ren, tx_flush, rx_flush, error_clear, done_clear, abort;
    logic split_apply, split_ready, fifo_error;
    logic uart_busy, uart_frame_done, uart_parity_error, uart_frame_error, uart_overrun;
    logic protocol_busy, protocol_done, protocol_error, rx_bit;
    dp_cmd_t uart_dp_cmd;
    dp_status_t dp_status;

    logic [7:0] unused_spi_config, unused_i2c_config;
    logic [6:0] unused_i2c_addr;
    logic [5:0] unused_spi_length;
    logic [31:0] unused_transfer_count;
    logic unused_start, unused_spi_miso;
    assign unused_spi_miso = spi_miso;

    register_map #(
        .FIFO_SIZE(FIFO_SIZE),
        .CLKDIV_BITS(CLKDIV_BITS),
        .SUPPORTED_MODES(8'b0000_0011)
    ) reg_map (
        .bpif(bpif),
        .CLK(CLK), .nRST(nRST),
        .tx_full(tx_full), .tx_empty(tx_empty),
        .rx_full(rx_full), .rx_empty(rx_empty),
        .tx_count(tx_count), .rx_count(rx_count),
        .rx_rdata(rx_rdata), .rx_read_valid_bytes(rx_read_valid_bytes),
        .protocol_busy(protocol_busy), .protocol_done(protocol_done),
        .protocol_error(protocol_error),
        .split_ready(split_ready), .fifo_tx_start(fifo_tx_start), .split_apply(split_apply),
        .mode_sel(mode_sel), .clkdiv(clkdiv), .uart_config(uart_config),
        .tx_wdata(tx_wdata), .tx_wen(tx_wen), .rx_ren(rx_ren),
        .tx_flush(tx_flush), .rx_flush(rx_flush),
        .error_clear(error_clear), .done_clear(done_clear), .abort(abort),
        .spi_config(unused_spi_config), .i2c_config(unused_i2c_config),
        .i2c_addr(unused_i2c_addr), .spi_length(unused_spi_length),
        .transfer_count(unused_transfer_count), .start(unused_start)
    );

    control_unit controller (
        .CLK(CLK), .nRST(nRST), .mode_sel(mode_sel),
        .uart_busy(uart_busy), .spi_busy(1'b0), .i2c_busy(1'b0),
        .active_mode(active_mode), .protocol_busy(protocol_busy)
    );

    usi_datapath #(.FIFO_SIZE(FIFO_SIZE)) datapath (
        .CLK(CLK), .nRST(nRST), .active_mode(active_mode), .dp_clear(abort),
        .uart_dp_cmd(uart_dp_cmd), .spi_dp_cmd('0), .i2c_dp_cmd('0),
        .rx_bit_i(rx_bit), .dp_status(dp_status),
        .tx_wdata(tx_wdata), .tx_wen(tx_wen), .rx_ren(rx_ren),
        .tx_flush(tx_flush), .rx_flush(rx_flush), .error_clear(error_clear),
        .protocol_busy(protocol_busy), .split_apply(split_apply),
        .fifo_tx_start(fifo_tx_start), .split_ready(split_ready),
        .rx_rdata(rx_rdata), .rx_read_valid_bytes(rx_read_valid_bytes),
        .tx_full(tx_full), .tx_empty(tx_empty), .rx_full(rx_full), .rx_empty(rx_empty),
        .fifo_error(fifo_error), .tx_count(tx_count), .rx_count(rx_count)
    );

    uart #(.CLKDIV_BITS(CLKDIV_BITS)) uart_fsm (
        .CLK(CLK), .nRST(nRST),
        .uart_en((active_mode == MODE_UART) && (mode_sel == 3'd1)),
        .abort(abort), .tx_flush(tx_flush), .rx_flush(rx_flush),
        .clkdiv(clkdiv), .uart_config(uart_config),
        .uart_rx(uart_rx), .uart_cts(uart_cts),
        .uart_tx(uart_tx), .uart_rts(uart_rts),
        .error_clear(error_clear),
        .dp_status(dp_status), .dp_cmd(uart_dp_cmd), .rx_bit(rx_bit),
        .busy(uart_busy), .frame_done(uart_frame_done),
        .parity_error(uart_parity_error), .frame_error(uart_frame_error),
        .rx_overrun(uart_overrun)
    );

    always_ff @(posedge CLK or negedge nRST) begin
        if (!nRST)
            protocol_done <= 1'b0;
        else begin
            if (done_clear)
                protocol_done <= 1'b0;
            if (uart_frame_done)
                protocol_done <= 1'b1;
        end
    end
    assign protocol_error = fifo_error || uart_parity_error || uart_frame_error || uart_overrun;

    // SPI/I2C adapters aren't connected so pads inactive
    assign spi_mosi = 1'b0;
    assign spi_sclk = 1'b0;
    assign spi_cs = 1'b1;
    assign i2c_sda = 1'bz;
    assign i2c_scl = 1'bz;
endmodule
