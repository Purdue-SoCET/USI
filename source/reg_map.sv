`include "bus_protocol_if.vh"
//test push

module reg_map (
    bus_protocol_if.peripheral_vital bpif,
    input logic CLK,
    input logic nRST,
    input logic ctrl_unit_error,
    output logic [1:0] mode_sel,
    output logic [31:0] clkdiv,
    output logic [31:0] parameters,
    output logic [31:0] tx_data,
    output logic [31:0] rx_data,
    output logic [31:0] error_reg
);

    logic [1:0] n_mode_sel;
    logic [31:0] n_clkdiv;
    logic [31:0] n_parameters;
    logic [31:0] n_tx_data;
    logic [31:0] n_rx_data;
    logic [31:0] n_error_reg;

    always_ff @(posedge CLK or negedge nRST) begin: reg_latches
        if(~nRST) begin
            mode_sel <= '0;
            clkdiv <= '0;
            parameters <= '0;
            tx_data <= '0;
            rx_data <= '0;
            error_reg <= '0;
        end else begin
            mode_sel <= n_mode_sel;
            clkdiv <= n_clkdiv;
            parameters <= n_parameters;
            tx_data <= n_tx_data;
            rx_data <= n_rx_data;
            error_reg <= n_error_reg;
        end
    end
    
    always_comb begin: mode_sel_comb
        n_mode_sel = mode_sel;

        if(bpif.wen) begin
            if(bpif.addr == 32'h0) begin
                n_mode_sel = bpif.wdata[1:0];
            end
        end

        if(bpif.ren) begin
            if(bpif.addr == 32'h0) begin
                bpif.rdata = {30'b0, mode_sel};
            end
        end
    end

    always_comb begin: clkdiv_comb
        n_clkdiv = clkdiv;

        if(bpif.wen) begin
            if(bpif.addr == 32'h4) begin
                n_clkdiv = bpif.wdata;
            end
        end

        if(bpif.ren) begin
            if(bpif.addr == 32'h4) begin
                bpif.rdata = clkdiv;
            end
        end
    end

    always_comb begin: parameters_comb
        n_parameters = parameters;

        if(bpif.wen) begin
            if(bpif.addr == 32'h8) begin
                n_parameters = bpif.wdata;
            end
        end

        if(bpif.ren) begin
            if(bpif.addr == 32'h8) begin
                bpif.rdata = parameters;
            end
        end
    end

    always_comb begin: tx_data_comb
        n_tx_data = tx_data;

        if(bpif.wen) begin
            if(bpif.addr == 32'hC) begin
                n_tx_data = bpif.wdata;
            end
        end

        if(bpif.ren) begin
            if(bpif.addr == 32'hC) begin
                bpif.rdata = tx_data;
            end
        end
    end

    always_comb begin: rx_data_comb
        n_rx_data = rx_data;

        if(bpif.wen) begin
            if(bpif.addr == 32'h10) begin
                n_rx_data = bpif.wdata;
            end
        end

        if(bpif.ren) begin
            if(bpif.addr == 32'h10) begin
                bpif.rdata = rx_data;
            end
        end
    end

    always_comb begin: error_reg_comb
        n_error_reg = error_reg;
        // when to latch?
        n_error_reg[0] = bpif.error;
        n_error_reg[8] = ctrl_unit_error; 
        if(bpif.ren) begin
            if(bpif.addr == 32'h14) begin
                bpif.rdata = error_reg;
            end
        end
    end

endmodule