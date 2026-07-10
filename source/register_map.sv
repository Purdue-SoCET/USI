module register_map #(
    parameter unsigned RX_FIFO_SIZE = 16,
    parameter unsigned TX_FIFO_SIZE = 16
)(
    bus_protocol_if.peripheral_vital bpif,
    input logic CLK,
    input logic nRST,
    input logic tx_overrun,
    input logic tx_underrun,
    input logic rx_overrun,
    input logic rx_underrun,
    input logic tx_full,
    input logic tx_empty,
    input logic rx_full,
    input logic rx_empty,
    input logic [$clog2(TX_FIFO_SIZE+1)-1:0] tx_count,
    input logic [$clog2(RX_FIFO_SIZE+1)-1:0] rx_count,
    input logic [31:0] rx_rdata,
    output logic [1:0] mode_sel,
    output logic [31:0] clkdiv,
    output logic [31:0] tx_wdata,
    output logic [7:0] uart_config,
    output logic [7:0] spi_config,
    output logic i2c_config,
    output logic [9:0] i2c_addr,
    output logic [31:0] i2c_t_low,
    output logic [31:0] i2c_t_high,
    output logic tx_WEN,
    output logic rx_REN,
    output logic tx_clear_overrun,
    output logic tx_clear_underrun,
    output logic rx_clear_overrun,
    output logic rx_clear_underrun,
    output logic tx_flush,
    output logic rx_flush
);
    logic [1:0] next_mode_sel;
    logic [31:0] next_clkdiv;
    logic [7:0] next_uart_config;
    logic [7:0] next_spi_config;
    logic next_i2c_config;
    logic [9:0] next_i2c_addr;
    logic [31:0] next_i2c_t_low;
    logic [31:0] next_i2c_t_high;
    logic strobe_error, write_error, read_error;

    always_ff @(posedge CLK, negedge nRST) begin
        if (~nRST) begin
            mode_sel <= '0;
            clkdiv <= '0;
            uart_config <= '0;
            spi_config <= '0;
            i2c_config <= '0;
            i2c_addr <= '0;
            i2c_t_low <= '0;
            i2c_t_high <= '0;
        end
        else begin
            mode_sel <= next_mode_sel;
            clkdiv <= next_clkdiv;
            uart_config <= next_uart_config;
            spi_config <= next_spi_config;
            i2c_config <= next_i2c_config;
            i2c_addr <= next_i2c_addr;
            i2c_t_low <= next_i2c_t_low;
            i2c_t_high <= next_i2c_t_high;
        end
    end

// Write to register map
    always_comb begin
        write_error = 1'b0;
        next_mode_sel = mode_sel;
        next_clkdiv = clkdiv;
        {rx_clear_underrun, rx_clear_overrun, tx_clear_underrun, tx_clear_overrun} = 4'b0;
        next_uart_config = uart_config;
        next_spi_config = spi_config;
        next_i2c_config = i2c_config;
        next_i2c_addr = i2c_addr;
        next_i2c_t_low = i2c_t_low;
        next_i2c_t_high = i2c_t_high;
        tx_WEN = 1'b0;
        {rx_flush, tx_flush} = 2'b0;
        if (bpif.wen && !strobe_error) begin
            case (bpif.addr)
                32'h00: next_mode_sel = bpif.wdata[1:0];
                32'h04: next_clkdiv = bpif.wdata;
                32'h08: {rx_clear_underrun, rx_clear_overrun, tx_clear_underrun, tx_clear_overrun} = bpif.wdata[3:0];
                32'h0C: next_uart_config = bpif.wdata[7:0];
                32'h10: next_spi_config = bpif.wdata[7:0];
                32'h14: next_i2c_config = bpif.wdata[0];
                32'h18: next_i2c_addr = bpif.wdata[9:0];
                32'h1C: next_i2c_t_low = bpif.wdata;
                32'h20: next_i2c_t_high = bpif.wdata;
                32'h24: tx_WEN = 1'b1;
                32'h28: {rx_flush, tx_flush} = bpif.wdata[1:0];
                // 32'h2C: read only
                // 32'h30: read only
                default: write_error = 1'b1;
            endcase
        end
    end

// Read from register map
    always_comb begin
        bpif.rdata = 32'b0;
        read_error = 1'b0;
        rx_REN = 1'b0;
        if (bpif.ren && !strobe_error) begin
            case (bpif.addr)
                32'h00: bpif.rdata = {30'b0, mode_sel};
                32'h04: bpif.rdata = clkdiv;
                32'h08: bpif.rdata = {24'b0, rx_empty, rx_full, tx_empty, tx_full, rx_underrun, rx_overrun, tx_underrun, tx_overrun};
                32'h0C: bpif.rdata = {24'b0, uart_config};
                32'h10: bpif.rdata = {24'b0, spi_config};
                32'h14: bpif.rdata = {31'b0, i2c_config};
                32'h18: bpif.rdata = {22'b0, i2c_addr};
                32'h1C: bpif.rdata = i2c_t_low;
                32'h20: bpif.rdata = i2c_t_high;
                32'h24: begin
                    bpif.rdata = rx_rdata;
                    rx_REN = 1'b1;
                end
                // 32'h28: write only
                32'h2C: bpif.rdata[$clog2(TX_FIFO_SIZE+1)-1:0] = tx_count;
                32'h30: bpif.rdata[$clog2(RX_FIFO_SIZE+1)-1:0] = rx_count;
                default: read_error = 1'b1;
            endcase
        end
    end

    assign tx_wdata = bpif.wdata;
    assign strobe_error = (bpif.strobe == 4'b1111) ? 1'b0 : 1'b1;
    assign bpif.error = (strobe_error || write_error || read_error);
    assign bpif.request_stall = 1'b0;

endmodule
