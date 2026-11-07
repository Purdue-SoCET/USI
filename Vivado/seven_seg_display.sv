module seven_segment_display (
    input  logic        CLK,
    input  logic        nRST,
    input  logic [15:0] display_value,
    output logic [7:0]  display_segments,
    output logic [3:0]  display_digit_enable
);

    logic [15:0] scan_count, scan_count_n;
    logic [1:0] digit_select;
    logic [3:0] digit_value;

    // Calculate the next scanning-counter value.
    always_comb begin
        scan_count_n = scan_count + 16'd1;
    end

    // Store the scanning-counter value.
    always_ff @(posedge CLK or negedge nRST) begin
        if (!nRST)
            scan_count <= '0;
        else
            scan_count <= scan_count_n;
    end

    // Select one of four digits.
    assign digit_select = scan_count[15:14];

    always_comb begin
        digit_value = 4'h0;
        display_digit_enable = 4'b1111;
        display_segments = 8'hFF;

        // Enable one digit and select its corresponding nibble.
        // Digit enables are active low.
        case (digit_select)
            2'd0: begin
                display_digit_enable = 4'b1110;
                digit_value = display_value[3:0];
            end

            2'd1: begin
                display_digit_enable = 4'b1101;
                digit_value = display_value[7:4];
            end

            2'd2: begin
                display_digit_enable = 4'b1011;
                digit_value = display_value[11:8];
            end

            2'd3: begin
                display_digit_enable = 4'b0111;
                digit_value = display_value[15:12];
            end

            default: begin
                display_digit_enable = 4'b1111;
            end
        endcase

        // Decode the selected hexadecimal digit.
        // Bit order is {DP, G, F, E, D, C, B, A}.
        // A zero lights a segment; DP stays off.
        case (digit_value)
            4'h0: display_segments = 8'hC0;
            4'h1: display_segments = 8'hF9;
            4'h2: display_segments = 8'hA4;
            4'h3: display_segments = 8'hB0;
            4'h4: display_segments = 8'h99;
            4'h5: display_segments = 8'h92;
            4'h6: display_segments = 8'h82;
            4'h7: display_segments = 8'hF8;
            4'h8: display_segments = 8'h80;
            4'h9: display_segments = 8'h90;
            4'hA: display_segments = 8'h88;
            4'hB: display_segments = 8'h83;
            4'hC: display_segments = 8'hC6;
            4'hD: display_segments = 8'hA1;
            4'hE: display_segments = 8'h86;
            4'hF: display_segments = 8'h8E;
            default: display_segments = 8'hFF;
        endcase

        // Blank the display during reset.
        if (!nRST) begin
            display_digit_enable = 4'b1111;
            display_segments = 8'hFF;
        end
    end

endmodule