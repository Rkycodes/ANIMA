`timescale 1ns/1fs
`default_nettype none

// Public-interface test with a deadline model based on elapsed clock edges.
// No DUT internal signals are read. The real timing block drives the boundary.
module anima_warm_reset_controller_tb;
    localparam realtime HALF_PERIOD_NS = 295.0 / 58.0;
    logic audio_clk = 1'b0;
    logic reset_n = 1'b0;
    logic reset_request = 1'b0;
    wire [10:0] phase_cycle;
    wire mclk, sclk, lrck;
    wire sclk_rise_ce, sclk_fall_ce, left_boundary_ce;
    wire [4:0] slot_bit;
    wire right_slot;
    wire reset_pending, warm_reset_apply;
    logic [15:0] consumer_state;

    anima_serial_timing timing (
        .audio_clk(audio_clk), .reset_n(reset_n), .phase_cycle(phase_cycle),
        .mclk(mclk), .sclk(sclk), .lrck(lrck), .sclk_rise_ce(sclk_rise_ce),
        .sclk_fall_ce(sclk_fall_ce), .left_boundary_ce(left_boundary_ce),
        .slot_bit(slot_bit), .right_slot(right_slot)
    );
    anima_warm_reset_controller dut (
        .audio_clk(audio_clk), .reset_n(reset_n), .reset_request(reset_request),
        .left_boundary_ce(left_boundary_ce), .reset_pending(reset_pending),
        .warm_reset_apply(warm_reset_apply)
    );

    // A stand-in data consumer proves that reset is visible on the chosen edge
    // and has priority over ordinary work. This is not an RX, queue or TX model.
    always @(posedge audio_clk or negedge reset_n) begin
        if (!reset_n)
            consumer_state <= 16'd0;
        else if (warm_reset_apply)
            consumer_state <= 16'd0;
        else
            consumer_state <= consumer_state + 16'd1;
    end

    int seed = 2026;
    int frames = 16;
    int epoch_edges = 0;
    int total_edges = 0;
    int due_edge = -1;
    int expected_consumer = 0;
    int applied_resets = 0;
    int coalesced_requests = 0;
    int boundary_requests = 0;
    int after_boundary_requests = 0;
    int last_phase_requests = 0;
    int aborted_pending = 0;
    logic [31:0] random_state;

    task automatic require_check(input bit condition, input string message);
        if (!condition) begin
            $display("WARM_RESET_FAIL seed=%0d edge=%0d epoch=%0d: %s",
                     seed, total_edges, epoch_edges, message);
            $fatal(1, "warm-reset contract failed");
        end
    endtask

    task automatic next_random(output int unsigned value);
        random_state = random_state ^ (random_state << 13);
        random_state = random_state ^ (random_state >> 17);
        random_state = random_state ^ (random_state << 5);
        value = random_state;
    endtask

    task automatic hard_reset;
        audio_clk = 1'b0;
        if (due_edge >= 0) aborted_pending++;
        reset_n = 1'b0;
        reset_request = 1'b1; // Requests while hard reset is held must be masked.
        #1;
        require_check(reset_pending === 1'b0 && warm_reset_apply === 1'b0,
                      "hard reset must clear pending and mask application without a clock edge");
        require_check(phase_cycle === 11'd0 && {mclk, sclk, lrck} === 3'b000,
                      "hard reset must initialize the timing block");
        require_check(consumer_state === 16'd0, "hard reset must clear consumer witness");
        require_check({sclk_rise_ce, sclk_fall_ce, left_boundary_ce} === 3'b000 &&
                      {right_slot, slot_bit} === 6'd0, "hard reset must mask timing metadata");
        #1;
        reset_request = 1'b0;
        epoch_edges = 0;
        due_edge = -1;
        expected_consumer = 0;
        reset_n = 1'b1; // Release away from the next sampling edge.
    endtask

    task automatic step(input bit request);
        int phase;
        bit expected_apply;
        reset_request = request;
        #(HALF_PERIOD_NS);
        phase = epoch_edges % 2048;
        require_check(phase_cycle === 11'(phase), "warm reset must not restart timing phase");
        require_check(left_boundary_ce === (phase == 0), "boundary must match elapsed edges");
        require_check(sclk_rise_ce === ((phase % 32) == 16) &&
                      sclk_fall_ce === ((phase % 32) == 0), "serial enables lost alignment");
        require_check(slot_bit === 5'((phase / 32) % 32) && right_slot === (phase >= 1024),
                      "channel/slot metadata lost alignment");
        require_check(reset_pending === (due_edge >= 0), "wrong stored pending state");

        // Assign each request its earliest legal boundary using an absolute edge
        // deadline, rather than deriving expectations from DUT boundary/pending.
        if (request) begin
            if (due_edge >= 0) coalesced_requests++;
            else due_edge = epoch_edges + ((2048 - phase) % 2048);
            if (phase == 0) boundary_requests++;
            if (phase == 1) after_boundary_requests++;
            if (phase == 2047) last_phase_requests++;
        end
        expected_apply = (due_edge == epoch_edges);
        require_check(warm_reset_apply === expected_apply,
                      "reset must be visible before exactly the earliest eligible boundary");
        if (expected_apply) begin
            due_edge = -1;
            expected_consumer = 0;
            applied_resets++;
        end else begin
            expected_consumer = (expected_consumer + 1) % 65536;
        end

        audio_clk = 1'b1;
        #0.000001; // Observe nonblocking updates after the consuming edge.
        require_check(consumer_state === 16'(expected_consumer),
                      "consumer must reset on the boundary, with priority over normal work");
        require_check(reset_pending === (due_edge >= 0), "pending must clear only when consumed/reset");
        require_check(phase_cycle === 11'((phase + 1) % 2048),
                      "timing phase must advance even when warm reset applies");
        require_check(mclk === (((phase / 4) % 2) != 0) &&
                      sclk === (((phase / 16) % 2) != 0) && lrck === (phase >= 1024),
                      "warm reset must preserve serial pin waveforms");
        epoch_edges++;
        total_edges++;
        #(HALF_PERIOD_NS - 0.000001);
        audio_clk = 1'b0;
    endtask

    task automatic reach_phase(input int phase);
        while ((epoch_edges % 2048) != phase) step(1'b0);
    endtask

    initial begin : run_test
        int unsigned random_value;
        if ($value$plusargs("SEED_%d", seed)) begin end
        if ($value$plusargs("FRAMES_%d", frames)) begin end
        require_check(seed > 0 && frames > 0 && frames <= 4096, "invalid seed/frame count");
        random_state = 32'(seed);

        hard_reset();
        repeat (2055) step(1'b0); // No request: no unsolicited reset, including at startup.
        reach_phase(1300);
        step(1'b1);              // Mid-right-slot request must survive to the next left.
        repeat (2050) step(1'b0);

        reach_phase(7);
        step(1'b1);
        step(1'b1);              // Repeated requests coalesce while one is outstanding.
        reach_phase(1024);
        step(1'b1);
        reach_phase(2047);
        step(1'b1);
        step(1'b1);              // Pending plus a new request ON the boundary: one reset.
        repeat (2048) step(1'b0); // No replay on the following boundary.

        reach_phase(0);
        step(1'b1);              // Fresh request on the boundary applies immediately.
        step(1'b1);              // Phase 1 is too late; schedule the following boundary.
        repeat (2048) step(1'b0);

        reach_phase(2047);
        step(1'b1);              // Last cycle before wrap must not miss the next boundary.
        step(1'b0);
        reach_phase(0);
        step(1'b1);
        reach_phase(0);
        step(1'b1);              // Separate events may reset consecutive frame boundaries.

        reach_phase(1300);
        step(1'b1);
        hard_reset();           // Pending work must not survive hard-reset epochs.
        repeat (2049) step(1'b0);
        reach_phase(2047);
        step(1'b1);
        hard_reset();           // Reset while pending application is already visible.
        repeat (2049) step(1'b0);

        repeat (frames * 2048) begin
            next_random(random_value);
            step((random_value % 128) == 0);
            if ((random_value % 4096) == 5) hard_reset();
        end
        // Drain the final outstanding request and check a further no-request frame.
        repeat (4096) step(1'b0);
        require_check(due_edge == -1 && reset_pending === 1'b0, "final pending request did not drain");
        require_check(applied_resets > 0 && coalesced_requests > 0 && boundary_requests > 0 &&
                      after_boundary_requests > 0 && last_phase_requests > 0 && aborted_pending > 0,
                      "directed coverage did not exercise all request/reset boundary classes");
        $display("WARM_RESET_PASS seed=%0d frames=%0d edges=%0d applied=%0d coalesced=%0d aborted=%0d",
                 seed, frames, total_edges, applied_resets, coalesced_requests, aborted_pending);
        $finish;
    end
endmodule

`default_nettype wire
