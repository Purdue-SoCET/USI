module I2C #( 
) (
    input logic clk,
    input logic n_rst,
    input logic rwconfig, // read/write mode
    input logic addr_config,
    input logic en,
    input logic [15:0] div,
    input logic scl_in,
    input logic read_done,
    input usi_datapath_pkg::dp_status_t dp_in, 
    output usi_datapath_pkg::dp_cmd_t dp_out, //this is SDA control....
    output logic scl // this is SCL control. This could be added to datapath later...
);

    localparam sys_clk = 150000 // MHz
    logic div_clk;


    typedef enum logic [2:0] {
        IDLE,
        RSET,
        START,
        ADDR,
        RWBIT,
        AWK,
        STOP,
        DATA
    } state_t;

    logic bcount_clr, bcount_en, count_sig;
    logic scl_en, scl_clr;
    logic [3:0] broll, count_out;

    flexCounter clkDiv(
        .clk(clk),
        .n_rst(n_rst),
        .rollover_val(div),
        .clear(scl_clr),
        .count_enable(scl_en),
        .count_out(),
        .rollover_flag(div_clk)
    );

    flexCounter bitCount(
        .clk(clk),
        .n_rst(n_rst),
        .rollover_val(broll),
        .clear(bcount_clr),
        .count_enable(bcount_en),
        .count_out(count_out),
        .rollover_flag(count_sig)
    );

    state_t state, next_state;
    logic next_scl;
    logic bcount_en;

    always_ff @(posedge clk, negedge n_rst) begin
        if(!n_rst) begin
            state <= IDLE;
            scl <= 1'b1;
        end else begin
            state <= next_state;
            scl <= next_scl;
        end
    end

    task automatic tx_push(
        input logic [7:0] data,
        input logic from_fifo,
        input logic en_shift
    );
        dp_out.tx_load = 1'b1;
        dp_out.tx_from_fifo = from_fifo;
        dp_out.tx_immediate = data;
        dp_out.tx_shift = en_shift;
    endtask

    task automatic rx_config(
        input logic rbegin,
        input logic sample,
        input logic commit,
        input logic discard
    );
        dp_out.lsb_first = 1'b0; //assume always msb for this???
        dp_out.rx_begin = rbegin;
        dp_out.rx_sample = sample;
        dp_out.rx_commit = commit;
        dp_out.rx_discard = discard;
    endtask

    task automatic set_counters(
        input logic scl_c,
        input logic scl_enable,
        input logic bcount_c,
        input logic bcount_enable
    );
        scl_clr = scl_c;
        scl_en = scl_enable;
        bcount_clr = bcount_c;
        bcount_en = bcount_enable;
    endtask

    always_comb begin : FSM
        bcount_en = 1'b0;
        scl_en = 1'b1;
        rx_config(1'b0, 1'b0, 1'b0, 1'b0); // rx active but continually clearing to be free for later reads
        tx_push(8'd1, 1'b0, 1'b1);
        set_counters(1'b0, 1'b1, 1'b1, 1'b0); // default is scl on, data counter off
        next_scl = scl_in ? (div_clk ? !scl : scl) : 1'b0;
        broll = 4'd8; // default for byte package
        case(state) 
            IDLE: begin
                // I2C idle state is 1 for SDA and SCL
                next_scl = 1'b1; //SCL
                next_state = en ? START : IDLE;
            end
            START: begin
                tx_push(8'd0, 1'b0, 1'b1); 
                next_scl = 1'b1; // keep scl high to activate start bit
                if(scl) begin
                    set_counters(1'b0, 1'b1, 1'b0, 1'b1);
                end
                next_state = scl ? ADDR : state;
            end
            ADDR: begin
                set_counters(1'b0, 1'b1, 1'b0, 1'b1);
                broll = addr_config ? 4'd7 : 4'd10; // 1 for 7-bit, 0 for 10-bit
                if(rwconfig) begin
                    tx_push(8'hFF, 1'b1, 1'b1);
                    next_state = count_sig ? RWBIT : state;
                end
            end
            RWBIT: begin
                next_state = scl ? rwconfig ? RSET : AWK : state;
                if(rwconfig) begin // writing/sending
                    tx_push(8'd0, 1'b0, 1'b1);
                end else begin // reading
                    tx_push(8'd1, 1'b0, 1'b1);
                end
            end
            RSET: begin
                tx_push(8'd1, 1'b0, 1'b0);  
                rx_config(1'b1, 1'b0, 1'b0, 1'b0);
                next_scl = 1'b1;
                next_state = dp_in.rx_begin_failed ? state : dp_in.rx_begin_done ? rwconfig ? AWK : DATA : state;
            end
            AWK: begin 
                next_state = state;
                if(rwconfig) begin // write mode (reading for awk bit from slave)
                    rx_config(1'b0, 1'b1, 1'b0, 1'b0); 
                    if(scl) begin // proper awknolwedge is a pull down
                        set_counters(1'b0, 1'b1, 1'b0, 1'b1);
                        next_state = (!data_byte[0] && dp_in.tx_fifo_valid) ? DATA : STOP;
                    end
                end else begin
                    tx_push(8'd0, 1'b0, 1'b1);  
                    if(scl) begin // proper awknolwedge is a pull down
                        set_counters(1'b0, 1'b1, 1'b0, 1'b1);
                        next_state = read_done ? STOP : RSET;
                    end
                end
            end
            DATA: begin
                set_counters(1'b0, 1'b1, 1'b0, 1'b1);
                next_state = state;
                if(rwconfig) begin // write mode
                    if(count_out & 4'd1) begin
                        tx_push(8'hFF, 1'b1, 1'b0);  
                    end
                    if(scl) begin
                        next_state = count_sig ? AWK : state;
                    end
                end else begin // read mode
                    rx_config(1'b0, 1'b1, 1'b0, 1'b0);
                    if(scl) begin
                        next_scl = dp_out.rx_fifo_ready ? next_scl : 1'b0;
                    end
                end
            end
            STOP: begin
                tx_push(8'd0, 1'b1, 1'b0); 
                next_scl = 1'b1; // have scl be high and keep SDA low until next state to IDLE
                next_state = scl ? IDLE : state;
            end
        endcase
    end
endmodule