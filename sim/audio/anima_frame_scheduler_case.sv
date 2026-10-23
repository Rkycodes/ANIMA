`timescale 1ns/1fs
`default_nettype none
module anima_frame_scheduler_case #(parameter integer DEPTH=1)(output bit done=0);
    logic audio_clk=0, reset_n=0, warm_reset_apply=0, in_valid=0;
    logic signed [23:0] in_left=0, in_right=0;
    logic [31:0] in_frame_id=0;
    wire left_boundary_ce;
    wire [10:0] unused_phase_cycle;
    wire unused_mclk, unused_sclk, unused_lrck, unused_rise, unused_fall, unused_right;
    wire [4:0] unused_slot;
    anima_serial_timing timing (.audio_clk(audio_clk), .reset_n(reset_n),
        .left_boundary_ce(left_boundary_ce), .phase_cycle(unused_phase_cycle),
        .mclk(unused_mclk), .sclk(unused_sclk), .lrck(unused_lrck),
        .sclk_rise_ce(unused_rise), .sclk_fall_ce(unused_fall),
        .right_slot(unused_right), .slot_bit(unused_slot));
    wire in_ready, select_ce, select_real, underflow_event, late_discard_event, ambiguous_id_event;
    wire signed [23:0] select_left, select_right;
    wire [31:0] select_frame_id;
    anima_frame_scheduler #(.TX_WAIT_DEPTH(DEPTH)) dut (.*);
    // Reference is a reservation list keyed by output interval. No DUT state
    // is read by the scoreboard. Only the bounded rollover setup writes state.
    logic [79:0] reservations[$];
    logic [31:0] expected=0, rng;
    bit begun=0, last_accept=0, deliberate_ambiguity=0;
    int seed=2026, ticks=0, real_pairs=0, silences=0, late_pairs=0, replacements=0;
    int direct_pairs=0, ambiguous_pairs=0, resets=0;
    task automatic check(input bit ok, input string msg);
        if (!ok) $fatal(1,"SCHEDULER_FAIL depth=%0d seed=%0d tick=%0d %s",DEPTH,seed,ticks,msg);
    endtask
    task automatic randomize_word;
        rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
    endtask
    task automatic tick;
        bit active, boundary, real_expected, ready_expected, accept, is_late, bad, direct_expected;
        logic [31:0] target, distance;
        logic [79:0] chosen, removed;
        #4;
        active=reset_n && !warm_reset_apply;
        boundary=active && begun && left_boundary_ce;
        target=expected;
        if (boundary && reservations.size()!=0) target=expected+1;
        distance=in_frame_id-target;
        bad=distance==32'h80000000;
        is_late=distance[31] && !bad;
        ready_expected=active && begun && !bad &&
            (is_late || (distance==0 && (reservations.size()==0 || boundary)));
        accept=in_valid && ready_expected;
        last_accept=accept;
        direct_expected=boundary && reservations.size()==0 && accept && distance==0;
        chosen=80'd0;
        real_expected=0;
        if (boundary) begin
            if (reservations.size()!=0) begin
                chosen=reservations[0]; real_expected=1;
            end else if (accept && distance==0) begin
                chosen={in_frame_id,in_left,in_right}; real_expected=1;
                direct_pairs++;
            end
        end
        check(in_ready===ready_expected,"acceptance/backpressure");
        check(select_ce===(reset_n && left_boundary_ce),"selection strobe");
        check(select_real===real_expected,"real/silence selection");
        check({select_left,select_right}===chosen[47:0],"selected whole-pair payload");
        check(select_frame_id===(boundary ? expected : 32'd0),"selected identity");
        check(underflow_event===(boundary && !real_expected),"underflow/startup/reset masking");
        check(late_discard_event===(accept && is_late),"late discard event");
        check(ambiguous_id_event===(active && begun && in_valid && bad),"half-range violation");
        assert (!ambiguous_id_event || (deliberate_ambiguity && !$test$plusargs("REJECT_AMBIGUOUS")))
            else $fatal(1,"SCHEDULER_EXPECTED_AMBIGUOUS_ASSERT half-range ID");
        if (ambiguous_id_event) ambiguous_pairs++;
        if (accept && is_late) late_pairs++;
        if (!reset_n || warm_reset_apply) begin
            reservations.delete(); expected=0;
            begun=reset_n && left_boundary_ce;
            resets++;
        end else begin
            if (boundary) begin
                if (real_expected) real_pairs++; else silences++;
                if (reservations.size()!=0) begin
                    removed=reservations.pop_front();
                    check(removed==chosen && removed[79:48]==expected,"reserved pair belongs to deadline");
                    if (accept && distance==0) replacements++;
                end
                expected++;
            end
            if (accept && distance==0) begin
                // Direct acceptance serves this boundary; all other due
                // transfers reserve the next unfilled output interval.
                if (!direct_expected)
                    reservations.push_back({in_frame_id,in_left,in_right});
            end
            if (left_boundary_ce) begun=1;
        end
        audio_clk=1; #1; audio_clk=0; #1; ticks++;
    endtask
    task automatic offer(input logic [31:0] id);
        in_valid=1; in_frame_id=id;
        in_left=$signed(24'h800001 ^ id[23:0]);
        in_right=$signed(24'h7ffffe ^ ~id[23:0]);
    endtask
    task automatic to_boundary;
        while (!left_boundary_ce) tick();
    endtask
    initial begin
        void'($value$plusargs("SEED_%d",seed));
        rng=32'(seed)+32'(DEPTH);
        tick(); reset_n=1; tick(); // intentional initial silence, starts capture
        offer(0); tick(); // reserve frame zero early
        offer(0); repeat(3) tick(); // duplicate must wait, cannot overwrite
        to_boundary(); tick(); // promote zero, accept/discard held duplicate
        offer(1); tick(); // reserve following slot after the duplicate transfer
        in_valid=0; to_boundary(); tick();
        to_boundary(); tick(); // missing frame two: underflow
        offer(2); tick(); // one edge late: discard
        offer(3); to_boundary(); tick(); // early reservation then promotion
        in_valid=0; to_boundary(); offer(4); tick(); // exact-edge direct
        offer(6); repeat(5) tick(); // future stays upstream
        to_boundary(); tick(); // future six stays held through missing five
        tick(); in_valid=0; // six is now due and accepted
        to_boundary(); warm_reset_apply=1; offer(7); tick();
        warm_reset_apply=0; offer(0); tick(); in_valid=0;
        to_boundary(); tick(); // zero after reset
        // Bounded wrap setup: avoid simulating 2^32 intervals. Seed only the
        // schedule counter, then score public results across rollover.
        reset_n=0; tick(); reset_n=1; tick();
        dut.expected_id=32'hfffffffe; expected=32'hfffffffe;
        offer(32'hfffffffe); tick(); in_valid=0; to_boundary(); offer(32'hffffffff); tick();
        in_valid=0; to_boundary(); offer(0); tick();
        in_valid=0; to_boundary(); tick();
        deliberate_ambiguity=1; offer(expected+32'h80000000); tick(); in_valid=0; deliberate_ambiguity=0;
        // Randomized offers obey stable valid/data under backpressure.
        for (int i=0;i<120000;i++) begin
            randomize_word();
            warm_reset_apply=left_boundary_ce && (rng[3:0]==0);
            if (!in_valid || last_accept || warm_reset_apply) begin
                in_valid=0;
                if (rng[1:0]!=0) begin
                    case (rng[4:2])
                        0: offer(expected-1);
                        1: offer(expected+1);
                        default: offer(expected);
                    endcase
                end
            end
            tick();
            if (warm_reset_apply) in_valid=0;
            warm_reset_apply=0;
        end
        while (in_valid && !last_accept) tick(); // finish the final stalled offer
        in_valid=0; to_boundary(); tick(); to_boundary(); tick();
        reset_n=0; tick();
        check(real_pairs>10 && silences>0 && late_pairs>0 && replacements>0 &&
              direct_pairs>0 && ambiguous_pairs>0 && resets>1,"coverage requirements");
        $display("SCHEDULER_CASE_PASS depth=%0d seed=%0d ticks=%0d real=%0d silence=%0d late=%0d replace=%0d direct=%0d",DEPTH,seed,ticks,real_pairs,silences,late_pairs,replacements,direct_pairs);
        done=1;
    end
endmodule
`default_nettype wire
