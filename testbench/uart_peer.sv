`timescale 1ns/1ps

// Pin level UART peer, timing here is independent of the DUT's counters/FSMs
module uart_peer (
    input logic nRST,
    input logic tx,
    output logic rx = 1'b1
);
    time bit_period = 200ns;
    logic [1:0] parity_mode = 2'd0;
    logic monitor_enable = 1'b1;
    logic [7:0] received[$];
    int unsigned frames = 0;
    time earliest_next_start = 0;

    task automatic send_byte(input logic [7:0] value, input time period,
                             input logic [1:0] parity = 2'd0,
                             input logic bad_parity = 1'b0, input logic bad_stop = 1'b0);
        if (period < 2ns) $fatal(1, "UART peer: bit period must be at least 2ns");
        rx = 1'b0;
        #(period);
        for (int bit_number = 0; bit_number < 8; bit_number++) begin
            rx = value[bit_number];
            #(period);
        end
        if (parity != 0) begin
            rx = (^value) ^ (parity == 2'd1) ^ bad_parity;
            #(period);
        end
        rx = !bad_stop;
        #(period);
        rx = 1'b1;
    endtask

    task automatic collect_frame;
        logic [7:0] value;
        time period;
        logic [1:0] parity;
        period = bit_period;
        parity = parity_mode;
        if (period < 2ns) $fatal(1, "UART peer: monitor bit period must be at least 2ns");
        #(period/2);
        if (!nRST || !monitor_enable) return;
        if (tx !== 1'b0) $fatal(1, "UART peer: invalid TX start bit");
        for (int bit_number = 0; bit_number < 8; bit_number++) begin
            #(period);
            if (!nRST || !monitor_enable) return;
            value[bit_number] = tx;
        end
        if (parity != 0) begin
            #(period);
            if (!nRST || !monitor_enable) return;
            if (tx !== ((^value) ^ (parity == 2'd1)))
                $fatal(1, "UART peer: TX parity mismatch for %02h", value);
        end
        #(period);
        if (!nRST || !monitor_enable) return;
        if (tx !== 1'b1) $fatal(1, "UART peer: invalid TX stop bit");
        received.push_back(value);
        frames++;
    endtask

    initial forever begin
        @(negedge tx);
        if (nRST && monitor_enable) begin
            if ($time < earliest_next_start)
                $fatal(1, "UART peer: next start truncated the previous frame/stop bit");
            earliest_next_start = $time + bit_period * (parity_mode == 0 ? 10 : 11);
            collect_frame();
        end
    end
endmodule
