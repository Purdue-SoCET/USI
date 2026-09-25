module register_map #(
    parameter unsigned RX_FIFO_SIZE = 16,
    parameter unsigned TX_FIFO_SIZE = 16,
    parameter int CLKDIV_BITS = 16
)(
    bus_protocol_if.peripheral_vital bpif,
    input logic CLK,
    input logic nRST,

    // FIFO SIGNALS
    input logic tx_full,
    input logic tx_empty,
    input logic rx_full,
    input logic rx_empty,

    // FIFO COUNTS
    input logic [$clog2(TX_FIFO_SIZE+1)-1:0] tx_count,
    input logic [$clog2(RX_FIFO_SIZE+1)-1:0] rx_count,

    input logic [31:0] rx_rdata,

    //PROTOCOL STATUS
    input logic protocol_busy,
    input logic protocol_done,
    input logic protocol_error,
    output logic [2:0] mode_sel,
    output logic [CLKDIV_BITS-1:0] clkdiv,
    output logic [31:0] tx_wdata,
    output logic [7:0] spi_config,
    output logic [7:0] i2c_config,
    output logic [6:0] i2c_addr,
    output logic [5:0] spi_length,

    // number of transactions to transfer for everything except UART
    output logic [31:0] transfer_count,
    
    output logic error_clear,
    output logic done_clear,
    output logic start,
    output logic abort,
    output logic tx_wen,
    output logic rx_ren,
    output logic tx_flush,
    output logic rx_flush
);
    logic [2:0] mode_sel_n;
    logic [CLKDIV_BITS-1:0] clkdiv_n;
    logic [7:0] spi_config_n;
    logic [7:0] i2c_config_n;
    logic [6:0] i2c_addr_n;
    logic [5:0] spi_length_n;
    logic [31:0] transfer_count_n;
    logic strobe_error, write_error, read_error;

    always_ff @(posedge CLK, negedge nRST) begin
        if (~nRST) begin
            mode_sel <= '0;
            clkdiv <= '0;
            spi_config <= '0;
            i2c_config <= '0;
            i2c_addr <= '0;
            spi_length <= 6'd8;
            transfer_count <= '0;
        end
        else begin
            mode_sel <= mode_sel_n;
            clkdiv <= clkdiv_n;
            spi_config <= spi_config_n;
            i2c_config <= i2c_config_n;
            i2c_addr <= i2c_addr_n;
            spi_length <= spi_length_n;
            transfer_count <= transfer_count_n;
        end
    end

    // Write to register map.
    always_comb begin
        write_error = 1'b0;
        mode_sel_n = mode_sel;
        clkdiv_n = clkdiv;
        spi_config_n = spi_config;
        i2c_config_n = i2c_config;
        spi_length_n = spi_length;
        i2c_addr_n = i2c_addr;
        transfer_count_n = transfer_count;
        start = 1'b0;
        abort = 1'b0;
        done_clear = 1'b0;
        error_clear = 1'b0;
        tx_wen = 1'b0;
        tx_flush = 1'b0;
        rx_flush = 1'b0;

        if (bpif.wen && !strobe_error) begin
            case (bpif.addr)
                32'h00: mode_sel_n = bpif.wdata[2:0];
                32'h04: clkdiv_n = bpif.wdata[CLKDIV_BITS-1:0];
                // 0x08: protocol_status, read only.
                // 0x0C: fifo_status, read only.
                32'h10: tx_wen = 1'b1;
                32'h14: {tx_flush, rx_flush} = bpif.wdata[1:0];
                32'h18: start = bpif.wdata[0];
                32'h1C: transfer_count_n = bpif.wdata;
                32'h20: begin
                    if (bpif.wdata[5:0] >= 6'd5 &&
                        bpif.wdata[5:0] <= 6'd32)
                        spi_length_n = bpif.wdata[5:0];
                    else
                        write_error = 1'b1;
                end
                32'h24: spi_config_n = bpif.wdata[7:0];
                32'h28: i2c_config_n = bpif.wdata[7:0];
                32'h2C: i2c_addr_n = bpif.wdata[6:0];
                32'h30: {error_clear, done_clear} = bpif.wdata[2:1];
                // 0x34: rx_count, read only.
                // 0x38: tx_count, read only.
                32'h3C: abort = bpif.wdata[0];
                default: write_error = 1'b1;
            endcase
        end
    end

    // Read from register map.
    always_comb begin
        bpif.rdata = 32'b0;
        read_error = 1'b0;
        rx_ren = 1'b0;

        if (bpif.ren && !strobe_error) begin
            case (bpif.addr)
                32'h00: bpif.rdata[2:0] = mode_sel;
                32'h04: bpif.rdata[CLKDIV_BITS-1:0] = clkdiv;
                32'h08: bpif.rdata[2:0] =
                    {protocol_error, protocol_done, protocol_busy};
                32'h0C: bpif.rdata[3:0] =
                    {tx_full, tx_empty, rx_full, rx_empty};
                32'h10: begin
                    bpif.rdata = rx_rdata;
                    rx_ren = 1'b1;
                end
                // 0x14: buffer_flush, write only.
                // 0x18: start, write only.
                32'h1C: bpif.rdata = transfer_count;
                32'h20: bpif.rdata[5:0] = spi_length;
                32'h24: bpif.rdata[7:0] = spi_config;
                32'h28: bpif.rdata[7:0] = i2c_config;
                32'h2C: bpif.rdata[6:0] = i2c_addr;
                // 0x30: status_clear, write only.
                32'h34: bpif.rdata[$clog2(RX_FIFO_SIZE+1)-1:0] = rx_count;
                32'h38: bpif.rdata[$clog2(TX_FIFO_SIZE+1)-1:0] = tx_count;
                // 0x3C: abort, write only.
                default: read_error = 1'b1;
            endcase
        end
    end

    assign tx_wdata = bpif.wdata;
    assign strobe_error = (bpif.strobe == 4'b1111) ? 1'b0 : 1'b1;
    assign bpif.error = strobe_error || write_error || read_error;
    assign bpif.request_stall = 1'b0;
endmodule
