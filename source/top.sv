<<<<<<< HEAD
module top(
    input logic CLK, nRST,
    bus_protocol_if.peripheral_vital bpif,
    input logic load,
    input logic send,
    input logic [7:0] data_in,
    input logic rx_line,
    input logic spi_miso,
    output logic tx_out,
    output logic spi_mosi,
    output logic serial_clk,
    output logic [3:0] spi_cs_n,
    output logic [7:0] data_out,
    output logic [7:0] buffer_occupancy
);

    logic [1:0]  mode_sel;
    logic [31:0] clkdiv;
    logic [31:0] configuration;
    logic [31:0] tx_data;
    logic [31:0] error_reg;

    logic ctrl_unit_error;
    logic [31:0] buffer_read;

    logic push, pop;

    logic uart_en, spi_en, i2c_en;
    logic done;
    logic usi_busy;

    logic [7:0] spi_data_out;
    logic [7:0] i2c_data_out;
    logic [7:0] uart_rx_data_out;

    logic push_rx_fifo;
=======
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
>>>>>>> bd284691b7b8c9fd2f5848a815d7c6a2155b8d04

            if (state == LATCH)
                latched_mode <= mode;
        end
    end

<<<<<<< HEAD
    reg_map REG_MAP (
        .bpif(bpif),
        .CLK(CLK),
        .nRST(nRST),
        .ctrl_unit_error(ctrl_unit_error),
        .buffer_read(buffer_read),
        .mode_sel(mode_sel),
        .clkdiv(clkdiv),
        .configuration(configuration),
        .tx_data(tx_data),
        .error_reg(error_reg),
        .push(push),
        .pop(pop)
    );

    data_buffer DATA_BUFFER (
        .CLK(CLK),
        .nRST(nRST),
        .mode_sel(mode_sel),
        .data_in(data_in),
        .buffer_write(bpif.wdata),
        .push(push),
        .pop(pop),
        .clear(1'b0),
        .load(load),
        .send(send),
        .data_out(data_out),
        .buffer_read(buffer_read),
        .buffer_occupancy(buffer_occupancy)
    );

    control_unit CONTROL_UNIT (
        .clk(CLK),
        .n_rst(nRST),
        .enable(send),
        .mode_sel(mode_sel),
        .done(done),
        .uart_en(uart_en),
        .spi_en(spi_en),
        .i2c_en(i2c_en),
        .usi_busy(usi_busy)
    );

    spi_ctrl SPI_INST (
        .clk(CLK),
        .n_rst(nRST),
        .spi_en(spi_en),
        .tx_data(tx_data[7:0]),
        .miso(spi_miso),
        .mosi(spi_mosi),
        .sclk(serial_clk),
        .cs_n(spi_cs_n),
        .data_out(spi_data_out),
        .done(done)
    );

    i2c_ctrl I2C_INST (
        .clk(CLK),
        .n_rst(nRST),
        .i2c_en(i2c_en),
        .tx_data(tx_data[7:0]),
        .data_out(i2c_data_out),
        .done(done)
    );

    uart_tx_fsm_8n1 UART_TX_INST (
        .clk(CLK),
        .n_rst(nRST),
        .tx_enable(uart_en),
        .tx_data(tx_data[7:0]),
        .tx_out(tx_out),
        .done(done)
    );

    uart_rx_fsm_8n1 UART_RX_INST (
        .clk(CLK),
        .n_rst(nRST),
        .rx_enable(uart_en),
        .rx_line(rx_line),
        .rx_byte_out(uart_rx_data_out),
        .push_rx_fifo(push_rx_fifo)
    );

endmodule

=======
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
>>>>>>> bd284691b7b8c9fd2f5848a815d7c6a2155b8d04
