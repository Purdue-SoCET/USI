module wrapper(
    input  logic        CLOCK_50,
    input  logic [3:0]  KEY,
    input  logic [17:0] SW,
    output logic [17:0] LEDR,
    output logic [7:0]  LEDG
);

    logic auto_nRST;
    logic [3:0] auto_nRST_count;
    logic nRST;

    logic serial_in;
    logic serial_out;
    logic serial_clk;
    logic [31:0] spi_cs_n;

    bus_protocol_if bpif();

    logic [31:0] addr_sel;
    logic [31:0] write_data_reg;
    logic [31:0] read_data_latched;

    logic key0_ff1, key0_ff2, key0_prev;
    logic key1_ff1, key1_ff2, key1_prev;
    logic key2_ff1, key2_ff2, key2_prev;

    logic load_word_pulse;
    logic read_pulse;
    logic write_pulse;

    typedef enum logic [1:0] {
        IDLE,
        ISSUE,
        HOLD
    } state_t;

    state_t state, next_state;

    logic op_is_write;
    logic op_is_read;

    initial begin
        auto_nRST = 1'b0;
        auto_nRST_count = 4'b0000;
    end

    assign nRST = KEY[3] & auto_nRST;
    assign serial_in = SW[0];

    always_ff @(posedge CLOCK_50) begin
        if (auto_nRST_count != 4'hF) begin
            auto_nRST_count <= auto_nRST_count + 1'b1;
            auto_nRST <= 1'b0;
        end
        else begin
            auto_nRST <= 1'b1;
        end
    end

    always_comb begin
        unique case (SW[17:15])
            3'b000: addr_sel = 32'h0000_0000;
            3'b001: addr_sel = 32'h0000_0004;
            3'b010: addr_sel = 32'h0000_0008;
            3'b011: addr_sel = 32'h0000_000C;
            3'b100: addr_sel = 32'h0000_0010;
            3'b101: addr_sel = 32'h0000_0014;
            default: addr_sel = 32'h0000_0000;
        endcase
    end

    always_ff @(posedge CLOCK_50 or negedge nRST) begin
        if (!nRST) begin
            key0_ff1 <= 1'b1;
            key0_ff2 <= 1'b1;
            key0_prev <= 1'b1;

            key1_ff1 <= 1'b1;
            key1_ff2 <= 1'b1;
            key1_prev <= 1'b1;

            key2_ff1 <= 1'b1;
            key2_ff2 <= 1'b1;
            key2_prev <= 1'b1;
        end
        else begin
            key0_ff1 <= KEY[0];
            key0_ff2 <= key0_ff1;
            key0_prev <= key0_ff2;

            key1_ff1 <= KEY[1];
            key1_ff2 <= key1_ff1;
            key1_prev <= key1_ff2;

            key2_ff1 <= KEY[2];
            key2_ff2 <= key2_ff1;
            key2_prev <= key2_ff2;
        end
    end

    assign load_word_pulse = key0_prev & ~key0_ff2;
    assign read_pulse      = key1_prev & ~key1_ff2;
    assign write_pulse     = key2_prev & ~key2_ff2;

    always_ff @(posedge CLOCK_50 or negedge nRST) begin
        if (!nRST) begin
            write_data_reg <= 32'h0000_0000;
        end
        else if (load_word_pulse) begin
            if (SW[16] == 1'b0)
                write_data_reg[15:0] <= {1'b0, SW[14:0]};
            else
                write_data_reg[31:16] <= {1'b0, SW[14:0]};
        end
    end

    always_ff @(posedge CLOCK_50 or negedge nRST) begin
        if (!nRST) begin
            state <= IDLE;
            op_is_write <= 1'b0;
            op_is_read <= 1'b0;
            read_data_latched <= 32'h0000_0000;
        end
        else begin
            state <= next_state;

            if (state == IDLE) begin
                if (write_pulse) begin
                    op_is_write <= 1'b1;
                    op_is_read <= 1'b0;
                end
                else if (read_pulse) begin
                    op_is_write <= 1'b0;
                    op_is_read <= 1'b1;
                end
                else begin
                    op_is_write <= 1'b0;
                    op_is_read <= 1'b0;
                end
            end

            if ((state == HOLD) && !bpif.request_stall && op_is_read)
                read_data_latched <= bpif.rdata;
        end
    end

    always_comb begin
        next_state = state;

        unique case (state)
            IDLE: begin
                if (write_pulse || read_pulse)
                    next_state = ISSUE;
            end

            ISSUE: begin
                next_state = HOLD;
            end

            HOLD: begin
                if (!bpif.request_stall)
                    next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    always_comb begin
        bpif.wen = 1'b0;
        bpif.ren = 1'b0;
        bpif.addr = addr_sel;
        bpif.wdata = write_data_reg;
        bpif.strobe = 4'b1111;
        bpif.is_burst = 1'b0;
        bpif.burst_type = 2'b00;
        bpif.burst_length = 8'h00;
        bpif.secure_transfer = 1'b0;

        case (state)
            ISSUE,
            HOLD: begin
                bpif.wen = op_is_write;
                bpif.ren = op_is_read;
            end
            default: begin
                bpif.wen = 1'b0;
                bpif.ren = 1'b0;
            end
        endcase
    end

    top DUT (
        .CLK(CLOCK_50),
        .nRST(nRST),
        .bpif(bpif.peripheral_vital),
        .serial_in(serial_in),
        .serial_out(serial_out),
        .serial_clk(serial_clk),
        .spi_cs_n(spi_cs_n)
    );

    assign LEDR = read_data_latched[17:0];

    assign LEDG[0] = ~KEY[0];
    assign LEDG[1] = ~KEY[1];
    assign LEDG[2] = ~KEY[2];
    assign LEDG[3] = (state == IDLE);
    assign LEDG[4] = (state == ISSUE);
    assign LEDG[5] = (state == HOLD);
    assign LEDG[6] = bpif.error;
    assign LEDG[7] = SW[16];

endmodule