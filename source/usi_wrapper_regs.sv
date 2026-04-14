// ============================================================
// usi_wrapper_regs.sv
//
// Top-level USI wrapper aligned with provided reg_map and data_buffer.
//
// Assumptions:
// - reg_map and data_buffer are used exactly as provided.
// - control unit drives:
//      clear, load, send, uart_en, spi_en, i2c_en, ctrl_unit_error
// - protocol engines are already implemented elsewhere.
// - bit checker is external and provides:
//      start_bit_det, parity_error, stop_error
//
// Notes:
// - reg_map handles bus-visible register storage.
// - data_buffer handles RX/TX buffering.
// - this wrapper connects control, buffering, and protocol engines.
// - You may need to rename a few ports if your local module names differ.
// ============================================================

module usi_wrapper_regs (
    bus_protocol_if.peripheral_vital bpif,
    input  logic        CLK,
    input  logic        nRST,
    input  logic        enable,

    // external serial/bit-check inputs
    input  logic        rx_line,
    input  logic        start_bit_det,
    input  logic        parity_error,
    input  logic        stop_error,

    // top-level observable outputs
    output logic        usi_busy,
    output logic        engines_off,
    output logic        latch_mode,
    output logic        uart_en,
    output logic        spi_en,
    output logic        i2c_en,

    output logic        start_bit_en,
    output logic        stop_bit_en,
    output logic        rx_enable,
    output logic        tx_enable,
    output logic        serial_clk,
    output logic        msb_first,
    output logic [1:0]  parity_mode,
    output logic [2:0]  data_bits,
    output logic [7:0]  data_out,

    output logic        tx_out,
    output logic [7:0]  rx_byte_out,
    output logic        push_rx_fifo,
    output logic [3:0]  spi_cs_n,
    output logic        done
);

    // ------------------------------------------------------------
    // Register-map outputs
    // ------------------------------------------------------------
    logic [1:0]  mode_sel;
    logic [31:0] clkdiv;
    logic [31:0] configuration;
    logic [31:0] tx_data;
    logic [31:0] error_reg;
    logic        push;
    logic        pop;

    // ------------------------------------------------------------
    // Buffer signals
    // ------------------------------------------------------------
    logic [7:0]  buffer_data_out;
    logic [31:0] buffer_read;
    logic [7:0]  buffer_occupancy;

    logic        clear;
    logic        load;
    logic        send;

    // ------------------------------------------------------------
    // Control/status
    // ------------------------------------------------------------
    logic        ctrl_unit_error;
    logic        rx_activity;

    // ------------------------------------------------------------
    // Divider/tick generation
    // ------------------------------------------------------------
    logic [15:0] active_div;
    logic [15:0] div_cnt;
    logic        bit_tick;
    logic        half_bit_tick;

    // ------------------------------------------------------------
    // UART internal status
    // ------------------------------------------------------------
    logic uart_tx_done;
    logic uart_rx_done;
    logic uart_rx_err;
    logic uart_done_int;
    logic uart_err_int;

    logic uart_pop_tx_fifo_unused;
    logic uart_baud_en_unused;
    logic uart_baud_wait_tx;
    logic uart_baud_wait_rx;
    logic uart_half_bit_timer_en;
    logic uart_sample_rx_en;
    logic uart_tx_mod_en_unused;
    logic uart_rx_mod_en_unused;
    logic rx_line_gated;

    // ------------------------------------------------------------
    // SPI internal status/signals
    // ------------------------------------------------------------
    logic       spi_done_int;
    logic       spi_err_int;
    logic       spi_busy_unused;

    logic       spi_start_bit_en;
    logic       spi_stop_bit_en;
    logic       spi_rx_enable;
    logic       spi_tx_enable;
    logic       spi_serial_clk;
    logic       spi_msb_first;
    logic [1:0] spi_parity_mode;
    logic [2:0] spi_data_bits;
    logic [7:0] spi_data_out;

    // ------------------------------------------------------------
    // I2C internal status/signals
    // ------------------------------------------------------------
    logic       i2c_done_int;
    logic       i2c_ack_error;
    logic       i2c_busy_unused;

    logic       i2c_start_bit_en;
    logic       i2c_stop_bit_en;
    logic       i2c_rx_enable;
    logic       i2c_tx_enable;
    logic       i2c_serial_clk;
    logic       i2c_msb_first;
    logic [1:0] i2c_parity_mode;
    logic [2:0] i2c_data_bits;
    logic [7:0] i2c_data_out;

    // ------------------------------------------------------------
    // Simple decoded config fields
    // ------------------------------------------------------------
    logic [3:0] spi_slave_select_cfg;

    assign spi_slave_select_cfg = configuration[3:0];

    // Treat detected start bit/condition as receive activity
    assign rx_activity = start_bit_det;

    assign uart_done_int = uart_tx_done | uart_rx_done;
    assign uart_err_int  = uart_rx_err;

    // Your current SPI block does not expose explicit spi_err
    assign spi_err_int   = 1'b0;

    // ------------------------------------------------------------
    // Register map instance
    // ------------------------------------------------------------
    reg_map u_reg_map (
        .bpif            (bpif),
        .CLK             (CLK),
        .nRST            (nRST),
        .ctrl_unit_error (ctrl_unit_error),
        .buffer_read     (buffer_read),
        .mode_sel        (mode_sel),
        .clkdiv          (clkdiv),
        .configuration   (configuration),
        .tx_data         (tx_data),
        .error_reg       (error_reg),
        .push            (push),
        .pop             (pop)
    );

    // ------------------------------------------------------------
    // Shared split FIFO / data buffer
    // ------------------------------------------------------------
    // Incoming received byte goes into data_in.
    // Outgoing transmitted byte comes out of data_out.
    // reg_map.tx_data is pushed into FIFO as 32-bit words.
    // reg_map reads buffer_read back out as 32-bit words.
    // ------------------------------------------------------------
    data_buffer u_data_buffer (
        .CLK              (CLK),
        .nRST             (nRST),
        .mode_sel         (mode_sel),
        .data_in          (rx_byte_out),
        .buffer_write     (tx_data),
        .push             (push),
        .pop              (pop),
        .clear            (clear),
        .load             (load),
        .send             (send),
        .data_out         (buffer_data_out),
        .buffer_read      (buffer_read),
        .buffer_occupancy (buffer_occupancy)
    );

    // Export buffer transmit byte on top-level debug/data output
    assign data_out = buffer_data_out;

    // ------------------------------------------------------------
    // Divider generation from clkdiv register
    // ------------------------------------------------------------
    assign active_div = (clkdiv[15:0] == 16'd0) ? 16'd1 : clkdiv[15:0];

    always_ff @(posedge CLK or negedge nRST) begin
        if (!nRST) begin
            div_cnt <= 16'd0;
        end
        else if (clear) begin
            div_cnt <= 16'd0;
        end
        else begin
            if (div_cnt == active_div - 16'd1)
                div_cnt <= 16'd0;
            else
                div_cnt <= div_cnt + 16'd1;
        end
    end

    assign bit_tick      = (div_cnt == active_div - 16'd1);
    assign half_bit_tick = (div_cnt == ((active_div >> 1) == 16'd0 ? 16'd0
                                                               : ((active_div >> 1) - 16'd1)));

    // ------------------------------------------------------------
    // Control unit
    // Replace this instance port list if your control-unit module
    // uses slightly different names.
    // ------------------------------------------------------------
    top control_unit (
        .clk             (CLK),
        .n_rst           (nRST),
        .enable          (enable),
        .mode            (mode_sel),
        .occupancy       (buffer_occupancy),
        .start_bit_det   (start_bit_det),
        .uart_done       (uart_done_int),
        .uart_err        (uart_err_int),
        .spi_done        (spi_done_int),
        .spi_err         (spi_err_int),
        .i2c_done        (i2c_done_int),
        .i2c_err         (i2c_ack_error),

        .clear           (clear),
        .load            (load),
        .send            (send),

        .usi_busy        (usi_busy),
        .engines_off     (engines_off),
        .latch_mode      (latch_mode),
        .uart_en         (uart_en),
        .spi_en          (spi_en),
        .i2c_en          (i2c_en),
        .ctrl_unit_error (ctrl_unit_error)
    );

    // ------------------------------------------------------------
    // UART TX
    // Uses byte popped from data_buffer
    // ------------------------------------------------------------
    uart_tx_fsm_8n1 uart_tx_inst (
        .clk         (CLK),
        .rst_n       (nRST),
        .tx_req      (uart_en && send),
        .tx_data_in  (buffer_data_out),
        .baud_tick   (bit_tick),
        .pop_tx_fifo (uart_pop_tx_fifo_unused),
        .baud_en     (uart_baud_en_unused),
        .baud_wait   (uart_baud_wait_tx),
        .tx_out      (tx_out),
        .uart_en     (uart_tx_mod_en_unused),
        .done        (uart_tx_done)
    );

    // ------------------------------------------------------------
    // UART RX
    // ------------------------------------------------------------
    assign rx_line_gated = uart_en ? rx_line : 1'b1;

    uart_rx_fsm_8n1 uart_rx_inst (
        .clk               (CLK),
        .rst_n             (nRST),
        .rx_line           (rx_line_gated),
        .baud_tick         (bit_tick),
        .half_bit_tick     (half_bit_tick),
        .uart_en           (uart_rx_mod_en_unused),
        .done              (uart_rx_done),
        .err               (uart_rx_err),
        .baud_wait         (uart_baud_wait_rx),
        .half_bit_timer_en (uart_half_bit_timer_en),
        .sample_rx_en      (uart_sample_rx_en),
        .rx_byte_out       (rx_byte_out),
        .push_rx_fifo      (push_rx_fifo)
    );

    // ------------------------------------------------------------
    // SPI
    // Uses transmit byte from buffer_data_out
    // ------------------------------------------------------------
    spi_ctrl spi_inst (
        .clk           (CLK),
        .rst_n         (nRST),
        .spi_en        (spi_en),
        .start         (send),
        .sclk_tick     (bit_tick),
        .tx_data_valid (1'b1),
        .tx_data       (buffer_data_out),
        .start_bit_det (start_bit_det),
        .parity_error  (parity_error),
        .stop_error    (stop_error),
        .start_bit_en  (spi_start_bit_en),
        .stop_bit_en   (spi_stop_bit_en),
        .rx_enable     (spi_rx_enable),
        .tx_enable     (spi_tx_enable),
        .serial_clk    (spi_serial_clk),
        .msb_first     (spi_msb_first),
        .parity_mode   (spi_parity_mode),
        .data_bits     (spi_data_bits),
        .data_out      (spi_data_out),
        .busy          (spi_busy_unused),
        .done          (spi_done_int)
    );

    // ------------------------------------------------------------
    // I2C
    // Current design uses configuration[8] as RW bit if desired.
    // If you already store RW somewhere else, change this.
    // ------------------------------------------------------------
    i2c_ctrl i2c_inst (
        .clk           (CLK),
        .rst_n         (nRST),
        .i2c_en        (i2c_en),
        .start         (send),
        .scl_tick      (bit_tick),
        .addr7         (configuration[14:8]),   // example mapping; change if needed
        .rw            (configuration[15]),      // example mapping; change if needed
        .tx_data       (buffer_data_out),
        .tx_data_valid (1'b1),
        .start_bit_det (start_bit_det),
        .parity_error  (parity_error),           // used as ACK-fail in your current RTL style
        .stop_error    (stop_error),
        .start_bit_en  (i2c_start_bit_en),
        .stop_bit_en   (i2c_stop_bit_en),
        .rx_enable     (i2c_rx_enable),
        .tx_enable     (i2c_tx_enable),
        .serial_clk    (i2c_serial_clk),
        .msb_first     (i2c_msb_first),
        .parity_mode   (i2c_parity_mode),
        .data_bits     (i2c_data_bits),
        .data_out      (i2c_data_out),
        .busy          (i2c_busy_unused),
        .done          (i2c_done_int),
        .ack_error     (i2c_ack_error)
    );

    // ------------------------------------------------------------
    // SPI chip-select decode
    // Assert only while SPI engine is active
    // ------------------------------------------------------------
    always_comb begin
        spi_cs_n = 4'b1111;
        if (spi_en && usi_busy) begin
            case (spi_slave_select_cfg[1:0])
                2'd0: spi_cs_n = 4'b1110;
                2'd1: spi_cs_n = 4'b1101;
                2'd2: spi_cs_n = 4'b1011;
                2'd3: spi_cs_n = 4'b0111;
                default: spi_cs_n = 4'b1111;
            endcase
        end
    end

    // ------------------------------------------------------------
    // Shared normalized outputs
    // ------------------------------------------------------------
    always_comb begin
        start_bit_en = 1'b0;
        stop_bit_en  = 1'b0;
        rx_enable    = 1'b0;
        tx_enable    = 1'b0;
        serial_clk   = 1'b0;
        msb_first    = 1'b1;
        parity_mode  = 2'b00;
        data_bits    = 3'd7;

        if (uart_en) begin
            start_bit_en = 1'b0;
            stop_bit_en  = 1'b0;
            rx_enable    = uart_sample_rx_en;
            tx_enable    = uart_baud_wait_tx;
            serial_clk   = bit_tick;
            msb_first    = 1'b0;   // UART is LSB first
            parity_mode  = 2'b00;  // 8N1
            data_bits    = 3'd7;   // 8 bits encoded as 7 if "N-1" convention
        end
        else if (spi_en) begin
            start_bit_en = spi_start_bit_en;
            stop_bit_en  = spi_stop_bit_en;
            rx_enable    = spi_rx_enable;
            tx_enable    = spi_tx_enable;
            serial_clk   = spi_serial_clk;
            msb_first    = spi_msb_first;
            parity_mode  = spi_parity_mode;
            data_bits    = spi_data_bits;
        end
        else if (i2c_en) begin
            start_bit_en = i2c_start_bit_en;
            stop_bit_en  = i2c_stop_bit_en;
            rx_enable    = i2c_rx_enable;
            tx_enable    = i2c_tx_enable;
            serial_clk   = i2c_serial_clk;
            msb_first    = i2c_msb_first;
            parity_mode  = i2c_parity_mode;
            data_bits    = i2c_data_bits;
        end
    end

    // ------------------------------------------------------------
    // Overall done flag qualified by active engine
    // ------------------------------------------------------------
    assign done = (uart_en && uart_done_int) ||
                  (spi_en  && spi_done_int ) ||
                  (i2c_en  && i2c_done_int );

endmodule
