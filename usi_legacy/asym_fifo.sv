/* verilator lint_off WIDTHTRUNC */
module asym_fifo #(
    parameter unsigned READ_BYTES = 1, 
    parameter unsigned WRITE_BYTES = 1, 
    parameter unsigned DEPTH_BYTES = 16 // total capacity in bytes, must be power of 2
)(
    input logic CLK,
    input logic nRST,
    input logic WEN,
    input logic REN,
    input logic clear_underrun,
    input logic clear_overrun,
    input logic flush,
    input logic [(WRITE_BYTES*8-1):0] wdata, 
    output logic full,
    output logic empty,
    output logic underrun, 
    output logic overrun,
    output logic [$clog2(DEPTH_BYTES+1)-1:0] count,
    output logic [(READ_BYTES*8-1):0] rdata  
);

    generate
        if (DEPTH_BYTES == 0 || (DEPTH_BYTES & (DEPTH_BYTES - 1)) != 0) begin : DEPTH_power
            $error("%m: DEPTH must be a power of 2 >= 1!");
        end
        if (READ_BYTES > DEPTH_BYTES || WRITE_BYTES > DEPTH_BYTES) begin : DEPTH_size
            $error("%m: DEPTH must be >= READ_BYTES and WRITE_BYTES");
        end
    endgenerate
    
    localparam int ADDR_BITS = $clog2(DEPTH_BYTES);

    logic overrun_next, underrun_next;
    logic [ADDR_BITS-1:0] write_ptr, write_ptr_next, read_ptr, read_ptr_next;
    logic [$clog2(DEPTH_BYTES+1)-1:0] count_next;
    logic [7:0] fifo [DEPTH_BYTES-1:0];
    logic [7:0] fifo_next [DEPTH_BYTES-1:0];
    logic [$clog2(DEPTH_BYTES+1):0] count_after_read;

    always_ff @(posedge CLK, negedge nRST) begin
        if(!nRST) begin
            write_ptr <= '0;
            read_ptr <= '0;
            overrun <= 1'b0;
            underrun <= 1'b0;
            count <= '0;
        end else begin
            fifo <= fifo_next;
            write_ptr <= write_ptr_next;
            read_ptr <= read_ptr_next;
            overrun <= overrun_next;
            underrun <= underrun_next;
            count <= count_next;
        end
    end

    always_comb begin
        fifo_next = fifo;
        write_ptr_next = write_ptr;
        read_ptr_next = read_ptr;
        overrun_next = overrun;
        underrun_next = underrun;
        count_next = count;

        if(flush) begin
            // No need to actually reset FIFO data,
            // changing pointers/flags to "empty" state is OK
            write_ptr_next = '0;
            read_ptr_next = '0;
            overrun_next = 1'b0;
            underrun_next = 1'b0;
            count_next = '0;
        end else begin
            overrun_next = clear_overrun ? 1'b0 : overrun;
            underrun_next = clear_underrun ? 1'b0 : underrun;
            if(REN && !empty) begin
                read_ptr_next = read_ptr + READ_BYTES;
            end else if(REN && empty) begin
                underrun_next = 1'b1;
            end

            if(WEN && !full) begin
                write_ptr_next = write_ptr + WRITE_BYTES;
                /* verilator lint_off WIDTHEXPAND */
                for (int j = 0; j < WRITE_BYTES; j++)
                    fifo_next[((write_ptr + j) & {ADDR_BITS{1'b1}})] = wdata[8*j +: 8];
                    /* verilator lint_on WIDTHEXPAND */
            end else if(WEN && full) begin
                overrun_next = 1'b1;
            end

            count_next = count + (WEN && !full ? WRITE_BYTES : '0) - (REN && !empty ? READ_BYTES : '0);
        end
    end

    assign count_after_read = {1'b0, count} - (REN && !empty ? READ_BYTES : '0);
    assign full = (count_after_read + WRITE_BYTES) > DEPTH_BYTES; // Can read + write when full
    assign empty = READ_BYTES > count; // Can't read + write when empty
    genvar i;
    generate
        for (i = 0; i < READ_BYTES; i++) begin : rdata_block
            assign rdata[8*i +: 8] = fifo[((read_ptr+i) & {ADDR_BITS{1'b1}})];
        end
    endgenerate

endmodule
