`timescale 1ns/1ps

module split_fifo_tb;

    localparam int DEPTH_BYTES = 256;
    localparam int BUSIF_BYTES = 4;
    localparam int DP_BYTES    = 2;
    localparam int COUNT_BITS = $clog2(DEPTH_BYTES + 1);
    localparam int NUM_BYTES_BITS = $clog2(DP_BYTES + 1);

    logic clk = 0;
    logic nRST;

    logic [BUSIF_BYTES*8-1:0] tx_wdata;
    logic tx_push, tx_pop, tx_flush;
    logic [NUM_BYTES_BITS-1:0] tx_pop_num_bytes;

    logic [DP_BYTES*8-1:0] tx_rdata;
    logic tx_empty, tx_full;
    logic [COUNT_BITS-1:0] tx_occupancy;

    logic [DP_BYTES*8-1:0] rx_wdata;
    logic rx_push, rx_pop, rx_flush;
    logic [NUM_BYTES_BITS-1:0] rx_push_num_bytes;

    logic [BUSIF_BYTES*8-1:0] rx_rdata;
    logic rx_empty, rx_full;
    logic [COUNT_BITS-1:0] rx_occupancy;

    logic dp_busy, split_apply;
    logic [COUNT_BITS-1:0] fifo_tx_start;
    logic rx_space_available;

    // Connect DUT ports to testbench signals with matching names.
    split_fifo #(
        .DEPTH_BYTES(DEPTH_BYTES),
        .BUSIF_BYTES(BUSIF_BYTES),
        .DP_BYTES(DP_BYTES)
    ) dut (.*);

    // 10 ns clock period.
    always #5 clk = ~clk;

    initial begin
        nRST = 0;

        tx_wdata = '0;
        tx_push = 0;
        tx_pop = 0;
        tx_flush = 0;
        tx_pop_num_bytes = NUM_BYTES_BITS'(1);

        rx_wdata = '0;
        rx_push = 0;
        rx_pop = 0;
        rx_flush = 0;
        rx_push_num_bytes = NUM_BYTES_BITS'(1);

        dp_busy = 0;
        split_apply = 0;
        fifo_tx_start = COUNT_BITS'(DEPTH_BYTES / 2);

        // Hold reset through two rising edges, then release it.
        repeat (2) @(negedge clk);
        nRST = 1;

        @(negedge clk);
        if (tx_occupancy !== '0 || rx_occupancy !== '0)
            $fatal(1, "Reset failed: occupancies must be zero");

        if (tx_empty !== 1'b1 || rx_empty !== 1'b1)
            $fatal(1, "Reset failed: both queues must be empty");

        if (tx_full !== 1'b0 || rx_full !== 1'b0)
            $fatal(1, "Reset failed: both queues should have space");

        if (tx_rdata !== '0 || rx_rdata !== '0)
            $fatal(1, "Reset failed: empty read outputs must be zero");

        $display("PASS: reset checks");

        // Drive a single four-byte push.
        @(negedge clk);
        tx_wdata = 32'h44332211;
        tx_push = 1;
        tx_pop = 0;
        tx_pop_num_bytes = NUM_BYTES_BITS'(2);

        // One rising edge has occurred: the push is complete.
        @(negedge clk);

        if (tx_occupancy !== COUNT_BITS'(4))
            $fatal(1, "TX push: expected 4 queued bytes");

        if (tx_empty !== 1'b0)
            $fatal(1, "TX push: FIFO should not be empty");

        if (tx_rdata !== 16'h2211)
            $fatal(1, "TX push: expected first two bytes = 2211");

        $display("PASS: TX push");

        // Still on this falling edge: stop pushing and start popping.
        tx_push = 0;
        tx_pop = 1;

        // First two-byte pop has completed.
        @(negedge clk);

        if (tx_occupancy !== COUNT_BITS'(2))
            $fatal(1, "First TX pop: expected 2 queued bytes");

        if (tx_rdata !== 16'h4433)
            $fatal(1, "First TX pop: expected next two bytes = 4433");

        $display("PASS: first TX pop");

        // Leave tx_pop asserted for one more rising edge.
        @(negedge clk);

        if (tx_occupancy !== COUNT_BITS'(0))
            $fatal(1, "Second TX pop: expected zero queued bytes");

        if (tx_empty !== 1'b1)
            $fatal(1, "Second TX pop: FIFO should be empty");

        if (tx_rdata !== 16'h0000)
            $fatal(1, "Second TX pop: expected zero output");

        // Stop popping on this same falling edge.
        tx_pop = 0;

        $display("PASS: second TX pop");

        // Push one RX byte, like an 8-bit UART transfer.
        @(negedge clk);
        rx_wdata = 16'h00AA;
        rx_push_num_bytes = NUM_BYTES_BITS'(1);
        rx_push = 1;
        rx_pop = 0;

        @(negedge clk);

        if (rx_occupancy !== COUNT_BITS'(1))
            $fatal(1, "RX one-byte push: expected occupancy of 1");

        if (rx_rdata !== 32'h000000AA)
            $fatal(1, "RX one-byte push: expected 000000AA");

        $display("PASS: RX one-byte push");

        // Keep rx_push asserted, but supply a new two-byte transfer.
        // Low byte BB enters first, then CC.
        rx_wdata = 16'hCCBB;
        rx_push_num_bytes = NUM_BYTES_BITS'(2);

        @(negedge clk);

        if (rx_occupancy !== COUNT_BITS'(3))
            $fatal(1, "RX two-byte push: expected total occupancy of 3");

        if (rx_rdata !== 32'h00CCBBAA)
            $fatal(1, "RX packing: expected 00CCBBAA");

        $display("PASS: RX two-byte push and packing");

        // Stop pushing and request a bus read.
        // Only three bytes exist, so this pop removes three.
        rx_push = 0;
        rx_pop = 1;

        @(negedge clk);

        if (rx_occupancy !== COUNT_BITS'(0))
            $fatal(1, "RX partial pop: expected zero occupancy");

        if (rx_empty !== 1'b1)
            $fatal(1, "RX partial pop: expected empty");

        if (rx_rdata !== 32'h00000000)
            $fatal(1, "RX partial pop: expected zero output");

        rx_pop = 0;

        $display("PASS: RX partial bus read");

        // Put data into both queues.
        @(negedge clk);
        tx_wdata = 32'h44332211;
        tx_push = 1;
        tx_pop = 0;

        rx_wdata = 16'hBBAA;
        rx_push_num_bytes = NUM_BYTES_BITS'(2);
        rx_push = 1;
        rx_pop = 0;

        @(negedge clk);

        if (tx_occupancy !== COUNT_BITS'(4) ||
            rx_occupancy !== COUNT_BITS'(2))
            $fatal(1, "Flush setup: expected 4 TX bytes and 2 RX bytes");

        // Stop pushing and flush only TX.
        tx_push = 0;
        rx_push = 0;
        tx_flush = 1;

        @(negedge clk);

        if (tx_occupancy !== '0 || tx_empty !== 1'b1)
            $fatal(1, "TX flush: expected empty TX queue");

        if (tx_rdata !== '0)
            $fatal(1, "TX flush: expected zero TX output");

        if (rx_occupancy !== COUNT_BITS'(2) ||
            rx_rdata !== 32'h0000BBAA)
            $fatal(1, "TX flush must preserve RX data");

        $display("PASS: TX flush preserves RX");

        // Stop flushing TX and flush RX.
        tx_flush = 0;
        rx_flush = 1;

        @(negedge clk);

        if (rx_occupancy !== '0 || rx_empty !== 1'b1)
            $fatal(1, "RX flush: expected empty RX queue");

        if (rx_rdata !== '0)
            $fatal(1, "RX flush: expected zero RX output");

        rx_flush = 0;

        $display("PASS: RX flush");

        // Apply a new split: 96 RX bytes, 160 TX bytes.
        @(negedge clk);
        dp_busy = 0;
        fifo_tx_start = COUNT_BITS'(96);
        split_apply = 1;

        @(negedge clk);

        if (dut.tx_start !== COUNT_BITS'(96))
            $fatal(1, "Split change: expected active boundary of 96");

        if (dut.rx_capacity !== COUNT_BITS'(96) ||
            dut.tx_capacity !== COUNT_BITS'(160))
            $fatal(1, "Split change: expected RX=96 and TX=160 bytes");

        if (tx_occupancy !== '0 || rx_occupancy !== '0)
            $fatal(1, "Split change: queues should remain empty");

        split_apply = 0;

        $display("PASS: split changed to RX=96, TX=160");

        // Request another split while the datapath is busy.
        @(negedge clk);
        dp_busy = 1;
        fifo_tx_start = COUNT_BITS'(128);
        split_apply = 1;

        @(negedge clk);

        // The requested change must not replace the active boundary.
        if (dut.tx_start !== COUNT_BITS'(96))
            $fatal(1, "Busy split change: active boundary must stay at 96");

        $display("PASS: split change rejected while busy");

        // Remove the request before making the datapath idle.
        split_apply = 0;
        dp_busy = 0;

        @(negedge clk);

        // A rejected request must not apply later automatically.
        if (dut.tx_start !== COUNT_BITS'(96))
            $fatal(1, "Rejected split request must not apply later");

        $display("PASS: rejected split request was not queued");

        // TX: 6 BYTES
        // RX: 250 BYTES
        @(negedge clk);
        tx_push = 0;
        tx_pop = 0;
        rx_push = 0;
        rx_pop = 0;
        split_apply = 0;
        dp_busy = 0;
        tx_flush = 1;
        rx_flush = 1;

        @(negedge clk);
        // apply the split
        tx_flush = 0;
        rx_flush = 0;
        fifo_tx_start = COUNT_BITS'(250);
        split_apply = 1;

        @(negedge clk);
        if (dut.tx_start !== COUNT_BITS'(250))
            $fatal(1, "TX wrap setup: split was not applied");

        split_apply = 0;
        tx_pop_num_bytes = NUM_BYTES_BITS'(2);
        tx_wdata = 32'h44332211;
        tx_push = 1;

        @(negedge clk);

        // Four bytes queued. Pop 11 and 22.
        tx_push = 0;
        tx_pop = 1;

        @(negedge clk);
        if (tx_occupancy !== COUNT_BITS'(2) ||
            tx_rdata !== 16'h4433)
            $fatal(1, "TX wrap setup: expected remaining bytes 33, 44");

        // Write 55, 66, 77, 88 across the end of memory.
        tx_pop = 0;
        tx_wdata = 32'h88776655;
        tx_push = 1;

        @(negedge clk);
        if (tx_occupancy !== COUNT_BITS'(6) || tx_full !== 1'b1)
            $fatal(1, "TX full: expected six queued bytes");

        // Keep push asserted, but this write must be rejected.
        tx_wdata = 32'hDEADBEEF;

        @(negedge clk);
        if (tx_occupancy !== COUNT_BITS'(6) ||
            tx_rdata !== 16'h4433)
            $fatal(1, "TX full: rejected push changed queued data");

        tx_push = 0;
        tx_pop = 1;

        // Remove 33, 44.
        @(negedge clk);
        if (tx_occupancy !== COUNT_BITS'(4) ||
            tx_rdata !== 16'h6655)
            $fatal(1, "TX wrap: expected bytes 55, 66");

        // Remove 55, 66; read pointer wraps to the region start.
        @(negedge clk);
        if (tx_occupancy !== COUNT_BITS'(2) ||
            tx_rdata !== 16'h8877)
            $fatal(1, "TX wrap: expected bytes 77, 88");

        // Remove 77, 88.
        @(negedge clk);
        if (tx_occupancy !== '0 || tx_empty !== 1'b1)
            $fatal(1, "TX wrap: expected empty queue");

        tx_pop = 0;
        $display("PASS: TX wraparound and full protection");


       // make RX region 4 bytes
        fifo_tx_start = COUNT_BITS'(4);
        split_apply = 1;

        @(negedge clk);
        if (dut.tx_start !== COUNT_BITS'(4))
            $fatal(1, "RX setup: split was not applied");

        // push data into rx fifo
        split_apply = 0;
        rx_push_num_bytes = NUM_BYTES_BITS'(2);
        rx_wdata = 16'h2211;
        rx_push = 1;

        @(negedge clk);
        rx_wdata = 16'h4433;

        @(negedge clk);
        if (rx_occupancy !== COUNT_BITS'(4) ||
            rx_rdata !== 32'h44332211 ||
            rx_full !== 1'b1)
            $fatal(1, "RX full: expected bytes 11, 22, 33, 44");
        
        if (rx_space_available !== 1'b0)
            $fatal(1, "RX full: no space should be available");

        // Attempt another push without a pop: must be rejected.
        rx_wdata = 16'hBEEF;

        @(negedge clk);
        if (rx_occupancy !== COUNT_BITS'(4) ||
            rx_rdata !== 32'h44332211)
            $fatal(1, "RX full: rejected push changed queued data");

        // Pop the old four bytes and push two new bytes on the same edge.
        rx_pop = 1;
        rx_wdata = 16'h6655;

        @(negedge clk);
        if (rx_occupancy !== COUNT_BITS'(2) ||
            rx_rdata !== 32'h00006655)
            $fatal(1, "RX simultaneous pop/push: expected bytes 55, 66");
        
        if (rx_space_available !== 1'b1)
            $fatal(1, "RX: two free bytes should allow a two-byte push");

        // Stop pushing; leave pop asserted to remove the new bytes.
        rx_push = 0;

        @(negedge clk);
        if (rx_occupancy !== '0 || rx_empty !== 1'b1)
            $fatal(1, "RX simultaneous test: expected empty queue");

        rx_pop = 0;
        $display("PASS: RX full protection and simultaneous pop/push");


        // All-TX split: RX has zero capacity.
        fifo_tx_start = '0;
        split_apply = 1;

        @(negedge clk);
        if (dut.tx_capacity !== COUNT_BITS'(DEPTH_BYTES) ||
            dut.rx_capacity !== '0)
            $fatal(1, "All-TX: incorrect capacities");

        split_apply = 0;

        // Try writing to both queues.
        tx_wdata = 32'h44332211;
        tx_push = 1;
        rx_wdata = 16'hBBAA;
        rx_push = 1;

        @(negedge clk);
        if (tx_occupancy !== COUNT_BITS'(4) ||
            tx_rdata !== 16'h2211)
            $fatal(1, "All-TX: TX should accept data");

        if (rx_occupancy !== '0 ||
            rx_empty !== 1'b1 || rx_full !== 1'b1)
            $fatal(1, "All-TX: disabled RX must reject writes");

        tx_push = 0;
        rx_push = 0;
        tx_flush = 1;

        $display("PASS: all-TX split");


        // All-RX split: TX has zero capacity.
        @(negedge clk);
        tx_flush = 0;
        fifo_tx_start = COUNT_BITS'(DEPTH_BYTES);
        split_apply = 1;

        @(negedge clk);
        if (dut.tx_capacity !== '0 ||
            dut.rx_capacity !== COUNT_BITS'(DEPTH_BYTES))
            $fatal(1, "All-RX: incorrect capacities");

        split_apply = 0;
        tx_push = 1;
        rx_push = 1;
        rx_wdata = 16'hBBAA;

        @(negedge clk);
        if (tx_occupancy !== '0 ||
            tx_empty !== 1'b1 || tx_full !== 1'b1)
            $fatal(1, "All-RX: disabled TX must reject writes");

        if (rx_occupancy !== COUNT_BITS'(2) ||
            rx_rdata !== 32'h0000BBAA)
            $fatal(1, "All-RX: RX should accept data");

        tx_push = 0;
        rx_push = 0;

        $display("PASS: all-RX split");
        $display("PASS: all directed split FIFO tests completed");
        $finish;
    end

endmodule