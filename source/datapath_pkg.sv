package usi_datapath_pkg;
    typedef enum logic [2:0] {
        MODE_IDLE = 3'd0,
        MODE_UART = 3'd1,
        MODE_SPI  = 3'd2,
        MODE_I2C  = 3'd3
    } usi_mode_t;

    typedef struct packed {
        logic       tx_load;
        logic       tx_from_fifo;
        logic [7:0] tx_immediate;
        logic       tx_shift;
        logic       rx_begin;
        logic       rx_sample;
        logic       rx_commit;
        logic       rx_discard;
        logic       lsb_first;
        logic [3:0] bit_length;
    } dp_cmd_t;

    typedef struct packed {
        logic       tx_fifo_valid;
        logic       rx_fifo_ready;
        logic       tx_active;
        logic       rx_active;
        logic       tx_bit;
        logic [7:0] rx_byte;
        logic       rx_byte_valid;
        logic       tx_load_done;
        logic       tx_load_failed;
        logic       tx_done;
        logic       rx_begin_done;
        logic       rx_begin_failed;
        logic       rx_done;
        logic       rx_commit_done;
        logic       rx_commit_failed;
    } dp_status_t;
endpackage
