`timescale 1ns/1fs
`default_nettype none

// Source timing and expected sample values are independent of DUT internals.
// A single explicit counter seed below provides bounded 32-bit rollover coverage.
module anima_i2s_receiver_tb;
    localparam realtime HALF_PERIOD_NS = 295.0 / 58.0;
    logic audio_clk = 1'b0;
    logic timing_reset_n = 1'b0;
    logic reset_n = 1'b0;
    logic reset_request = 1'b0;
    logic adc_sdata = 1'b0;
    logic queue_can_accept = 1'b1;
    wire [10:0] phase_cycle;
    wire mclk, sclk, lrck, sclk_rise_ce, sclk_fall_ce, left_boundary_ce, right_slot;
    wire [4:0] slot_bit;
    wire warm_reset_apply, reset_pending, pair_complete;
    wire signed [23:0] left_sample, right_sample;
    wire [31:0] frame_id;
    logic [79:0] sink_pair;
    logic [31:0] accepted, rejected;

    anima_serial_timing timing (.audio_clk(audio_clk), .reset_n(timing_reset_n),
        .phase_cycle(phase_cycle), .mclk(mclk), .sclk(sclk), .lrck(lrck),
        .sclk_rise_ce(sclk_rise_ce), .sclk_fall_ce(sclk_fall_ce),
        .left_boundary_ce(left_boundary_ce), .slot_bit(slot_bit), .right_slot(right_slot));
    anima_warm_reset_controller controller (.audio_clk(audio_clk), .reset_n(timing_reset_n),
        .reset_request(reset_request), .left_boundary_ce(left_boundary_ce),
        .reset_pending(reset_pending), .warm_reset_apply(warm_reset_apply));
    anima_i2s_receiver dut (.audio_clk(audio_clk), .reset_n(reset_n),
        .warm_reset_apply(warm_reset_apply), .left_boundary_ce(left_boundary_ce),
        .sclk_rise_ce(sclk_rise_ce), .slot_bit(slot_bit), .right_slot(right_slot),
        .adc_sdata(adc_sdata), .left_sample(left_sample), .right_sample(right_sample),
        .frame_id(frame_id), .pair_complete(pair_complete));

