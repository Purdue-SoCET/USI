module shift_register (
    input logic CLK,
    input logic nRST,
    input logic parallel_load,
    input logic [7:0] parallel_in,
    input logic shift_en,
    input logic msb_first,
    input logic shift_in,
    output logic shift_out,
    output logic [7:0] parallel_out
);
    logic [7:0] parallel_reg, next_parallel_reg;

    assign parallel_out = parallel_reg;
    assign shift_out = msb_first ? parallel_reg[7] : parallel_reg[0];

    always_ff @(posedge CLK, negedge nRST) begin
        if (~nRST) begin
            parallel_reg <= '0;
        end
        else begin
            parallel_reg <= next_parallel_reg;
        end
    end

    always_comb begin
        next_parallel_reg = parallel_reg;
        if (parallel_load) begin
            next_parallel_reg = parallel_in;
        end
        else if (shift_en) begin
            if (msb_first) begin
                next_parallel_reg = {parallel_reg[6:0], shift_in};
            end
            else begin
                next_parallel_reg = {shift_in, parallel_reg[7:1]};
            end
        end
    end

endmodule