`timescale 1ns/1ps

// SPI master: Mode 0, 8 bits, MSB first, one byte per start.
// Direct FIFO/shift-register interface; no usi_datapath_pkg dependency.
// sclk_tick: synchronous enable once per SCLK half period.
// Pulse start for one CLK while idle, TX is nonempty, and RX has space.
// Keep ticks running until done. spi_en only gates new transfers.
// RX space must remain available: this SPI is the only RX FIFO writer.
module spi_ctrl (
    input logic CLK,
    input logic nRST,
    input logic spi_en,
    input logic start,
    input logic sclk_tick,
    input logic tx_empty,
    input logic rx_full,
    input logic [7:0] tx_rdata,

    output logic tx_load,
    output logic [7:0] tx_data,
    output logic tx_shift_en,
    output logic tx_REN,
    output logic rx_shift_en,
    output logic rx_WEN,
    output logic serial_clk,
    output logic spi_cs_n,
    output logic msb_first,
    output logic busy,
    output logic done
);
    typedef enum logic [2:0] {
        IDLE, LOAD, TRANSFER, CS_HOLD, DONE
    } spi_state_t;

    spi_state_t spi_state, next_spi_state;
    logic [2:0] bit_count, next_bit_count;
    logic [7:0] tx_latched, next_tx_latched;
    logic next_serial_clk;

    always_ff @(posedge CLK, negedge nRST) begin
        if (~nRST) begin
            spi_state <= IDLE;
            bit_count <= 3'b0;
            tx_latched <= 8'b0;
            serial_clk <= 1'b0;
        end
        else begin
            spi_state <= next_spi_state;
            bit_count <= next_bit_count;
            tx_latched <= next_tx_latched;
            serial_clk <= next_serial_clk;
        end
    end

// SPI Logic
    always_comb begin : SPI_State_Transitions
        next_spi_state = spi_state;
        case(spi_state)
            IDLE: begin
                if (spi_en && start && !tx_empty && !rx_full) begin
                    next_spi_state = LOAD;
                end
            end
            LOAD: begin
                next_spi_state = TRANSFER;
            end
            TRANSFER: begin
                // Complete the eighth falling edge before ending the frame.
                if (sclk_tick && serial_clk && bit_count == 3'd7) begin
                    next_spi_state = CS_HOLD;
                end
            end
            CS_HOLD: begin
                if (sclk_tick) begin
                    next_spi_state = DONE;
                end
            end
            DONE: begin
                next_spi_state = IDLE;
            end
            default: begin
                next_spi_state = IDLE;
            end
        endcase
    end

    always_comb begin : SPI_Outputs
        next_bit_count = bit_count;
        next_tx_latched = tx_latched;
        next_serial_clk = serial_clk;
        tx_data = tx_latched;
        tx_load = 1'b0;
        tx_shift_en = 1'b0;
        tx_REN = 1'b0;
        rx_shift_en = 1'b0;
        rx_WEN = 1'b0;
        spi_cs_n = 1'b1;
        msb_first = 1'b1;
        busy = 1'b0;
        done = 1'b0;

        case(spi_state)
            IDLE: begin
                next_bit_count = 3'b0;
                next_serial_clk = 1'b0;
                if (spi_en && start && !tx_empty && !rx_full) begin
                    // Latch the FIFO head on the same edge that pops it.
                    next_tx_latched = tx_rdata;
                    tx_REN = 1'b1;
                end
            end
            LOAD: begin
                busy = 1'b1;
                spi_cs_n = 1'b0;
                tx_load = 1'b1;
            end
            TRANSFER: begin
                busy = 1'b1;
                spi_cs_n = 1'b0;
                if (sclk_tick) begin
                    next_serial_clk = ~serial_clk;
                    if (!serial_clk) begin
                        // Mode 0: sample MISO at the rising SCLK edge.
                        rx_shift_en = 1'b1;
                    end
                    else if (bit_count != 3'd7) begin
                        // Prepare the next MOSI bit at the falling edge.
                        tx_shift_en = 1'b1;
                        next_bit_count = bit_count + 3'd1;
                    end
                end
            end
            CS_HOLD: begin
                busy = 1'b1;
                spi_cs_n = 1'b0;
                next_serial_clk = 1'b0;
            end
            DONE: begin
                // RX shift register already holds all eight received bits.
                // FIFO accepts that byte at the edge leaving DONE.
                rx_WEN = 1'b1;
                done = 1'b1;
            end
            default: begin
                next_bit_count = 3'b0;
                next_serial_clk = 1'b0;
            end
        endcase

        if (!nRST) begin
            tx_load = 1'b0;
            tx_shift_en = 1'b0;
            tx_REN = 1'b0;
            rx_shift_en = 1'b0;
            rx_WEN = 1'b0;
            spi_cs_n = 1'b1;
            busy = 1'b0;
            done = 1'b0;
        end
    end
endmodule
