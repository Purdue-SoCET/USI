`timescale 1ns/1ps
module usi_bus_exerciser #(
    parameter int unsigned UART_DIVISOR = 868,
    parameter int unsigned BUS_TIMEOUT_CYCLES = 1024
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

    typedef enum logic [4:0] {
        WRITE_DIVISOR, WRITE_CONFIG, WRITE_MODE,
        MODE_WAIT1, MODE_WAIT2,
        READ_DIVISOR, READ_CONFIG, READ_MODE,
        BANNER_SPACE, WRITE_BANNER,
        READ_STATUS, READ_RX_COUNT, ECHO_SPACE, READ_RX_DATA, WRITE_ECHO,
        GAP, FAILED
    } state_t;

    state_t state, resume_state;
    logic initialized;
    logic [31:0] echo_word;
    logic [TIMEOUT_BITS-1:0] stalled_cycles;

    generate
        if (UART_DIVISOR < 8 || UART_DIVISOR > 65535) begin : INVALID_DIVISOR
            $error("%m: UART_DIVISOR must fit the 16-bit divisor and be at least eight");
        end
        if (BUS_TIMEOUT_CYCLES < 1) begin : INVALID_TIMEOUT
            $error("%m: BUS_TIMEOUT_CYCLES must be at least one");
        end
    endgenerate

    assign fault = (state == FAILED);
    assign ready = initialized && !fault && nRST;
    assign bus_strobe = 4'hF;

    always_comb begin
        bus_addr = '0;
        bus_wdata = '0;
        bus_wen = 1'b0;
        bus_ren = 1'b0;

        if (nRST) begin
            case (state)
                WRITE_DIVISOR: begin
                    bus_addr = 32'h04;
                    bus_wdata = UART_DIVISOR;
                    bus_wen = 1'b1;
                end
                WRITE_CONFIG: begin
                    bus_addr = 32'h40;
                    bus_wen = 1'b1;
                end
                WRITE_MODE: begin
                    bus_addr = 32'h00;
                    bus_wdata = 32'd1;
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
                default: ;
            endcase
        end
    end

    always_ff @(posedge CLK or negedge nRST) begin
        if (!nRST) begin
            state <= WRITE_DIVISOR;
            resume_state <= WRITE_DIVISOR;
            initialized <= 1'b0;
            echo_word <= '0;
            stalled_cycles <= '0;
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
                        WRITE_DIVISOR: resume_state <= WRITE_CONFIG;
                        WRITE_CONFIG: resume_state <= WRITE_MODE;
                        WRITE_MODE: resume_state <= MODE_WAIT1;
                        READ_DIVISOR: begin
                            if (bus_rdata != UART_DIVISOR)
                                state <= FAILED;
                            else
                                resume_state <= READ_CONFIG;
                        end
                        READ_CONFIG: begin
                            if (bus_rdata != 32'd0)
                                state <= FAILED;
                            else
                                resume_state <= READ_MODE;
                        end
                        READ_MODE: begin
                            if (bus_rdata != 32'd1) begin
                                state <= FAILED;
                            end else begin
                                initialized <= 1'b1;
                                resume_state <= BANNER_SPACE;
                            end
                        end
                        BANNER_SPACE: resume_state <=
                            bus_rdata[3] ? BANNER_SPACE : WRITE_BANNER;
                        WRITE_BANNER: resume_state <= READ_STATUS;
                        READ_STATUS: begin
                            if (bus_rdata[2])
                                state <= FAILED;
                            else
                                resume_state <= READ_RX_COUNT;
                        end
                        READ_RX_COUNT: resume_state <=
                            (bus_rdata >= 32'd4) ? ECHO_SPACE : READ_STATUS;
                        ECHO_SPACE: resume_state <=
                            bus_rdata[3] ? READ_STATUS : READ_RX_DATA;
                        READ_RX_DATA: begin
                            echo_word <= bus_rdata;
                            resume_state <= WRITE_ECHO;
                        end
                        WRITE_ECHO: resume_state <= READ_STATUS;
                        default: state <= FAILED;
                    endcase
                end
            end
        end else begin
            stalled_cycles <= '0;
            case (state)
                GAP: state <= resume_state;
                MODE_WAIT1: state <= MODE_WAIT2;
                MODE_WAIT2: state <= READ_DIVISOR;
                FAILED: ;
                default: state <= FAILED;
            endcase
        end
    end
endmodule
