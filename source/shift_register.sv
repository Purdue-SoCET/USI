module shift_register (
    input logic CLK,
    input logic nRST,
    input logic start,
    input logic [7:0] parallel_in,
    input logic shift_en,
    input logic msb_first,
    input logic serial_in,
    output logic serial_out,
    output logic [7:0] parallel_out,
    output logic done
);
    logic [7:0] parallel_latch, next_parallel_latch, next_parallel_out;
    logic [2:0] bit_count, next_bit_count;

    always_ff @(posedge CLK, negedge nRST) begin
        if (~nRST) begin
            parallel_out <= 8'b0;
            bit_count <= 3'b0;
        end
        else begin
            parallel_out <= next_parallel_out;
            bit_count <= next_bit_count;
        end
    end

    always_comb begin
        next_bit_count = bit_count;
        next_parallel_latch = parallel_latch;
        if (start) begin
            next_bit_count = 3'b0;
            next_parallel_latch = parallel_in;
        end
        else if (shift_en) begin
            next_bit_count = bit_count + 1;
        end
    end

    always_comb begin
        next_parallel_out = parallel_out;
        if (shift_en) begin
            if (msb_first) begin
                next_parallel_out = {parallel_out[6:0], serial_in};
            end
            else begin
                next_parallel_out = {serial_in, parallel_out[7:1]};
            end
        end
    end

    always_comb begin
        if (msb_first) begin
            serial_out = parallel_in[7 - bit_count];
        end
        else begin
            serial_out  = parallel_in[bit_count];
        end
    end

    assign done = (bit_count == 3'b111) ? 1'b1 : 1'b0;

endmodule