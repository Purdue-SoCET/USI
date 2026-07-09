module register_map (
    bus_protocol_if.peripheral_vital bpif,
    input logic CLK,
    input logic nRST,
    // input status/error signals
    input logic [31:0] rx_rdata,
    output logic [1:0] mode_sel,
    output logic [31:0] clkdiv,
    output logic [31:0] tx_wdata,
    output logic [7:0] uart_config,
    output logic [7:0] spi_config,
    output logic i2c_config,
    output logic [9:0] i2c_addr,
    output logic tx_WEN,
    output logic rx_REN
    // output fifo clear and flush signals
);
    logic [1:0] next_mode_sel;
    logic [31:0] next_clkdiv;
    logic [7:0] next_uart_config;
    logic [7:0] next_spi_config;
    logic next_i2c_config;
    logic [9:0] next_i2c_addr;
    logic strobe_error, write_error, read_error;

    always_ff @(posedge CLK, negedge nRST) begin
        if (~nRST) begin
            mode_sel <= '0;
            clkdiv <= '0;
            uart_config <= '0;
            spi_config <= '0;
            i2c_config <= '0;
            i2c_addr <= '0;
        end
        else begin
            mode_sel <= next_mode_sel;
            clkdiv <= next_clkdiv;
            uart_config <= next_uart_config;
            spi_config <= next_spi_config;
            i2c_config <= next_i2c_config;
            i2c_addr <= next_i2c_addr;
        end
    end

// Write to register map
    always_comb begin
        write_error = 1'b0;
        next_mode_sel = mode_sel;
        next_clkdiv = clkdiv;
        next_uart_config = uart_config;
        next_spi_config = spi_config;
        next_i2c_config = i2c_config;
        next_i2c_addr = i2c_addr;
        tx_WEN = 1'b0;
        if (bpif.wen && !strobe_error) begin
            case (bpif.addr)
                32'h00: next_mode_sel = bpif.wdata[1:0];
                32'h04: next_clkdiv = bpif.wdata;
                // 32'h08: 
                32'h0C: next_uart_config = bpif.wdata[7:0];
                32'h10: next_spi_config = bpif.wdata[7:0];
                32'h14: next_i2c_config = bpif.wdata[0];
                32'h18: next_i2c_addr = bpif.wdata[9:0];
                32'h1C: tx_WEN = 1'b1;
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
                // 32'h08: rdata = status signals
                32'h0C: bpif.rdata = {24'b0, uart_config};
                32'h10: bpif.rdata = {24'b0, spi_config};
                32'h14: bpif.rdata = {31'b0, i2c_config};
                32'h18: bpif.rdata = {22'b0, i2c_addr};
                32'h1C: begin
                    bpif.rdata = rx_rdata;
                    rx_REN = 1'b1;
                end
                default: read_error = 1'b1;
            endcase
        end
    end

    assign tx_wdata = bpif.wdata;
    assign strobe_error = (bpif.strobe == 4'b1111) ? 1'b0 : 1'b1;
    assign bpif.error = (strobe_error || write_error || read_error);
    assign bpif.request_stall = 1'b0;

endmodule
