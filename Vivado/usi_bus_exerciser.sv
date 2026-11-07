// One four-byte SPI exchange per reset.
// Uses this register map's immediate, zero-stall bus responses.
module usi_bus_exerciser #(
    parameter int unsigned SPI_DIVISOR = 100,
    parameter logic [31:0] TX_WORD = 32'h00000000,
    parameter logic [31:0] EXPECTED_RX_WORD = 32'h00001234
) (
    input  logic CLK, nRST,
    output logic [31:0] bus_addr, bus_wdata,
    output logic [3:0] bus_strobe,
    output logic bus_wen, bus_ren,
    input  logic [31:0] bus_rdata,
    input  logic bus_error,
    output logic [31:0] received_word,
    output logic ready, fault
);
    typedef enum logic [3:0] {
        SET_DIVISOR, SET_MODE, LOAD_TX, CLEAR_DONE, START_BYTE,
        WAIT_BYTE, NEXT_BYTE, READ_RX, PASSED, FAILED
    } state_t;
    state_t state, state_n;
    logic [1:0] byte_index, byte_index_n;
    logic [31:0] received_word_n;
    logic bus_gap, running;
    logic [24:0] timeout_count, timeout_count_n;

    assign ready = nRST && (state == PASSED);
    assign fault = nRST && (state == FAILED);
    assign running = (state != PASSED) && (state != FAILED);
    assign bus_strobe = 4'hF;

    always_comb begin
        state_n = state;
        byte_index_n = byte_index;
        received_word_n = received_word;
        timeout_count_n = timeout_count;
        bus_addr = '0;
        bus_wdata = '0;
        bus_wen = 1'b0;
        bus_ren = 1'b0;
        if (running)
            timeout_count_n = timeout_count + 25'd1;

        // Insert one quiet cycle after every bus access.
        if (nRST && !bus_gap) begin
            case (state)
                SET_DIVISOR: begin
                    bus_addr = 32'h04;
                    bus_wdata = SPI_DIVISOR;
                    bus_wen = 1'b1;
                    state_n = SET_MODE;
                end
                SET_MODE: begin
                    bus_addr = 32'h00;
                    bus_wdata = 32'd2;
                    bus_wen = 1'b1;
                    state_n = LOAD_TX;
                end
                LOAD_TX: begin
                    bus_addr = 32'h10;
                    bus_wdata = TX_WORD;
                    bus_wen = 1'b1;
                    state_n = CLEAR_DONE;
                end
                CLEAR_DONE: begin
                    bus_addr = 32'h30;
                    bus_wdata = 32'd6;
                    bus_wen = 1'b1;
                    state_n = START_BYTE;
                end
                START_BYTE: begin
                    bus_addr = 32'h18;
                    bus_wdata = 32'd1;
                    bus_wen = 1'b1;
                    state_n = WAIT_BYTE;
                end
                WAIT_BYTE: begin
                    bus_addr = 32'h08;
                    bus_ren = 1'b1;
                    if (bus_rdata[2])
                        state_n = FAILED;
                    else if (bus_rdata[1] && !bus_rdata[0])
                        state_n = NEXT_BYTE;
                end
                NEXT_BYTE: begin
                    state_n = READ_RX;
                    if (byte_index != 2'd3) begin
                        byte_index_n = byte_index + 2'd1;
                        state_n = CLEAR_DONE;
                    end
                end
                READ_RX: begin
                    bus_addr = 32'h10;
                    bus_ren = 1'b1;
                    received_word_n = bus_rdata;
                    state_n = PASSED;
                    if (bus_rdata != EXPECTED_RX_WORD)
                        state_n = FAILED;
                end
                default: ;
            endcase
        end

        if ((bus_wen || bus_ren) && bus_error)
            state_n = FAILED;
        // One-second deadline at the 25 MHz system clock.
        if (running && timeout_count == 25'd24999999)
            state_n = FAILED;
    end

    always_ff @(posedge CLK or negedge nRST) begin
        if (!nRST) begin
            state <= SET_DIVISOR;
            byte_index <= '0;
            received_word <= '0;
            timeout_count <= '0;
            bus_gap <= 1'b0;
        end else begin
            state <= state_n;
            byte_index <= byte_index_n;
            received_word <= received_word_n;
            timeout_count <= timeout_count_n;
            bus_gap <= bus_wen || bus_ren;
        end
    end
endmodule
