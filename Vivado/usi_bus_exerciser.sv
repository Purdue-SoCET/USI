`timescale 1ns/1ps
module usi_bus_exerciser #(
    parameter int unsigned UART_DIVISOR = 217,
    parameter int unsigned BUS_TIMEOUT_CYCLES = 1024,
    parameter int unsigned TEST_MODE = 1, // 1 = UART banner/echo, 2 = SPI loopback
    parameter int unsigned SPI_DIVISOR = 100
)(
    input  logic CLK,
    input  logic nRST,
    output logic [31:0] bus_addr,
    output logic [31:0] bus_wdata,
    output logic [3:0] bus_strobe,
    output logic bus_wen,
    output logic bus_ren,
    input  logic [31:0] bus_rdata,
    input  logic bus_error,
    input  logic bus_request_stall,
    output logic ready,
    output logic fault
);
    localparam int TIMEOUT_BITS = (BUS_TIMEOUT_CYCLES > 1) ?
        $clog2(BUS_TIMEOUT_CYCLES) : 1;
    localparam int unsigned ACTIVE_DIVISOR = (TEST_MODE == 2) ? SPI_DIVISOR : UART_DIVISOR;
    localparam logic [31:0] SPI_TEST_WORD = 32'h3CA55A96;
    localparam int unsigned SPI_WAIT_CYCLES = 20 * SPI_DIVISOR + 4096;
    localparam int SPI_WAIT_BITS = $clog2(SPI_WAIT_CYCLES + 1);

    typedef enum logic [4:0] {
        WRITE_DIVISOR, WRITE_CONFIG, WRITE_MODE,
        MODE_WAIT1, MODE_WAIT2,
        READ_DIVISOR, READ_CONFIG, READ_MODE,
        BANNER_SPACE, WRITE_BANNER,
        READ_STATUS, READ_RX_COUNT, ECHO_SPACE, READ_RX_DATA, WRITE_ECHO,
        GAP, FAILED,
        CHECK_BANNER_SPACE, CHECK_ECHO_SPACE,
        SPI_WRITE_PATTERN, SPI_CLEAR_DONE, SPI_START_BYTE, SPI_POLL_DONE,
        SPI_NEXT_BYTE, SPI_READ_TX_COUNT, SPI_POLL_RX_COUNT,
        SPI_READ_RX_WORD, SPI_READ_RX_EMPTY, SPI_PASSED
    } state_t;

    state_t state, resume_state;
    logic initialized;
    // Capture FIFO status before using it to choose the next bus operation.
    logic tx_full_read;
    logic [31:0] echo_word;
    logic [TIMEOUT_BITS-1:0] stalled_cycles;
    logic [1:0] spi_byte_index;
    logic [SPI_WAIT_BITS-1:0] spi_wait_count;
    logic spi_polling;

    generate
        if (UART_DIVISOR < 8 || UART_DIVISOR > 65535) begin : INVALID_DIVISOR
            $error("%m: UART_DIVISOR must fit the 16-bit divisor and be at least eight");
        end
        if (BUS_TIMEOUT_CYCLES < 1) begin : INVALID_TIMEOUT
            $error("%m: BUS_TIMEOUT_CYCLES must be at least one");
        end
        if (TEST_MODE != 1 && TEST_MODE != 2) begin : INVALID_TEST_MODE
            $error("%m: TEST_MODE must be 1 (UART) or 2 (SPI loopback)");
        end
        if (SPI_DIVISOR < 8 || SPI_DIVISOR > 65535) begin : INVALID_SPI_DIVISOR
            $error("%m: SPI_DIVISOR must fit 16 bits and be at least eight");
        end
    endgenerate

    assign fault = (state == FAILED);
    // UART ready means initialized; SPI ready means the data comparison passed.
    assign ready = nRST && !fault &&
        ((TEST_MODE == 2) ? (state == SPI_PASSED) : initialized);
    assign bus_strobe = 4'hF;

    // Bound SPI completion and RX-count polling, including intervening gaps.
    assign spi_polling = (TEST_MODE == 2) && (
        state == SPI_POLL_DONE || state == SPI_POLL_RX_COUNT ||
        (state == GAP && (resume_state == SPI_POLL_DONE || resume_state == SPI_POLL_RX_COUNT))
    );

    always_ff @(posedge CLK or negedge nRST) begin
        if (!nRST)
            spi_wait_count <= '0;
        else if (!spi_polling)
            spi_wait_count <= '0;
        else if (spi_wait_count < SPI_WAIT_BITS'(SPI_WAIT_CYCLES - 1))
            spi_wait_count <= spi_wait_count + 1'b1;
    end

    always_comb begin
        bus_addr = '0;
        bus_wdata = '0;
        bus_wen = 1'b0;
        bus_ren = 1'b0;

        if (nRST) begin
            case (state)
                WRITE_DIVISOR: begin
                    bus_addr = 32'h04;
                    bus_wdata = ACTIVE_DIVISOR;
                    bus_wen = 1'b1;
                end
                WRITE_CONFIG: begin
                    bus_addr = 32'h40;
                    bus_wen = 1'b1;
                end
                WRITE_MODE: begin
                    bus_addr = 32'h00;
                    bus_wdata = TEST_MODE;
                    bus_wen = 1'b1;
                end
                READ_DIVISOR: begin
                    bus_addr = 32'h04;
                    bus_ren = 1'b1;
                end
                READ_CONFIG: begin
                    bus_addr = 32'h40;
                    bus_ren = 1'b1;
                end
                READ_MODE: begin
                    bus_addr = 32'h00;
                    bus_ren = 1'b1;
                end
                BANNER_SPACE, ECHO_SPACE: begin
                    bus_addr = 32'h0C;
                    bus_ren = 1'b1;
                end
                WRITE_BANNER: begin
                    bus_addr = 32'h10;
                    bus_wdata = 32'h0A495355;
                    bus_wen = 1'b1;
                end
                READ_STATUS: begin
                    bus_addr = 32'h08;
                    bus_ren = 1'b1;
                end
                READ_RX_COUNT: begin
                    bus_addr = 32'h34;
                    bus_ren = 1'b1;
                end
                READ_RX_DATA: begin
                    bus_addr = 32'h10;
                    bus_ren = 1'b1;
                end
                WRITE_ECHO: begin
                    bus_addr = 32'h10;
                    bus_wdata = echo_word;
                    bus_wen = 1'b1;
                end
                // Current SPI RTL: Mode 0, eight bits, MSB first, one byte/start.
                // Requires MOSI to be connected back to MISO in the top module.
                SPI_WRITE_PATTERN: begin
                    bus_addr = 32'h10;
                    bus_wdata = SPI_TEST_WORD; // bytes 96, 5A, A5, 3C
                    bus_wen = 1'b1;
                end
                SPI_CLEAR_DONE: begin
                    bus_addr = 32'h30;
                    bus_wdata = 32'd6; // clear sticky done and error
                    bus_wen = 1'b1;
                end
                SPI_START_BYTE: begin
                    bus_addr = 32'h18;
                    bus_wdata = 32'd1;
                    bus_wen = 1'b1;
                end
                SPI_POLL_DONE: begin
                    bus_addr = 32'h08;
                    bus_ren = 1'b1;
                end
                SPI_READ_TX_COUNT: begin
                    bus_addr = 32'h38;
                    bus_ren = 1'b1;
                end
                SPI_POLL_RX_COUNT, SPI_READ_RX_EMPTY: begin
                    bus_addr = 32'h34;
                    bus_ren = 1'b1;
                end
                SPI_READ_RX_WORD: begin
                    bus_addr = 32'h10;
                    bus_ren = 1'b1;
                end
                default: ;
            endcase
        end
    end

    always_ff @(posedge CLK or negedge nRST) begin
        if (!nRST) begin
            state <= WRITE_DIVISOR;
            resume_state <= WRITE_DIVISOR;
            initialized <= 1'b0;
            tx_full_read <= 1'b0;
            echo_word <= '0;
            stalled_cycles <= '0;
            spi_byte_index <= '0;
        end else if (spi_polling && spi_wait_count == SPI_WAIT_BITS'(SPI_WAIT_CYCLES - 1)) begin
            state <= FAILED;
        end else if (bus_wen || bus_ren) begin
            if (bus_request_stall) begin
                if (stalled_cycles == TIMEOUT_BITS'(BUS_TIMEOUT_CYCLES - 1)) begin
                    state <= FAILED;
                end else begin
                    stalled_cycles <= stalled_cycles + 1'b1;
                end
            end else begin
                stalled_cycles <= '0;
                if (bus_error) begin
                    state <= FAILED;
                end else begin
                    state <= GAP;
                    case (state)
                        WRITE_DIVISOR: resume_state <= (TEST_MODE == 2) ? WRITE_MODE : WRITE_CONFIG;
                        WRITE_CONFIG: resume_state <= WRITE_MODE;
                        WRITE_MODE: resume_state <= MODE_WAIT1;
                        READ_DIVISOR: begin
                            if (bus_rdata != ACTIVE_DIVISOR)
                                state <= FAILED;
                            else
                                resume_state <= (TEST_MODE == 2) ? READ_MODE : READ_CONFIG;
                        end
                        READ_CONFIG: begin
                            if (bus_rdata != 32'd0)
                                state <= FAILED;
                            else
                                resume_state <= READ_MODE;
                        end
                        READ_MODE: begin
                            if (bus_rdata != TEST_MODE) begin
                                state <= FAILED;
                            end else if (TEST_MODE == 2) begin
                                resume_state <= SPI_WRITE_PATTERN;
                            end else begin
                                initialized <= 1'b1;
                                resume_state <= BANNER_SPACE;
                            end
                        end
                        BANNER_SPACE: begin
                            tx_full_read <= bus_rdata[3];
                            resume_state <= CHECK_BANNER_SPACE;
                        end
                        WRITE_BANNER: resume_state <= READ_STATUS;
                        READ_STATUS: begin
                            if (bus_rdata[2])
                                state <= FAILED;
                            else
                                resume_state <= READ_RX_COUNT;
                        end
                        READ_RX_COUNT: resume_state <=
                            (bus_rdata >= 32'd4) ? ECHO_SPACE : READ_STATUS;
                        ECHO_SPACE: begin
                            tx_full_read <= bus_rdata[3];
                            resume_state <= CHECK_ECHO_SPACE;
                        end
                        READ_RX_DATA: begin
                            echo_word <= bus_rdata;
                            resume_state <= WRITE_ECHO;
                        end
                        WRITE_ECHO: resume_state <= READ_STATUS;
                        SPI_WRITE_PATTERN: resume_state <= SPI_CLEAR_DONE;
                        SPI_CLEAR_DONE: resume_state <= SPI_START_BYTE;
                        SPI_START_BYTE: resume_state <= SPI_POLL_DONE;
                        SPI_POLL_DONE: begin
                            if (bus_rdata[2])
                                state <= FAILED;
                            else if (bus_rdata[1] && !bus_rdata[0])
                                resume_state <= SPI_NEXT_BYTE;
                            else
                                resume_state <= SPI_POLL_DONE;
                        end
                        SPI_READ_TX_COUNT: begin
                            if (bus_rdata != 0)
                                state <= FAILED;
                            else
                                resume_state <= SPI_POLL_RX_COUNT;
                        end
                        SPI_POLL_RX_COUNT: begin
                            if (bus_rdata > 4)
                                state <= FAILED;
                            else if (bus_rdata == 4)
                                resume_state <= SPI_READ_RX_WORD;
                            else
                                resume_state <= SPI_POLL_RX_COUNT;
                        end
                        SPI_READ_RX_WORD: begin
                            if (bus_rdata != SPI_TEST_WORD)
                                state <= FAILED;
                            else
                                resume_state <= SPI_READ_RX_EMPTY;
                        end
                        SPI_READ_RX_EMPTY: begin
                            if (bus_rdata != 0)
                                state <= FAILED;
                            else
                                resume_state <= SPI_PASSED;
                        end
                        default: state <= FAILED;
                    endcase
                end
            end
        end else begin
            stalled_cycles <= '0;
            case (state)
                GAP: state <= resume_state;
                // No bus request is asserted while checking captured status.
                CHECK_BANNER_SPACE: begin
                    if (tx_full_read)
                        state <= BANNER_SPACE;
                    else
                        state <= WRITE_BANNER;
                end
                CHECK_ECHO_SPACE: begin
                    if (tx_full_read)
                        state <= READ_STATUS;
                    else
                        state <= READ_RX_DATA;
                end
                MODE_WAIT1: state <= MODE_WAIT2;
                MODE_WAIT2: state <= READ_DIVISOR;
                SPI_NEXT_BYTE: begin
                    if (spi_byte_index == 3)
                        state <= SPI_READ_TX_COUNT;
                    else begin
                        spi_byte_index <= spi_byte_index + 1'b1;
                        state <= SPI_CLEAR_DONE;
                    end
                end
                SPI_PASSED: ; // latch pass until reset
                FAILED: ;
                default: state <= FAILED;
            endcase
        end
    end
endmodule
