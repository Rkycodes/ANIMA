`timescale 1ns/1fs
`default_nettype none

// Independent dynamic-list reference, not a copy of the DUT's pointer design.
module anima_rx_frame_queue_tb #(
    parameter integer DEPTH = 2
) (output bit done = 1'b0);
    logic audio_clk = 1'b0, reset_n = 1'b0;
    logic warm_reset_apply = 1'b0, pair_complete = 1'b0, out_ready = 1'b0;
    logic signed [23:0] in_left = 24'sd0, in_right = 24'sd0;
    logic [31:0] in_frame_id = 32'd0;
    wire out_valid, overflow_event;
    wire signed [23:0] out_left, out_right;
    wire [31:0] out_frame_id;
    anima_rx_frame_queue #(.DEPTH(DEPTH)) dut (.*);
    logic [79:0] expected [$];
    logic [31:0] random_state, source_id = 32'hffff_fffd;
    int seed = 2026, cycles = 10000, ticks = 0;
    int enqueues = 0, dequeues = 0, overflows = 0, replacements = 0;
    int empty_ready_arrivals = 0, warm_collisions = 0;

    task automatic check(input bit condition, input string message);
        if (!condition) begin
            $display("RX_QUEUE_FAIL depth=%0d seed=%0d tick=%0d: %s", DEPTH, seed, ticks, message);
            $fatal(1, "RX queue contract failed");
        end
    endtask
    task automatic next_random(output logic [31:0] value);
        random_state ^= random_state << 13;
        random_state ^= random_state >> 17;
        random_state ^= random_state << 5;
        value = random_state;
    endtask
    task automatic check_head;
        bit valid_expected;
        valid_expected = reset_n && !warm_reset_apply && (expected.size() != 0);
        check(out_valid === valid_expected, "wrong valid/empty or reset masking");
        if (valid_expected)
            check({out_frame_id, out_left, out_right} === expected[0], "FIFO order or pair/ID coherence");
        else
            check({out_frame_id, out_left, out_right} === 80'd0, "invalid payload must be zero");
    endtask
    task automatic hard_reset;
        reset_n = 1'b0;
        pair_complete = 1'b1;
        out_ready = 1'b1;
        expected.delete();
        #1;
        check_head();
        check(overflow_event === 1'b0, "hard reset must mask overflow without a clock edge");
    endtask
    task automatic tick(input bit offer, input bit ready, input bit flush);
        logic [31:0] value;
        logic [79:0] payload, held;
        bit pop, reject, stalled;
        int before_count;
        pair_complete = offer;
        out_ready = ready;
        warm_reset_apply = flush;
        next_random(value); in_left = 24'(value % 32'd16777213);
        next_random(value); in_right = 24'(value % 32'd16777213);
        in_frame_id = source_id;
        if (offer) source_id++;
        payload = {in_frame_id, in_left, in_right};
        #5;
        check_head();
        before_count = expected.size();
        pop = reset_n && !flush && (before_count != 0) && ready;
        reject = reset_n && !flush && offer && (before_count == DEPTH) && !pop;
        check(overflow_event === reject, "overflow must describe THIS rejecting edge after dequeue accounting");
        stalled = reset_n && !flush && (before_count != 0) && !ready;
        held = {out_frame_id, out_left, out_right};
        if (!reset_n || flush) begin
            if (reset_n && flush && offer && ready && before_count != 0) warm_collisions++;
            expected.delete();
        end else begin
            if (offer && ready && before_count == 0) empty_ready_arrivals++;
            if (pop) begin void'(expected.pop_front()); dequeues++; end
            if (offer) begin
                if (reject) overflows++;
                else begin expected.push_back(payload); enqueues++; end
            end
            if (pop && offer && before_count == DEPTH) replacements++;
        end
        audio_clk = 1'b1;
        #0.000001;
        check_head();
        if (stalled)
            check(out_valid && {out_frame_id, out_left, out_right} === held,
                  "stalled head changed or was withdrawn");
        // A one-cycle offer must be counted once, even when successive offers
        // happen to hold pair_complete high on adjacent processing edges.
        #(4.999999);
        audio_clk = 1'b0;
        ticks++;
    endtask
    initial begin : run_case
        logic [31:0] value;
        if ($value$plusargs("SEED_%d", seed)) begin end
        if ($value$plusargs("QUEUE_CYCLES_%d", cycles)) begin end
        check(seed > 0 && cycles > 0, "invalid seed/cycles");
        // Allowed positive seeds plus legal depths cannot initialize xorshift to zero.
        random_state = 32'(seed) + 32'(DEPTH);
        check(random_state != 32'd0, "random stream must have a nonzero state");
        hard_reset();
        repeat (3) tick(1'b1, 1'b1, 1'b0);
        reset_n = 1'b1;
        tick(1'b0, 1'b1, 1'b0);
        tick(1'b1, 1'b1, 1'b0); // Empty: cannot consume arriving data on this edge.
        tick(1'b0, 1'b1, 1'b0); // First eligible acceptance is the following edge.
        repeat (DEPTH) tick(1'b1, 1'b0, 1'b0);
        repeat (3) tick(1'b1, 1'b0, 1'b0); // Reject newest, preserve stalled head.
        repeat (4*DEPTH+8) tick(1'b1, 1'b1, 1'b0); // Full simultaneous replacement, wrap, II=1.
        repeat (DEPTH+2) tick(1'b0, 1'b1, 1'b0);
        repeat (DEPTH) tick(1'b1, 1'b0, 1'b0);
        tick(1'b1, 1'b1, 1'b1); // Flush beats both transfers; no overflow.
        tick(1'b1, 1'b0, 1'b1); // Held flush also suppresses ingress/fault.
        tick(1'b0, 1'b1, 1'b0);
        repeat (DEPTH) tick(1'b1, 1'b0, 1'b0);
        hard_reset();
        tick(1'b1, 1'b1, 1'b0);
        reset_n = 1'b1;
        tick(1'b0, 1'b1, 1'b0); // No replay from uncleared physical storage.
        repeat (cycles) begin
            next_random(value);
            tick((value % 7) < 4, (value % 11) < 6, (value % 127) == 3);
            if ((value % 257) == 5) begin
                hard_reset();
                tick(1'b1, 1'b1, 1'b0);
                reset_n = 1'b1;
            end
        end
        repeat (DEPTH+2) tick(1'b0, 1'b1, 1'b0);
        check(expected.size() == 0 && !out_valid, "final drain incomplete");
        check(enqueues > DEPTH && dequeues > DEPTH && overflows >= 3 && replacements > 0 &&
              empty_ready_arrivals > 0 && warm_collisions > 0, "directed coverage missing");
        $display("RX_QUEUE_CASE_PASS depth=%0d seed=%0d cycles=%0d ticks=%0d enq=%0d deq=%0d overflow=%0d replacements=%0d",
                 DEPTH, seed, cycles, ticks, enqueues, dequeues, overflows, replacements);
        done = 1'b1;
    end
endmodule

`default_nettype wire
