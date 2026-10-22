`timescale 1ns/1fs
`default_nettype none

// Independent edge-index model: no reads of internal DUT state or helper logic.
// Case selection isolates phase, clock and event checks when diagnosing failures.
module anima_serial_timing_tb;
    // Synthetic processing clock for the calculated 100 MHz * 58/59 target.
    // Simulation time quantization is not physical frequency/jitter evidence.
    localparam realtime HALF_PERIOD_NS = 295.0 / 58.0;
    logic audio_clk = 1'b0;
    logic reset_n = 1'b0;
    wire [10:0] phase_cycle;
    wire mclk, sclk, lrck;
    wire sclk_rise_ce, sclk_fall_ce, left_boundary_ce;
    wire [4:0] slot_bit;
    wire right_slot;

    anima_serial_timing dut (.*);

    string case_name = "phase";
    int seed = 2026;
    int frames = 8;
    int expected_phase = 0;
    int total_edges = 0;
    int epoch_edges = 0;
    int rise_count = 0;
    int fall_count = 0;
    int left_count = 0;
    bit check_phase;
    bit check_clocks;
    bit check_events;
    logic [31:0] random_state;

    task automatic require_check(input bit condition, input string message);
        if (!condition) begin
            $display("FAIL case=%s edge=%0d phase=%0d: %s",
                     case_name, total_edges, expected_phase, message);
            $fatal(1, "serial timing contract failed");
        end
    endtask

    // A specified xorshift stream makes reset offsets reproducible across tools.
    task automatic next_random(output int unsigned value);
        random_state = random_state ^ (random_state << 13);
        random_state = random_state ^ (random_state >> 17);
        random_state = random_state ^ (random_state << 5);
        value = random_state;
    endtask

    task automatic hard_reset;
        // No audio_clk rising edge occurs here: verify asynchronous assertion.
        audio_clk = 1'b0;
        reset_n = 1'b0;
        #1;
        if (check_phase)
            require_check(phase_cycle === 11'd0, "hard reset must clear phase without a clock edge");
        if (check_clocks)
            require_check({mclk, sclk, lrck} === 3'b000, "hard reset must clear serial pins");
        if (check_events) begin
            require_check({sclk_rise_ce, sclk_fall_ce, left_boundary_ce} === 3'b000,
                          "hard reset must suppress all enables");
            require_check({right_slot, slot_bit} === 6'd0, "hard reset must clear metadata");
        end
        #1;
        expected_phase = 0;
        epoch_edges = 0;
        rise_count = 0;
        fall_count = 0;
        left_count = 0;
        // Legal release while audio_clk is low, away from its next rising edge.
        reset_n = 1'b1;
    endtask

    task automatic step;
        bit old_sclk;
        bit expected_rise;
        bit expected_fall;
        bit expected_left;
        bit expected_mclk;
        bit expected_sclk;
        bit expected_lrck;
        logic [4:0] expected_slot;
        logic [10:0] next_phase;

        #(HALF_PERIOD_NS);
        // Expected values come from elapsed edges, not from DUT phase_cycle.
        expected_rise = ((expected_phase % 32) == 16);
        expected_fall = ((expected_phase % 32) == 0);
        expected_left = (expected_phase == 0);
        expected_mclk = ((expected_phase / 4) % 2) != 0;
        expected_sclk = ((expected_phase / 16) % 2) != 0;
        expected_lrck = (expected_phase >= 1024);
        expected_slot = 5'((expected_phase / 32) % 32);
        next_phase = 11'((expected_phase + 1) % 2048);
        old_sclk = sclk;

        if (check_phase)
            require_check(phase_cycle === 11'(expected_phase), "wrong pre-edge phase");
        if (check_events) begin
            require_check(sclk_rise_ce === expected_rise, "capture enable must be visible before its edge");
            require_check(sclk_fall_ce === expected_fall, "launch enable must be visible before its edge");
            require_check(left_boundary_ce === expected_left, "wrong left-boundary enable");
            require_check(slot_bit === expected_slot, "wrong channel-slot position");
            require_check(right_slot === expected_lrck, "wrong upcoming channel");
            require_check(!(sclk_rise_ce && sclk_fall_ce), "rise/fall enables overlap");
            require_check(!left_boundary_ce || sclk_fall_ce, "left boundary must be a launch edge");
            if (sclk_rise_ce) rise_count++;
            if (sclk_fall_ce) fall_count++;
            if (left_boundary_ce) left_count++;
        end

        audio_clk = 1'b1;
        #0.000001; // One femtosecond: observe nonblocking assignments after the edge.
        if (check_phase)
            require_check(phase_cycle === next_phase, "phase must advance once and wrap at 2048");
        if (check_clocks) begin
            require_check(mclk === expected_mclk, "MCLK must divide processing frequency by 8");
            require_check(sclk === expected_sclk, "SCLK must divide processing frequency by 32");
            require_check(lrck === expected_lrck, "LRCK must divide processing frequency by 2048");
        end
        if (check_events && check_clocks) begin
            if (expected_rise)
                require_check(!old_sclk && sclk, "capture event must coincide with a registered SCLK rise");
            // First post-reset p=0 initializes low; later falls are actual transitions.
            if (expected_fall && epoch_edges != 0)
                require_check(old_sclk && !sclk, "launch event must coincide with a registered SCLK fall");
        end
        if (check_events && expected_phase == 2047) begin
            require_check(rise_count == 64 && fall_count == 64 && left_count == 1,
                          "one stereo frame requires 64 rises, 64 falls and one left boundary");
            rise_count = 0;
            fall_count = 0;
            left_count = 0;
        end
        expected_phase = (expected_phase + 1) % 2048;
        total_edges++;
        epoch_edges++;
        #(HALF_PERIOD_NS - 0.000001);
        audio_clk = 1'b0;
    endtask

    initial begin : run_test
        int unsigned random_value;
        int unsigned offset;
        if ($value$plusargs("CASE_%s", case_name)) begin end
        if ($value$plusargs("SEED_%d", seed)) begin end
        if ($value$plusargs("FRAMES_%d", frames)) begin end
        check_phase = (case_name == "phase" || case_name == "all");
        check_clocks = (case_name == "clocks" || case_name == "all");
        check_events = (case_name == "events" || case_name == "all");
        require_check(check_phase || check_clocks || check_events, "unknown CASE");
        require_check(seed > 0 && frames > 0 && frames <= 1024, "invalid seed or frame count");
        random_state = 32'(seed);

        hard_reset();
        // Directed checks cover wrap and both sides of every bit/channel boundary.
        repeat (frames * 2048 + 1) step();
        // Seeded resets cover clock phases away from a frame-aligned reset.
        repeat (4) begin
            next_random(random_value);
            offset = 1 + (random_value % 2046);
            repeat (offset) step();
            hard_reset();
            repeat (2048) step();
        end
        $display("TIMING_PASS case=%s seed=%0d frames=%0d edges=%0d",
                 case_name, seed, frames, total_edges);
        $finish;
    end
endmodule

`default_nettype wire
