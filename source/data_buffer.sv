module data_buffer (
    input logic CLK,
    input logic nRST,
    input logic [1:0] mode_sel, 
    input logic [7:0] data_in,
    input logic [31:0] buffer_write, // from tx_data line of reg_map
    input logic push,
    input logic pop,
    input logic clear,
    input logic load,
    input logic send,
    output logic [7:0] data_out,
    output logic [31:0] buffer_write,
    output logic [7:0] buffer_occupancy
);

    logic [7:0] [255:0] mem;
    logic [7:0] [255:0] n_mem;
    logic [7:0] write_ptr_1, write_ptr_2, read_ptr_1, read_ptr_2;
    logic [7:0] n_write_ptr_1, n_write_ptr_2, n_read_ptr_1, n_read_ptr_2;
    logic [7:0] n_buffer_occupancy;
    logic [7:0] occupancy1, occupancy2;
    logic [7:0] n_occupancy1, n_occupancy2;

    always_ff @(posedge CLK or negedge nRST) begin
        if(~nRST) begin
            for (int i = 0; i < 256; i++) begin
                mem[i] = 8'h00;
            end
        end
        else begin
            mem <= n_mem;
        end
    end

    always_ff @(posedge CLK or negedge nRST) begin
        if(~nRST) begin
            write_ptr_1 <= '0;
            write_ptr_2 <= 8'd128;
            read_ptr_1 <= '0;
            read_ptr_2 <= 8'd128;
            buffer_occupancy <= '0;
            occupancy1 <= '0;
            occupancy2 <= '0;
        end
        else begin
            write_ptr_1 <= n_write_ptr_1;
            write_ptr_2 <= n_write_ptr_2;
            read_ptr_1 <= n_read_ptr_1;
            read_ptr_2 <= n_read_ptr_2;
            buffer_occupancy <= n_buffer_occupancy;
            occupancy1 <= n_occupancy1;
            occupancy2 <= n_occupancy2;
        end
    end

    always_comb begin
        n_write_ptr_1 = write_ptr_1;
        n_write_ptr_2 = write_ptr_2;
        n_read_ptr_1 = read_ptr_1;
        n_read_ptr_2 = read_ptr_2;
        n_mem = mem;
        n_occupancy1 = occupancy1;
        n_occupancy2 = occupancy2;
        n_buffer_occupancy = occupancy1 + occupancy2;

        if(clear) begin
            n_write_ptr_1 = '0;
            n_write_ptr_2 = 8'd128;
            n_read_ptr_1 = '0;
            n_read_ptr_2 = 8'd128;
            n_buffer_occupancy = '0;
            n_occupancy1 = '0;
            n_occupancy2 = '0;
            for (int i = 0; i < 256; i++) begin
                n_mem[i] = 8'h00;
            end
        end

        if(mode_sel != 2'b01) begin
            if(load) begin                          // rx_data
                if(occupancy1 < 8'd128) begin 
                    n_mem[write_ptr_1] = data_in;
                    n_write_ptr_1++;
                    n_occupancy1++;
                end
            end
            else if(pop) begin
                if(occupancy1 >= 8'd4) begin
                    buffer_read[7:0] = mem[read_ptr_1];
                    buffer_read[15:8] = mem[read_ptr_1 + 8'd1];
                    buffer_read[23:16] = mem[read_ptr_1 + 8'd2];
                    buffer_read[31:24] = mem[read_ptr_1 + 8'd3];
                    n_read_ptr_1 = n_read_ptr_1 - 8'd4;
                    n_occupancy1 = n_occupancy1 - 8'd4;
                end
            end
            
            if(push) begin                            // tx_data
                if(occupancy2 <= 8'd252) begin
                    n_mem[write_ptr_2] = buffer_write[7:0];
                    n_mem[write_ptr_2 + 8'd1] = buffer_write[15:8];
                    n_mem[write_ptr_2 + 8'd2] = buffer_write[23:16];
                    n_mem[write_ptr_2 + 8'd3] = buffer_write[31:24];
                    n_write_ptr_2 = n_write_ptr_2 + 8'd4;
                    n_occupancy2 = n_occupancy2 + 8'd4;
                end
            end
            else if(send) begin
                if(occupancy2 > 8'd128) begin
                    data_out = mem[read_ptr_2];
                    n_read_ptr_2--;
                    n_occupancy2--;
                end
            end 
        end
        
        else begin
            if(load) begin                          // incoming
                if(occupancy1 < 8'd128) begin 
                    n_mem[write_ptr_1] = data_in;
                    n_write_ptr_1++;
                    n_occupancy1++;
                end
            end
            else if(push) begin
                if(occupancy1 < 8'd124) begin
                    n_mem[write_ptr_1] = buffer_write[7:0];
                    n_mem[write_ptr_1 + 8'd1] = buffer_write[15:8];
                    n_mem[write_ptr_1 + 8'd2] = buffer_write[23:16];
                    n_mem[write_ptr_1 + 8'd3] = buffer_write[31:24];
                    n_write_ptr_1 = n_write_ptr_1 + 8'd4;
                    n_occupancy1 = n_occupancy1 + 8'd4;
                end
            end

            if(send) begin                          // outgoing
                if(occupancy1 > '0) begin
                    data_out = mem[read_ptr_1];
                    n_read_ptr_1--;
                    n_occupancy1--;
                end
            end 
            else if(pop) begin
                if(occupancy1 >= 8'd4) begin
                    buffer_read[7:0] = mem[read_ptr_1];
                    buffer_read[15:8] = mem[read_ptr_1 + 8'd1];
                    buffer_read[23:16] = mem[read_ptr_1 + 8'd2];
                    buffer_read[31:24] = mem[read_ptr_1 + 8'd3];
                    n_read_ptr_1 = n_read_ptr_1 - 8'd4;
                    n_occupancy1 = n_occupancy1 - 8'd4;
                end
            end
        end
    end


endmodule