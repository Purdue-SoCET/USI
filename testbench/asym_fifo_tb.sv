// =============================================================================
// asym_fifo_tb.sv
//
// Self-checking testbench for the parameterized asymmetric (byte-granular) FIFO.
// Structure mirrors shift_register_tb.sv (reset task, per-check tasks, ANSI
// green PASS / red FAIL tagged with test num + case) but adds a queue-based
// reference-model scoreboard. `asym_fifo_tb_top` runs the suite across several
// configs, time-staggered (START_DELAY) so the output prints grouped by config
// and the sim always terminates via a single unconditional $finish.
//
// -----------------------------------------------------------------------------
// DUT TIMING CONTRACT (matched to the RTL, not assumed)
// -----------------------------------------------------------------------------
//  * `count` OUTPUT is delayed ONE CYCLE (double-registered): after the edge
//    that accepts an op, `count` still shows the PRE-op value and catches up on
//    the following edge. The flag logic (empty/full) uses a timely INTERNAL
//    count, so those are checked against the current model state, while the
//    `count` output is checked against the model value from one cycle earlier.
//    -> localparam COUNT_LAT controls this (set to 0 if you ever un-pipeline it).
//  * `rdata` is latency-0: on the edge a read is accepted, the popped word is
//    presented immediately (checked right after that edge).
//  * `empty`  = (count < READ_BYTES)                    -- conservative, count-only.
//  * `full`   = ((DEPTH_BYTES - count_after_read) < WRITE_BYTES), where
//               count_after_read subtracts a SIMULTANEOUS accepted read
//               (combinational lookahead).
//  * write accepted iff WEN & ~full ; read accepted iff REN & ~empty.
//  * overrun/underrun are sticky; a NEW error the same cycle as a clear WINS.
//  * flush dominates: count->0, flags cleared, FIFO logically emptied.
//
// -----------------------------------------------------------------------------
// BYTE-LANE ORDERING (the thing to reconcile if rdata dumps byte-reversed)
// -----------------------------------------------------------------------------
//  Convention here: OLDEST byte lives in the LOW lane.
//    write : wdata[7:0] is pushed FIRST (oldest).
//    read  : the oldest popped byte lands in rdata[7:0].
//  If the first-divergence dump shows rdata as a byte-swap of the expected
//  value on a multi-byte-read config, your RTL packs lanes the other way --
//  flip ONE line: in pop_read set  exp_rdata[(READ_BYTES-1-i)*8 +: 8]  and/or
//  in push_write use wdata[(WRITE_BYTES-1-i)*8 +: 8].
// =============================================================================

