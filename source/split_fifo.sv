`timescale 1ns/1ps

module split_fifo #(
    parameter int unsigned DEPTH_BYTES  = 256,
    parameter int unsigned BUSIF_BYTES = 4, // 32 bits - bus interface bytes
    parameter int unsigned DP_BYTES = 2 // 16 bits - datapath bytes
)(
    input logic clk,
    input logic nRST,

    // TX FIFO, software inputs data
    input logic [BUSIF_BYTES*8-1:0] tx_wdata,
    input logic tx_push,
    input logic tx_pop,
    input logic tx_flush,

    // number of bytes we want to pop
    input logic [$clog2(DP_BYTES+1)-1:0] tx_pop_num_bytes,

    output logic [DP_BYTES*8-1:0] tx_rdata,
    output logic tx_empty,
    output logic tx_full,
    output logic [$clog2(DEPTH_BYTES+1)-1:0] tx_occupancy,

    // RX FIFO, software receives data
    input  logic [DP_BYTES*8-1:0] rx_wdata,
    input  logic rx_push,
    input  logic rx_pop,
    input  logic rx_flush,

    // number of received bytes we want to store
    input logic [$clog2(DP_BYTES+1)-1:0] rx_push_num_bytes,

    output logic [BUSIF_BYTES*8-1:0] rx_rdata,
    output logic rx_empty,
    output logic rx_full,
    output logic rx_space_available, // enough space for requested RX push, without relying on a pop happening this cycle
    output logic [$clog2(DEPTH_BYTES+1)-1:0] rx_occupancy,

    input logic dp_busy,
    input logic split_apply, // signal to tell FIFO to actually apply the configuration split

    // RX starts below this address, TX starts from this address
    input logic [$clog2(DEPTH_BYTES+1)-1:0] fifo_tx_start
);  
    // width for addressing individual bytes
    localparam int ADDR_BITS = $clog2(DEPTH_BYTES);

    // width for split boundary. For 256, this would be 9 bits
    localparam int COUNT_BITS = $clog2(DEPTH_BYTES + 1);

    // just do an equal 50/50 RX TX split on reset
    localparam int RESET_TX_START = DEPTH_BYTES / 2;

    typedef int unsigned uint_t;

    // split fifo storage, index goes from 0...255
    logic [7:0] fifo [0:DEPTH_BYTES-1];
    logic [7:0] fifo_n [0:DEPTH_BYTES-1];

    // check where tx fifo starts
    logic [COUNT_BITS-1:0] tx_start;    
    logic [COUNT_BITS-1:0] tx_start_n;

    // TX read and write ptrs
    logic [ADDR_BITS-1:0] tx_write_ptr, tx_write_ptr_n;
    logic [ADDR_BITS-1:0] tx_read_ptr, tx_read_ptr_n;

    // RX read and write ptrs
    logic [ADDR_BITS-1:0] rx_write_ptr, rx_write_ptr_n;
    logic [ADDR_BITS-1:0] rx_read_ptr, rx_read_ptr_n;


    // Current occupancies already exist as output logic ports.
    logic [COUNT_BITS-1:0] tx_occupancy_n;
    logic [COUNT_BITS-1:0] rx_occupancy_n;

    // determine FIFO capacity
    logic [COUNT_BITS-1:0] tx_capacity;
    logic [COUNT_BITS-1:0] rx_capacity;

    // signals to accept or decline pop
    logic tx_pop_accept;
    logic rx_pop_accept;

    // number of bytes removed by an RX pop
    logic [COUNT_BITS-1:0] rx_pop_num_bytes;

    // how many bytes remain after accepted pops
    logic [COUNT_BITS-1:0] tx_occupancy_after_pop;
    logic [COUNT_BITS-1:0] rx_occupancy_after_pop;

    // how many unused bytes are in the tx and rx regions
    logic [COUNT_BITS-1:0] tx_free_bytes;
    logic [COUNT_BITS-1:0] rx_free_bytes;

    // determine if we can accept a push
    logic tx_push_accept;
    logic rx_push_accept;

    // tracks each byte of tx and rx outputs   
    int unsigned tx_read_addr;
    int unsigned rx_read_addr; 

    always_ff @(posedge clk, negedge nRST) begin
        if(!nRST) begin
            // default 50/50 split
            tx_start <= COUNT_BITS'(RESET_TX_START);

            // TX pointers begin at first address in TX region
            tx_write_ptr <= ADDR_BITS'(RESET_TX_START);
            tx_read_ptr  <= ADDR_BITS'(RESET_TX_START);

            // RX pointer begin at zero
            rx_write_ptr <= '0;
            rx_read_ptr <= '0;

            // occupancy
            tx_occupancy <= '0;
            rx_occupancy <= '0;
        end

        else begin

            tx_start <= tx_start_n;

            tx_write_ptr <= tx_write_ptr_n;
            tx_read_ptr  <= tx_read_ptr_n;

            rx_write_ptr <= rx_write_ptr_n;
            rx_read_ptr  <= rx_read_ptr_n;

            tx_occupancy <= tx_occupancy_n;
            rx_occupancy <= rx_occupancy_n;
        end
    end

    // fifo does nothing on reset so make its own ff block
    always_ff @(posedge clk) begin
    if (nRST)
        fifo <= fifo_n;
    end

    always_comb begin
        // default assertions
        fifo_n = fifo;
        tx_start_n = tx_start;

        tx_write_ptr_n = tx_write_ptr;
        tx_read_ptr_n  = tx_read_ptr;

        rx_write_ptr_n = rx_write_ptr;
        rx_read_ptr_n  = rx_read_ptr;

        tx_occupancy_n = tx_occupancy;
        rx_occupancy_n = rx_occupancy;

        // apply a new split only when idle, empty, and FIFO not being accessed
        if (
            split_apply &&
            !dp_busy &&
            (tx_occupancy == '0) && (rx_occupancy == '0) &&
            !tx_push && !tx_pop && !rx_push && !rx_pop &&
            !tx_flush && !rx_flush &&
            (fifo_tx_start <= COUNT_BITS'(DEPTH_BYTES)) 
        ) begin

            // store boundary
            tx_start_n = fifo_tx_start;

            // rx always start at zero
            rx_write_ptr_n = '0;
            rx_read_ptr_n = '0;

            // if we only want RX FIFO to be enabled
            if(fifo_tx_start == COUNT_BITS'(DEPTH_BYTES)) begin
                tx_write_ptr_n = '0;
                tx_read_ptr_n = '0;
            end

            // if we do want TX FIFO enabled
            else begin
                tx_write_ptr_n = ADDR_BITS'(fifo_tx_start);
                tx_read_ptr_n = ADDR_BITS'(fifo_tx_start);
            end
        end

        // TX Flush
        if(tx_flush) begin
            tx_occupancy_n = '0;

            // if TX disabled, keep it disabled
            if(tx_start == COUNT_BITS'(DEPTH_BYTES)) begin
                tx_write_ptr_n = '0;
                tx_read_ptr_n = '0;
            end

            // if TX not disabled, send read/write ptrs back to tx_start
            else begin
                tx_write_ptr_n = ADDR_BITS'(tx_start);
                tx_read_ptr_n  = ADDR_BITS'(tx_start);
            end
        end
        else begin
            // occupancy after pop, then add accepted push
            tx_occupancy_n =
            tx_occupancy_after_pop +
            (tx_push_accept ? COUNT_BITS'(BUSIF_BYTES) : '0);

            // if tx pop is accepted
            if(tx_pop_accept) begin
                // if we crossed end of memory, wrap back to start of TX region
                if((uint_t'(tx_read_ptr) + uint_t'(tx_pop_num_bytes)) >= DEPTH_BYTES) begin
                    tx_read_ptr_n = ADDR_BITS'(
                        uint_t'(tx_read_ptr) + 
                        uint_t'(tx_pop_num_bytes) -
                        uint_t'(tx_capacity)
                    );
                end
                else begin
                    tx_read_ptr_n = ADDR_BITS'(uint_t'(tx_read_ptr) + uint_t'(tx_pop_num_bytes));
                end
            end

            if(tx_push_accept) begin
                // store each byte, start with tx_wdata[7:0]
                for(int unsigned j = 0; j < BUSIF_BYTES; j++) begin
                    // if push crosses into boundary
                    if((uint_t'(tx_write_ptr) + j) >= DEPTH_BYTES) begin
                        fifo_n[uint_t'(tx_write_ptr) + j - uint_t'(tx_capacity)] = 8'(tx_wdata >> (8*j));
                    end
                    else begin
                        // if we do not wrap around
                        fifo_n[uint_t'(tx_write_ptr) + j] = 8'(tx_wdata >> (8*j));
                    end
                end

                // advance the write ptr, accounting for wrap-around
                if((uint_t'(tx_write_ptr) + BUSIF_BYTES) >= DEPTH_BYTES) begin
                    tx_write_ptr_n = ADDR_BITS'(uint_t'(tx_write_ptr) + BUSIF_BYTES - uint_t'(tx_capacity));
                end
                else begin
                    tx_write_ptr_n = ADDR_BITS'(uint_t'(tx_write_ptr) + BUSIF_BYTES);
                end
            end 
        end

        // RX Flush, just reset all pointers to the start
        if(rx_flush) begin
            rx_occupancy_n = '0;
            rx_write_ptr_n = '0;
            rx_read_ptr_n = '0;
        end
        else begin
            // occupancy after pop, then add accepted push
            rx_occupancy_n = rx_occupancy_after_pop + (rx_push_accept ? COUNT_BITS'(rx_push_num_bytes) : '0);

            if (rx_pop_accept) begin
                // if crossed end of RX memory
                if ((uint_t'(rx_read_ptr) + uint_t'(rx_pop_num_bytes)) >= uint_t'(rx_capacity)) begin
                    // wrap the rx read address
                    rx_read_ptr_n = ADDR_BITS'(
                        uint_t'(rx_read_ptr) +
                        uint_t'(rx_pop_num_bytes) -
                        uint_t'(rx_capacity)
                    );
                end else begin
                    rx_read_ptr_n = ADDR_BITS'(
                        uint_t'(rx_read_ptr) + uint_t'(rx_pop_num_bytes)
                    );
                end
            end

            // VALID RX PUSH
            if(rx_push_accept) begin
                for(int unsigned j = 0; j < DP_BYTES; j++) begin

                    // push only rx_push_num_bytes
                    if(j < uint_t'(rx_push_num_bytes)) begin
                        // if wrap-around occurs
                        if ((uint_t'(rx_write_ptr) + j) >= uint_t'(rx_capacity)) begin
                            fifo_n[uint_t'(rx_write_ptr) + j - uint_t'(rx_capacity)] = 8'(rx_wdata >> (8*j));
                        end 
                        // no wrap needed
                        else begin
                            fifo_n[uint_t'(rx_write_ptr) + j] = 8'(rx_wdata >> (8*j));
                        end
                    end
                end 

                // advance the rx write ptr

                // if wrap-around
                if((uint_t'(rx_write_ptr) + uint_t'(rx_push_num_bytes)) >= uint_t'(rx_capacity)) begin
                    rx_write_ptr_n = ADDR_BITS'(uint_t'(rx_write_ptr) + uint_t'(rx_push_num_bytes) - uint_t'(rx_capacity));
                end

                // if not wrap around
                else begin
                    rx_write_ptr_n = ADDR_BITS'(uint_t'(rx_write_ptr) + uint_t'(rx_push_num_bytes));
                end
            end
        end
    end

    // present queued tx bytes to datapath, low byte first
    always_comb begin : tx_read_data
        tx_rdata = '0;
        tx_read_addr = 0;

        for (int unsigned j = 0; j < DP_BYTES; j++) begin
            // Only show bytes that are actually queued
            if (j < uint_t'(tx_occupancy)) begin

                // Find current byte's address.
                tx_read_addr = uint_t'(tx_read_ptr) + j;

                // wrap if needed
                if (tx_read_addr >= DEPTH_BYTES) begin
                    tx_read_addr = tx_read_addr - uint_t'(tx_capacity);
                end

                // shift data bytes into their correct positions
                tx_rdata = tx_rdata | ((DP_BYTES*8)'(fifo[tx_read_addr]) << (8*j));
            end
        end
    end

    // present queued rx bytes to register map, low byte first
    always_comb begin : rx_read_data
        rx_rdata = '0;
        rx_read_addr = 0;

        for (int unsigned j = 0; j < BUSIF_BYTES; j++) begin
            // Only show bytes that are actually queued
            if (j < uint_t'(rx_occupancy)) begin

                // get current rx read addr
                rx_read_addr = uint_t'(rx_read_ptr) + j;

                // check rx wrap around
                if (rx_read_addr >= uint_t'(rx_capacity)) begin
                    rx_read_addr = rx_read_addr - uint_t'(rx_capacity);
                end

                // shift data bytes into correct positions
                rx_rdata = rx_rdata | ((BUSIF_BYTES*8)'(fifo[rx_read_addr]) << (8*j));
            end
        end
    end

    // RX occupies addresses below tx_start
    assign rx_capacity = tx_start;

    // TX occupies addresses from tx_start through DEPTH_BYTES-1
    assign tx_capacity = COUNT_BITS'(DEPTH_BYTES) - tx_start;

    // Empty means there are no valid bytes queued
    assign tx_empty = (tx_occupancy == '0);
    assign rx_empty = (rx_occupancy == '0);

    // tx pop must request valid number of bytes, all bytes must be queued
    assign tx_pop_accept = 
        nRST && !tx_flush &&
        tx_pop &&
        (tx_pop_num_bytes != '0) &&
        (uint_t'(tx_pop_num_bytes) <= DP_BYTES) &&
        (tx_occupancy >= COUNT_BITS'(tx_pop_num_bytes));

        // RX allows a partial bus read, so any nonempty queue can be popped.
    assign rx_pop_accept =
        nRST &&
        !rx_flush &&
        rx_pop &&
        !rx_empty;
    
    // number of bytes rx is gunna pop
    assign rx_pop_num_bytes = 
            !rx_pop_accept ? 
            '0 : // if rx pop not accepted
            (rx_occupancy >= COUNT_BITS'(BUSIF_BYTES)) ? // 4 bytes
                COUNT_BITS'(BUSIF_BYTES) : // if there is at least one bus word (4 bytes), pop the bus word from fifo
                rx_occupancy; // if less than 4 bytes, pop all from fifo

    // Subtract only when the TX pop is accepted
    assign tx_occupancy_after_pop = tx_occupancy - (tx_pop_accept ? COUNT_BITS'(tx_pop_num_bytes) : '0);

    // rx_pop_num_bytes is already zero when no RX pop is accepted
    assign rx_occupancy_after_pop = rx_occupancy - rx_pop_num_bytes;

    
    // Space available after any accepted pop on this clock edge.
    assign tx_free_bytes = tx_capacity - tx_occupancy_after_pop;
    assign rx_free_bytes = rx_capacity - rx_occupancy_after_pop;

    // full if number of free bytes less than 4 bytes
    assign tx_full = (uint_t'(tx_free_bytes) < BUSIF_BYTES);

    // rx_full checks if size is invalid, or if there is not enough space to accept valid push
    assign rx_full =
    (rx_push_num_bytes == '0) || // reject 0 bytes
    (uint_t'(rx_push_num_bytes) > DP_BYTES) || // reject more bytes than rx_wdata contains
    (uint_t'(rx_free_bytes) < uint_t'(rx_push_num_bytes)); // not enough space for requested push

    // check for space available for requested push, doesn't count space freed by pop on this cycle
    assign rx_space_available =
    (rx_push_num_bytes != '0) &&
    (uint_t'(rx_push_num_bytes) <= DP_BYTES) &&
    ((rx_capacity - rx_occupancy) >=
        COUNT_BITS'(rx_push_num_bytes));

    // Accept pushes only when not resetting/flushing and enough space exists
    assign tx_push_accept =
    nRST &&
    !tx_flush &&
    tx_push &&
    !tx_full;

    assign rx_push_accept =
    nRST &&
    !rx_flush &&
    rx_push &&
    !rx_full;
endmodule