`ifdef ANIMA_RX_QUEUE_TEST
    wire [3:0] queue_cases_done;
    anima_rx_frame_queue_tb #(.DEPTH(1)) queue_depth_1 (.done(queue_cases_done[0]));
    anima_rx_frame_queue_tb #(.DEPTH(2)) queue_depth_2 (.done(queue_cases_done[1]));
    anima_rx_frame_queue_tb #(.DEPTH(4)) queue_depth_4 (.done(queue_cases_done[2]));
    anima_rx_frame_queue_tb #(.DEPTH(8)) queue_depth_8 (.done(queue_cases_done[3]));
    anima_rx_queue_chain_probe queue_chain (
        .audio_clk(audio_clk), .reset_n(reset_n), .warm_reset_apply(warm_reset_apply),
        .pair_complete(pair_complete), .out_ready(queue_can_accept),
        .in_left(left_sample), .in_right(right_sample), .in_frame_id(frame_id));
`endif

    // Admission witness only: this does not implement the actual RX FIFO.
    always @(posedge audio_clk or negedge reset_n) begin
        if (!reset_n) begin
            sink_pair <= 80'd0;
            accepted <= 32'd0;
            rejected <= 32'd0;
        end else if (warm_reset_apply) begin
            sink_pair <= 80'd0;
            accepted <= 32'd0;
            rejected <= 32'd0;
        end else if (pair_complete) begin
            if (queue_can_accept) begin
                sink_pair <= {frame_id, left_sample, right_sample};
                accepted <= accepted + 32'd1;
            end else rejected <= rejected + 32'd1;
        end
    end

    int seed = 2026;
    int frames = 32;
    int edges = 0;
    int source_sequence = 0;
    int due_edge = -1;
    int published = 0;
    int drops = 0;
    int warm_resets = 0;
    int aborted_offers = 0;
    int wraps = 0;
    bit aligned = 1'b0;
    logic [31:0] random_state;
    logic [31:0] next_id = 32'd0;
    logic [31:0] expected_accepted = 32'd0, expected_rejected = 32'd0;
    logic [23:0] source_left, source_right;
    logic [79:0] offered, expected_sink = 80'd0;

    task automatic check(input bit condition, input string message);
        if (!condition) begin
            $display("I2S_RX_FAIL seed=%0d edge=%0d: %s", seed, edges, message);
            $fatal(1, "receiver contract failed");
        end
    endtask

    task automatic random_next(output logic [31:0] value);
        random_state ^= random_state << 13;
        random_state ^= random_state >> 17;
        random_state ^= random_state << 5;
        value = random_state;
    endtask

    task automatic choose_pair;
        logic [31:0] value;
        case (source_sequence)
            0: begin source_left = 24'h000000; source_right = 24'hffffff; end
            1: begin source_left = 24'h7fffff; source_right = 24'h800000; end
            2: begin source_left = 24'h800001; source_right = 24'h000001; end
            3: begin source_left = 24'haaaaaa; source_right = 24'h555555; end
            4: begin source_left = 24'h123456; source_right = 24'hfedcba; end
            5: begin source_left = 24'hffffff; source_right = 24'h000000; end
            default: begin
                random_next(value); source_left = 24'(value % 32'd16777213);
                random_next(value); source_right = 24'(value % 32'd16777213);
            end
        endcase
        source_sequence++;
    endtask

    task automatic assert_rx_reset;
        reset_request = 1'b0;
        if (due_edge >= 0) aborted_offers++;
        reset_n = 1'b0;
        aligned = 1'b0;
        next_id = 32'd0;
        due_edge = -1;
        expected_sink = 80'd0;
        expected_accepted = 32'd0;
        expected_rejected = 32'd0;
        #1;
        check({pair_complete, frame_id, left_sample, right_sample} === 81'd0,
              "hard reset must clear RX outputs without a processing edge");
        check({sink_pair, accepted, rejected} === 144'd0, "witness hard reset failed");
    endtask

    task automatic step(input bit request);
        int phase;
        int position;
        reset_request = request;
        phase = edges % 2048;
        if (phase == 0) choose_pair();
        #(HALF_PERIOD_NS);
        check(phase_cycle === 11'(phase), "timing phase interrupted");
        check(left_boundary_ce === (phase == 0) &&
              sclk_rise_ce === ((phase % 32) == 16) &&
              sclk_fall_ce === ((phase % 32) == 0), "timing enable mismatch");
        check(slot_bit === 5'((phase / 32) % 32) && right_slot === (phase >= 1024),
              "timing metadata mismatch");
        check(!warm_reset_apply || (phase == 0 && (reset_pending || request)),
              "warm reset applied outside qualified left boundary");
        check(pair_complete === (reset_n && due_edge == edges),
              "complete-pair event must be offered exactly on E+1");
        if (reset_n && due_edge == edges) begin
            check({frame_id, left_sample, right_sample} === offered,
                  "wrong L/R, missing final bit, mixed frame or off-by-one ID");
            published++;
            if (queue_can_accept) begin
                expected_sink = offered;
                expected_accepted++;
            end else begin
                expected_rejected++;
                drops++;
            end
            due_edge = -1;
        end
        if (!reset_n || warm_reset_apply) begin
            aligned = reset_n && (phase == 0);
            next_id = 32'd0;
            due_edge = -1;
            expected_sink = 80'd0;
            expected_accepted = 32'd0;
            expected_rejected = 32'd0;
            if (reset_n && warm_reset_apply) warm_resets++;
        end else if (phase == 0) begin
            aligned = 1'b1;
        end else if (phase == 1808 && aligned) begin
            // Known source values, not DUT assembly registers, form expectations.
            offered = {next_id, source_left, source_right};
            if (next_id == 32'hffff_ffff) wraps++;
            next_id++;
            due_edge = edges + 1;
        end
        audio_clk = 1'b1;
        #0.000001;
        check(pair_complete === (reset_n && due_edge == edges + 1),
              "completion pulse must be registered after final right capture");
        check(sink_pair === expected_sink && accepted === expected_accepted &&
              rejected === expected_rejected, "same-edge ingress witness mismatch");
        check(phase_cycle === 11'((phase + 1) % 2048) &&
              mclk === (((phase / 4) % 2) != 0) &&
              sclk === (((phase / 16) % 2) != 0) && lrck === (phase >= 1024),
              "RX reset must leave serial timing running");
        // ADC source changes AFTER the falling serial edge, with a model delay.
        // Sampling on the falling edge therefore cannot accidentally pass.
        #1;
        if ((phase % 32) == 0) begin
            position = (phase / 32) % 32;
            if (position >= 1 && position <= 24)
                adc_sdata = (phase < 1024) ? source_left[24-position] : source_right[24-position];
            else adc_sdata = ~adc_sdata; // Nonzero tail/padding must be ignored.
        end
        #(HALF_PERIOD_NS - 1.000001);
        audio_clk = 1'b0;
        edges++;
    endtask

    task automatic reach_phase(input int phase);
        while ((edges % 2048) != phase) step(1'b0);
    endtask

    initial begin : run_test
        logic [31:0] value;
        int reset_phases [9] = '{0, 1, 48, 784, 1024, 1072, 1808, 1809, 2047};
        if ($value$plusargs("SEED_%d", seed)) begin end
        if ($value$plusargs("FRAMES_%d", frames)) begin end
        check(seed > 0 && frames > 0 && frames <= 4096, "invalid seed/frame count");
        random_state = 32'(seed);
        assert_rx_reset();
        timing_reset_n = 1'b1;
        repeat (123) step(1'b0); // Timing runs while RX is held in hard reset.
        reset_n = 1'b1;          // Mid-frame release must wait for a whole pair.
        repeat (4096) step(1'b0);
        assert_rx_reset();
        reach_phase(0);
        reset_n = 1'b1;
        repeat (258 * 2048) step(1'b0); // Includes signed extremes and low-byte ID carry.
        check(next_id == 32'd258, "continuous frame IDs must advance once per pair");
        queue_can_accept = 1'b0;
        repeat (4 * 2048) step(1'b0);
        queue_can_accept = 1'b1;
        repeat (2 * 2048) step(1'b0); // Rejected offers must still consume IDs.
        foreach (reset_phases[i]) begin
            reach_phase(reset_phases[i]);
            step(1'b1);
            repeat (4096) step(1'b0); // New frame zero starts at reset's boundary.
        end
        foreach (reset_phases[i]) begin
            reach_phase(reset_phases[i]);
            assert_rx_reset();
            repeat (13) step(1'b0);
            reset_n = 1'b1;
            repeat (4096) step(1'b0);
        end
        // Test-only state seed avoids simulating 2^32 input frames. No extra RTL
        // port/parameter is added. Public payloads/IDs remain independently scored.
        assert_rx_reset();
        reach_phase(0);
        reset_n = 1'b1;
        step(1'b0);
        force dut.next_frame_id = 32'hffff_fffe;
        #0.001;
        release dut.next_frame_id;
        #0.001;
        check(dut.next_frame_id === 32'hffff_fffe, "simulator did not retain wrap-test seed");
        next_id = 32'hffff_fffe;
        repeat (3 * 2048) step(1'b0);
        check(wraps == 1, "bounded rollover case did not run");
        repeat (frames * 2048) begin
            random_next(value);
            queue_can_accept = (value % 5) != 0;
            step((value % 2017) == 0);
            if ((value % 8191) == 3) begin
                assert_rx_reset();
                repeat (7) step(1'b0);
                reset_n = 1'b1;
            end
        end
        queue_can_accept = 1'b1;
        repeat (4096) step(1'b0);
        check(published > 258 && drops >= 4 && warm_resets >= 9 && aborted_offers > 0,
              "directed capture/reset/admission coverage missing");
        $display("I2S_RX_PASS seed=%0d frames=%0d edges=%0d pairs=%0d rejected=%0d warm=%0d aborted=%0d wraps=%0d",
                 seed, frames, edges, published, drops, warm_resets, aborted_offers, wraps);
`ifdef ANIMA_RX_QUEUE_TEST
        check(&queue_cases_done, "queue unit cases have not finished");
        queue_chain.report(seed);
        $display("RX_QUEUE_PASS seed=%0d depths=1,2,4,8", seed);
`endif
        $finish;
    end
endmodule

`default_nettype wire
