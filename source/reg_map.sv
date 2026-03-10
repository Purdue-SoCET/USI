module reg_map (
    bus_protocol_if.peripheral_vital bpif,
    input logic CLK,
    input logic nRST,
    input logic ctrl_unit_error,
    input logic [31:0] buffer_read,
    output logic [1:0] mode_sel,
    output logic [31:0] clkdiv,
    output logic [31:0] configuration,
    output logic [31:0] tx_data,
    output logic [31:0] error_reg
);

    logic [1:0] n_mode_sel;
    logic [31:0] n_clkdiv;
    logic [31:0] n_configuration;
    logic [31:0] n_tx_data;
    logic [31:0] n_error_reg;
    logic bus_error;
    logic strobe_error;

    always_ff @(posedge CLK or negedge nRST) begin: reg_latches
        if(~nRST) begin
            mode_sel <= '0;
            clkdiv <= '0;
            configuration <= '0;
            tx_data <= '0;
            error_reg <= '0;
        end else begin
            mode_sel <= n_mode_sel;
            clkdiv <= n_clkdiv;
            configuration <= n_configuration;
            tx_data <= n_tx_data;
            if (bpif.ren && bpif.addr == 32'h14)
                error_reg <= '0;
            else
                error_reg <= n_error_reg;
        end
    end
    

    always_comb begin
        strobe_error = bpif.wen && (bpif.strobe != 4'b1111);
        n_mode_sel   = mode_sel;
        n_clkdiv     = clkdiv;
        n_configuration = configuration;
        n_tx_data    = tx_data;
        n_error_reg  = error_reg;

        if (bus_error)
            n_error_reg[0] = 1'b1;

        if (ctrl_unit_error)
            n_error_reg[8] = 1'b1;

        if (bpif.wen && !strobe_error) begin
            case (bpif.addr)
                32'h0: n_mode_sel = bpif.wdata[1:0];
                32'h4: n_clkdiv = bpif.wdata;
                32'h8: n_configuration = bpif.wdata;
                32'hC: n_tx_data = bpif.wdata;
                default: ;
            endcase
        end
    end

    always_comb begin
        bpif.rdata = '0;
        bpif.request_stall = 1'b0;
        bpif.error = bus_error;

        if (bpif.ren) begin
            case (bpif.addr)
                32'h0:  bpif.rdata = {30'b0, mode_sel};
                32'h4:  bpif.rdata = clkdiv;
                32'h8:  bpif.rdata = configuration;
                32'hC:  bpif.rdata = tx_data;
                32'h10: bpif.rdata = buffer_read;
                32'h14: bpif.rdata = error_reg;
                default: bpif.rdata = '0;
            endcase
        end
    end

    always_comb begin
        bus_error = 1'b0;

        if (strobe_error)
            bus_error = 1'b1;

        if (bpif.wen) begin
            case (bpif.addr)
                32'h0,
                32'h4,
                32'h8,
                32'hC: ;
                default: bus_error = 1'b1;
            endcase
        end

        if (bpif.ren) begin
            case (bpif.addr)
                32'h0,
                32'h4,
                32'h8,
                32'hC,
                32'h10,
                32'h14: ;
                default: bus_error = 1'b1;
            endcase
        end
    end

endmodule