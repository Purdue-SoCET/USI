module I2C #( 
) (
    input logic clk,
    input logic n_rst,
    input logic [2:0] config_in,
    input logic scl_in,
    input logic sda_in,
    input logic en,
    input logic [15:0] div,
    output logic scl,
    output logic sda,
    output logic count_sig
);

    localparam sys_clk = 150000 // MHz
    //localparam addr_bit = 7;
    logic div_clk;

    // input_sig --> mode = [1:0], r/w [2]

    //speeds based on online resouces for common modes supported
    //https://www.circuitbasics.com/basics-of-the-i2c-communication-protocol/

    /*
    typedef enum logic [1:0] {
        STANDARD,  // 100 kHz
        FAST,    // 400 kHz
        FAST_PLUS,   // 1 MHz
        HIGH    // 3.4 MHz
    } mode_t;
    */

    typedef struct packed {
        logic rwconfig; // 0 for read, 1 for write
        //mode_t [1:0] speed;
    } config_t;

    typedef enum logic [2:0] {
        IDLE,
        START,
        ADDR,
        RWBIT,
        AWK,
        WSTOP,
        RSTOP,
        DATA
    } state_t;

    flexCounter clkDiv(
        .clk(clk),
        .n_rst(n_rst),
        .rollover_val(div),
        .clear(),
        .count_enable(),
        .count_out(),
        .rollover_flag(div_clk)
    );

    flexCounter bitCount(
        .clk(clk),
        .n_rst(n_rst),
        .rollover_val(4'd7),
        .clear(),
        .count_enable(),
        .count_out(),
        .rollover_flag(count_sig)
    );

    state_t state, next_state;
    logic [10:0] div;
    config_t config;
    logic next_sda, next_scl;
    logic bcount_en;

    always_ff @(posedge clk, negedge n_rst) begin
        if(!n_rst) begin
            state <= IDLE;
            //mode <= STANDARD;
            sda <= 1'b1;
            scl <= 1'b1;
        end else begin
            state <= next_state;
            //mode <= next_mode;
            sda <= next_sda;
            scl <= next_scl;
        end
    end

    always_comb begin : FSM
        bcount_en = 1'b0;
        config = config_in
        case(state) 
            IDLE: begin
                next_sda = 1'b1;
                next_scl = 1'b1;
                next_state = en ? START : IDLE;
            end
            START: begin
                if(config.rwconfig) begin // write mode
                    next_sda = 1'b0;
                    next_scl = div_clk ? !scl : scl;
                    next_state = div_clk ? ADDR : state;
                end
                else begin //read mode
                    next_state = state;
                    if(div_clk && !sda && scl) begin
                        next_state = ADDR;  
                    end
                end
            end
            ADDR: begin
                if(config.rwconfig) begin
                    bcount_en = 1'b1;
                end
            end
        endcase
    end

    /*
    always_comb begin : clkDiv
        case(speed)
            STANDARD: div = 10'd749;
            FAST: div = 10'd186;
            FAST_PLUS: div = 10'd74;    
            HIGH: div = 10'd21;
            default: div = 10'd749;
        endcase
    end
    */

endmodule