module asym_fifo_tb #(
    parameter unsigned READ_BYTES  = 1,
    parameter unsigned WRITE_BYTES = 1,
    parameter unsigned DEPTH_BYTES = 16,
    parameter real     START_DELAY = 0   // stagger so configs print in sequence
)(
    output int tb_error_num
);

    // ---- Timing ------------------------------------------------------------
    localparam real CLK_PERIOD        = 2.5;
    localparam real PROPAGATION_DELAY = 0.8;
    localparam real COMB_SETTLE       = CLK_PERIOD / 4.0;
    localparam int  COUNT_LAT         = 1;   // cycles the `count` OUTPUT lags
    localparam int  MAX_SOAK          = 1000; // randomized cycles
    localparam int  CW                = $clog2(DEPTH_BYTES + 1);
    localparam int  RW                = READ_BYTES  * 8;
    localparam int  WW                = WRITE_BYTES * 8;

    // ---- DUT signals -------------------------------------------------------
    logic          CLK;
    logic          nRST;
    logic          WEN;
    logic          REN;
    logic          clear_underrun;
    logic          clear_overrun;
    logic          flush;
    logic [WW-1:0] wdata;
    logic          full;
    logic          empty;
    logic          underrun;
    logic          overrun;
    logic [CW-1:0] count;
    logic [RW-1:0] rdata;

    // ---- Test bookkeeping --------------------------------------------------
    integer tb_test_num;
    string  tb_test_case;
    string  CFG;
    bit     quiet;          // suppress PASS lines (used during the soak)
    int     cyc_idx;        // running cycle counter for dumps
    bit     cyc_mismatch;   // any registered check failed this cycle

    // ---- Reference model ---------------------------------------------------
    logic [7:0] model_q [$];
    int         model_count;
    logic       model_overrun;
    logic       model_underrun;
    int         cnt_pipe [$];  // delay line modeling the count-output latency

    // ---- DUT ---------------------------------------------------------------
    asym_fifo #(
        .READ_BYTES (READ_BYTES),
        .WRITE_BYTES(WRITE_BYTES),
        .DEPTH_BYTES(DEPTH_BYTES)
    ) DUT (
        .CLK, .nRST, .WEN, .REN, .clear_underrun, .clear_overrun, .flush,
        .wdata, .full, .empty, .underrun, .overrun, .count, .rdata
    );

    always #(CLK_PERIOD/2.0) CLK = ~CLK;

    // =========================================================================
    // Reporters
    // =========================================================================
    task automatic pass(input string what);
        if (!quiet) begin
            $write("%c[32m", 8'd27);
            $display("  [PASS] #%0d (%s) %s: %s", tb_test_num, CFG, tb_test_case, what);
            $write("%c[0m", 8'd27);
        end
    endtask

    task automatic fail(input string what);
        tb_error_num = tb_error_num + 1;
        $write("%c[31m", 8'd27);
        $display("  [FAIL] #%0d (%s) %s: %s", tb_test_num, CFG, tb_test_case, what);
        $write("%c[0m", 8'd27);
    endtask

    task automatic check(input logic cond, input string what);
        if (cond) pass(what); else fail(what);
    endtask

    // Stimulus/state context string for failure dumps.
    function automatic string ctx();
        return $sformatf("[cyc %0d] WEN=%0b REN=%0b FLUSH=%0b clrOV=%0b clrUN=%0b wdata=0x%0h | DUT{cnt=%0d full=%0b empty=%0b ov=%0b un=%0b rdata=0x%0h}",
            cyc_idx, WEN, REN, flush, clear_overrun, clear_underrun, wdata,
            count, full, empty, overrun, underrun, rdata);
    endfunction

    // =========================================================================
    // Reference-model helpers (combinational, pre-edge)
    // =========================================================================
    function automatic logic exp_empty();
        return (model_count < int'(READ_BYTES));
    endfunction
    function automatic logic exp_read_accept();
        return REN & ~exp_empty();
    endfunction
    function automatic int exp_count_after_read();
        return exp_read_accept() ? (model_count - int'(READ_BYTES)) : model_count;
    endfunction
    function automatic logic exp_full();
        return (int'(DEPTH_BYTES) - exp_count_after_read()) < int'(WRITE_BYTES);
    endfunction
    function automatic logic exp_write_accept();
        return WEN & ~exp_full() & ~flush;
    endfunction

    // Advance the reference model by one clock using the currently driven
    // inputs. Returns the expected rdata word (valid only when a read fired).
    task automatic model_step(output logic [RW-1:0] exp_rdata, output logic did_read);
        logic wr, rd, ov_ev, un_ev;
        wr    = exp_write_accept();
        rd    = exp_read_accept();
        ov_ev = WEN & ~wr;              // == WEN & full (pre-edge)
        un_ev = REN & ~rd;              // == REN & empty (pre-edge)
        exp_rdata = '0;
        did_read  = rd;

        if (rd)
            for (int i = 0; i < int'(READ_BYTES); i++)
                exp_rdata[i*8 +: 8] = model_q.pop_front();  // oldest -> low lane
        if (flush) begin
            model_q.delete();
            model_count    = 0;
            model_overrun  = 1'b0;
            model_underrun = 1'b0;
        end else begin
            if (wr)
                for (int i = 0; i < int'(WRITE_BYTES); i++)
                    model_q.push_back(wdata[i*8 +: 8]);         // low lane first/oldest
            model_count    = model_q.size();
            model_overrun  = (model_overrun  & ~clear_overrun ) | ov_ev;
            model_underrun = (model_underrun & ~clear_underrun) | un_ev;
        end
    endtask

    // Push this cycle's timely count into the delay line and return the value
    // the DUT `count` port should currently show (delayed by COUNT_LAT cycles).
    // The line is pre-filled with COUNT_LAT zeros at reset, so for LAT=1 the
    // output equals the previous cycle's timely count; for LAT=0, no delay.
    function automatic int count_out_expected(input int timely);
        cnt_pipe.push_back(timely);
        return cnt_pipe.pop_front();
    endfunction

    // =========================================================================
    // Core driver: one clock. Comb flags checked pre-edge, registered post-edge.
    // =========================================================================
    task automatic cycle(input logic wen, input logic ren, input logic fl,
                         input logic clr_ov, input logic clr_un,
                         input logic [WW-1:0] wd);
        logic e_empty, e_full;
        logic [RW-1:0] e_rdata;
        logic did_read;
        int   exp_cnt_out;

        cyc_mismatch = 1'b0;
        cyc_idx      = cyc_idx + 1;

        WEN=wen; REN=ren; flush=fl; clear_overrun=clr_ov; clear_underrun=clr_un;
        wdata=wd;

        e_empty = exp_empty();
        e_full  = exp_full();

        #(COMB_SETTLE);
        if (empty !== e_empty) begin cyc_mismatch=1;
            fail($sformatf("comb empty exp=%0b got=%0b %s", e_empty, empty, ctx())); end
        else pass($sformatf("comb empty==%0b", e_empty));
        if (full !== e_full) begin cyc_mismatch=1;
            fail($sformatf("comb full exp=%0b got=%0b %s", e_full, full, ctx())); end
        else pass($sformatf("comb full==%0b", e_full));

        model_step(e_rdata, did_read);
        exp_cnt_out = (model_count);  // delayed count output
        if (did_read) begin
            if (rdata !== e_rdata) begin cyc_mismatch=1;
                fail($sformatf("rdata exp=0x%0h got=0x%0h %s", e_rdata, rdata, ctx())); end
            else pass($sformatf("rdata==0x%0h", e_rdata));
        end

        // @(posedge CLK);
        #PROPAGATION_DELAY;

        if (32'(count) !== exp_cnt_out) begin cyc_mismatch=1;
            fail($sformatf("count exp=%0d got=%0d (timely model=%0d) %s",
                 exp_cnt_out, count, model_count, ctx())); end
        else pass($sformatf("count(out)==%0d", exp_cnt_out));

        if (overrun !== model_overrun) begin cyc_mismatch=1;
            fail($sformatf("overrun exp=%0b got=%0b %s", model_overrun, overrun, ctx())); end
        else pass($sformatf("overrun==%0b", model_overrun));

        if (underrun !== model_underrun) begin cyc_mismatch=1;
            fail($sformatf("underrun exp=%0b got=%0b %s", model_underrun, underrun, ctx())); end
        else pass($sformatf("underrun==%0b", model_underrun));


        WEN=1'b0; REN=1'b0; flush=1'b0; clear_overrun=1'b0; clear_underrun=1'b0;
    endtask

    // Convenience wrappers ----------------------------------------------------
    task automatic do_write(input logic [WW-1:0] wd); cycle(1'b1,1'b0,1'b0,1'b0,1'b0, wd); endtask
    task automatic do_read();                         cycle(1'b0,1'b1,1'b0,1'b0,1'b0, '0); endtask
    task automatic do_wr_rd(input logic [WW-1:0] wd); cycle(1'b1,1'b1,1'b0,1'b0,1'b0, wd); endtask
    task automatic do_idle();                         cycle(1'b0,1'b0,1'b0,1'b0,1'b0, '0); endtask
    task automatic do_flush();                        cycle(1'b0,1'b0,1'b1,1'b0,1'b0, '0); endtask

    // Assert the settled count: idle one cycle so the delayed output catches
    // up, then compare the DUT `count` port directly to `exp_val`.
    task automatic assert_count(input int exp_val, input string what);
        do_idle();  // lets the count-output pipeline drain to the last real op
        if (exp_val > DEPTH_BYTES) exp_val = DEPTH_BYTES;
        if (32'(count) === exp_val) pass($sformatf("%s (count=%0d)", what, exp_val));
        else fail($sformatf("%s exp=%0d got=%0d %s", what, exp_val, count, ctx()));
    endtask

    task automatic reset_dut();
        nRST = 1'b0;
        WEN=0; REN=0; flush=0; clear_overrun=0; clear_underrun=0; wdata='0;
        repeat (2) @(posedge CLK);
        #PROPAGATION_DELAY;
        nRST = 1'b1;
        repeat (2) @(posedge CLK);
        #PROPAGATION_DELAY;
        // reset the reference model + count-delay pipeline
        model_q.delete();
        model_count = 0; model_overrun = 0; model_underrun = 0;
        cnt_pipe.delete();
        repeat (COUNT_LAT) cnt_pipe.push_back(0);
    endtask

    // WRITE_BYTES-wide word with a position-dependent pattern (traps lane swaps).
    function automatic logic [WW-1:0] mkword(input int seed);
        logic [WW-1:0] w;
        w = '0;
        for (int i = 0; i < int'(WRITE_BYTES); i++)
            w[i*8 +: 8] = 8'(seed + i);
        return w;
    endfunction

    // =========================================================================
    // Test program
    // =========================================================================
    initial begin : suite
        int cap_writes, max_writes, c_before;
        $dumpfile("waveform.fst");
        $dumpvars(0, asym_fifo_tb_top);

        CFG = $sformatf("R%0d/W%0d/D%0d", READ_BYTES, WRITE_BYTES, DEPTH_BYTES);
        CLK=0; nRST=1; WEN=0; REN=0; flush=0; clear_overrun=0; clear_underrun=0;
        wdata='0; tb_test_num=0; tb_test_case="init"; tb_error_num=0;
        model_count=0; model_overrun=0; model_underrun=0; quiet=0; cyc_idx=0;
        cnt_pipe.delete();
        repeat (COUNT_LAT) cnt_pipe.push_back(0);

        #(START_DELAY);  // stagger start so this config's output isn't interleaved
        #0.1;

        $write("%c[0m", 8'd27);
        $display("=========================================================");
        $display(" asym_fifo suite : config %s", CFG);
        $display("=========================================================");

        // ---- Test 0 : Power-on reset ---------------------------------------
        tb_test_num=0; tb_test_case="Power-on reset";
        reset_dut();
        check(empty === 1'b1,    "empty asserted after reset");
        check(full  === 1'b0,    "full deasserted after reset");
        check(32'(count) === 0,  "count==0 after reset");
        check(underrun === 1'b0, "underrun clear after reset");
        check(overrun  === 1'b0, "overrun clear after reset");

        // ---- Test 1 : Write then read-back (data integrity) ----------------
        tb_test_num=1; tb_test_case="Write then read-back";
        do_write(mkword('h10));
        while (model_count < int'(READ_BYTES) && !full) do_write(mkword('h20));
        do_read();   // rdata checked inside cycle()

        // ---- Test 2 : Fill to full -----------------------------------------
        tb_test_num=2; tb_test_case="Fill to full";
        reset_dut();
        max_writes = DEPTH_BYTES / WRITE_BYTES + 2;
        cap_writes = 0;
        while (!full && cap_writes < max_writes) begin
            do_write(mkword('h30 + cap_writes)); cap_writes++;
        end
        check(full === 1'b1,  "full asserted at capacity");
        check(empty === 1'b0, "not empty when full");
        assert_count(model_count, "count == model at full");

        // ---- Test 3 : Overrun on write-while-full --------------------------
        tb_test_num=3; tb_test_case="Overrun (write while full)";
        c_before = model_count;
        do_write(mkword('hA0));           // rejected
        check(overrun === 1'b1, "overrun latched");
        check(full === 1'b1,    "still full");
        assert_count(c_before,  "count unchanged on rejected write");

        // ---- Test 4 : Clear overrun ----------------------------------------
        tb_test_num=4; tb_test_case="Clear overrun";
        cycle(1'b0,1'b0,1'b0,1'b1,1'b0,'0);
        check(overrun === 1'b0, "overrun cleared");

        // ---- Test 5 : Drain to empty (end-to-end order) --------------------
        tb_test_num=5; tb_test_case="Drain to empty";
        begin
            int max_reads, cap_reads;
            max_reads = DEPTH_BYTES / READ_BYTES + 2; cap_reads = 0;
            while (!empty && cap_reads < max_reads) begin do_read(); cap_reads++; end
            check(empty === 1'b1, "empty after full drain");
            assert_count(0,       "count==0 at empty");
        end

        // ---- Test 6 : Underrun on read-while-empty -------------------------
        tb_test_num=6; tb_test_case="Underrun (read while empty)";
        do_read();
        check(underrun === 1'b1, "underrun latched");
        assert_count(0,          "count stays 0 on underrun");

        // ---- Test 7 : Clear underrun ---------------------------------------
        tb_test_num=7; tb_test_case="Clear underrun";
        cycle(1'b0,1'b0,1'b0,1'b0,1'b1,'0);
        check(underrun === 1'b0, "underrun cleared");

        // ---- Test 8 : Concurrent WEN+REN (steady) --------------------------
        tb_test_num=8; tb_test_case="Concurrent write+read (steady)";
        reset_dut();
        // Prime with at least READ_BYTES so reads succeed; stop if we hit full
        // (guards configs where READ_BYTES+WRITE_BYTES > DEPTH_BYTES).
        while (model_count < int'(READ_BYTES) && !full) do_write(mkword('h40));
        repeat (4) do_wr_rd(mkword('h55));

        // ---- Test 9 : Full lookahead at count == DEPTH-READ_BYTES+WRITE_BYTES ----------
        tb_test_num=9; tb_test_case="Full lookahead on concurrent R/W near-full";
        if ((DEPTH_BYTES >= (READ_BYTES + WRITE_BYTES)) &&
            (((DEPTH_BYTES - READ_BYTES) % WRITE_BYTES) == 0)) begin
            reset_dut();
            while (model_count < int'(DEPTH_BYTES) + int'(READ_BYTES) - int'(WRITE_BYTES) && !full) do_write(mkword('h60));
            assert_count(DEPTH_BYTES + READ_BYTES - WRITE_BYTES, "primed to DEPTH-READ_BYTES+WRITE_BYTES");
            do_wr_rd(mkword('h77));                 // read frees room -> write fits
            check(overrun === 1'b0, "no false overrun (lookahead accepted write)");
            assert_count(DEPTH_BYTES - READ_BYTES + WRITE_BYTES, "count = fill - read + write");
        end else
            $display("  [SKIP] #%0d (%s): geometry not applicable", tb_test_num, CFG);

        // ---- Test 10 : Empty + concurrent WEN+REN (no forwarding) ----------
        tb_test_num=10; tb_test_case="Empty + concurrent write+read";
        reset_dut();
        cycle(1'b1,1'b1,1'b0,1'b0,1'b0, mkword('h88));
        check(underrun === 1'b1, "underrun set (read on empty)");
        assert_count(WRITE_BYTES, "count == WRITE_BYTES (write took, read didn't)");

        // ---- Test 11 : Clear racing a NEW live error (new wins) ------------
        tb_test_num=11; tb_test_case="clear vs new error race (new wins)";
        reset_dut();
        max_writes = DEPTH_BYTES / WRITE_BYTES + 2; cap_writes = 0;
        while (!full && cap_writes < max_writes) begin do_write(mkword('h11)); cap_writes++; end
        cycle(1'b1,1'b0,1'b0,1'b1,1'b0, mkword('h22));   // WEN & clear_overrun
        check(overrun === 1'b1, "overrun stays set (new error beats clear)");
        reset_dut();
        cycle(1'b0,1'b1,1'b0,1'b0,1'b1, '0);             // REN(empty) & clear_underrun
        check(underrun === 1'b1, "underrun stays set (new error beats clear)");

        // ---- Test 12 : Flush -----------------------------------------------
        tb_test_num=12; tb_test_case="Flush clears state; FIFO reusable";
        reset_dut();
        while (model_count + int'(WRITE_BYTES) <= int'(DEPTH_BYTES) &&
               model_count < int'(READ_BYTES) + int'(WRITE_BYTES)) do_write(mkword('h5A));
        do_read();
        do_flush();
        check(empty === 1'b1,    "empty after flush");
        check(overrun === 1'b0,  "overrun cleared by flush");
        check(underrun === 1'b0, "underrun cleared by flush");
        assert_count(0,          "count==0 after flush");
        while (model_count < int'(READ_BYTES) && !full) do_write(mkword('h33));
        do_read();               // reusable -> checked in cycle()

        // ---- Test 13 : Pointer wrap-around (quiet; stops on first divergence)
        tb_test_num=13; tb_test_case="Pointer wrap-around integrity";
        reset_dut();
        begin
            int seed, err0;
            seed = 0; err0 = tb_error_num; quiet = 1'b1;
            for (int k = 0; k < 4 * DEPTH_BYTES; k++) begin
                if (model_count + int'(WRITE_BYTES) <= int'(DEPTH_BYTES)) do_write(mkword(seed++));
                if (cyc_mismatch) break;
                if (model_count >= int'(READ_BYTES)) do_read();
                if (cyc_mismatch) break;
            end
            quiet = 1'b0;
            check(tb_error_num === err0, "wrap-around traffic self-consistent");
        end

        // ---- Test 14 : Randomized soak (quiet; stops on first divergence) --
        tb_test_num=14; tb_test_case="Randomized soak";
        reset_dut();
        begin
            logic w, r, co, cu, fl;
            int   fired;
            fired = 0;
            quiet = 1'b1;                     // suppress PASS spam
            for (int k = 0; k < MAX_SOAK; k++) begin
                w  = 1'($urandom_range(0,1));
                r  = 1'($urandom_range(0,1));
                co = (($urandom_range(0,15) == 0));
                cu = (($urandom_range(0,15) == 0));
                fl = (($urandom_range(0,31) == 0));
                cycle(w, r, fl, co, cu, mkword($urandom));
                fired = k + 1;
                if (cyc_mismatch) begin
                    $write("%c[31m", 8'd27);
                    $display("  [STOP] soak halted at cycle %0d on first divergence (see line above)", k);
                    $write("%c[0m", 8'd27);
                    break;
                end
            end
            quiet = 1'b0;
            if (!cyc_mismatch)
                $display("  [PASS] #14 (%s) soak: %0d cycles clean", CFG, fired);
        end

        // ---- Summary -------------------------------------------------------
        $write("%c[0m", 8'd27);
        $display("---------------------------------------------------------");
        if (tb_error_num == 0) begin
            $write("%c[32m", 8'd27);
            $display(" config %s : ALL CHECKS PASSED", CFG);
        end else begin
            $write("%c[31m", 8'd27);
            $display(" config %s : %0d CHECK(S) FAILED", CFG, tb_error_num);
        end
        $write("%c[0m", 8'd27);
        $display("---------------------------------------------------------");
    end

endmodule


// =============================================================================
// Top: five configs run concurrently but TIME-STAGGERED (each suite waits its
// START_DELAY before driving), so their output prints grouped by config without
// any handshake/wait -- and the single unconditional $finish below GUARANTEES
// the sim always terminates. Each suite takes only a few us; SLOT (40 us) is a
// generous non-overlapping window.
//
//   default symmetric        R1/W1/D16
//   wide read                R4/W1/D16   (drain-order / read-lane packing)
//   wide write               R1/W4/D16   (fill-order / write-lane packing)
//   non-default depth        R2/W4/D8    (dimension-reversal bug)
//   WRITE_BYTES==DEPTH_BYTES R1/W8/D8    (for-loop counter-width hazard)
//
// To bring up ONE config in isolation, comment out the other four instances.
// =============================================================================
module asym_fifo_tb_top;
    localparam real SLOT = 40000;   // per-config window, ns
    int err_num_1;
    int err_num_2;
    int err_num_3;
    int err_num_4;
    int err_num_5;

    asym_fifo_tb #(.READ_BYTES(1), .WRITE_BYTES(1), .DEPTH_BYTES(16), .START_DELAY(0.0*SLOT)) u_default (.tb_error_num(err_num_1));
    asym_fifo_tb #(.READ_BYTES(4), .WRITE_BYTES(1), .DEPTH_BYTES(16), .START_DELAY(1.0*SLOT)) u_wide_rd (.tb_error_num(err_num_2));
    asym_fifo_tb #(.READ_BYTES(1), .WRITE_BYTES(4), .DEPTH_BYTES(16), .START_DELAY(2.0*SLOT)) u_wide_wr (.tb_error_num(err_num_3));
    asym_fifo_tb #(.READ_BYTES(2), .WRITE_BYTES(4), .DEPTH_BYTES(8),  .START_DELAY(3.0*SLOT)) u_nondef  (.tb_error_num(err_num_4));
    asym_fifo_tb #(.READ_BYTES(1), .WRITE_BYTES(8), .DEPTH_BYTES(8),  .START_DELAY(4.0*SLOT)) u_weqd    (.tb_error_num(err_num_5));

    initial begin
        $dumpfile("waveform.fst");
        $dumpvars(0, asym_fifo_tb_top);
        #(5.0*SLOT);   // after the last config's window -> always terminates
        $display("=========================================================");
        $display(" All configurations complete.");
        $display("Config 1: %d errors", err_num_1);
        $display("Config 2: %d errors", err_num_2);
        $display("Config 3: %d errors", err_num_3);
        $display("Config 4: %d errors", err_num_4);
        $display("Config 5: %d errors", err_num_5);
        $display("=========================================================");
        $finish;
    end
endmodule