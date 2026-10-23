`timescale 1ns/1fs
`default_nettype none
module anima_audio_diagnostics_tb;
    logic audio_clk=0, diagnostic_reset_n=0, diagnostic_clear=0;
    logic [4:0] occurrences=0;
    wire underflow_event=occurrences[0], overflow_event=occurrences[1];
    wire late_discard_event=occurrences[2], stall_timeout_event=occurrences[3];
    wire recovered_clock_loss_event=occurrences[4];
    wire [31:0] underflow_count, overflow_count, late_discard_count;
    wire [31:0] stall_timeout_count, recovered_clock_loss_count;
    wire fault_sticky;
    anima_audio_diagnostics dut (.*);
    wire [159:0] observed={recovered_clock_loss_count,stall_timeout_count,
                          late_discard_count,overflow_count,underflow_count};
    // Wide integer arithmetic provides an independent bounded-count oracle.
    longint unsigned expected[0:4];
    bit expected_fault=0;
    logic [31:0] rng;
    int seed=2026, ticks=0, sampled_events=0, clears=0, initializations=0;
    task automatic check_outputs;
        for(int k=0;k<5;k++)
            assert(observed[k*32+:32]===32'(expected[k]))
                else $fatal(1,"DIAGNOSTICS_FAIL seed=%0d tick=%0d class=%0d expected=%0d actual=%0d",
                            seed,ticks,k,expected[k],observed[k*32+:32]);
        assert(fault_sticky===expected_fault)
            else $fatal(1,"DIAGNOSTICS_FAIL sticky evidence seed=%0d tick=%0d",seed,ticks);
    endtask
    task automatic initialize_diagnostics;
        diagnostic_reset_n=0; #1;
        foreach(expected[k]) expected[k]=0;
        expected_fault=0; initializations++;
        check_outputs(); // immediate asynchronous assertion, no clock edge
    endtask
    task automatic tick(input logic [4:0] mask, input bit clear_now);
        occurrences=mask; diagnostic_clear=clear_now;
        if (!diagnostic_reset_n) begin
            foreach(expected[k]) expected[k]=0;
            expected_fault=0;
        end else begin
            for(int k=0;k<5;k++) begin
                if(clear_now) expected[k]=mask[k] ? 1 : 0;
                else if(mask[k] && expected[k]<64'hffffffff) expected[k]++;
                if(mask[k]) sampled_events++;
            end
            expected_fault=clear_now ? (mask!=0) : (expected_fault || mask!=0);
            if(clear_now) clears++;
        end
        #2; audio_clk=1; #1; check_outputs(); audio_clk=0; #1; ticks++;
    endtask
    initial begin
        void'($value$plusargs("SEED_%d",seed)); rng=32'(seed);
        initialize_diagnostics(); tick(5'b11111,1); diagnostic_reset_n=1;
        for(int k=0;k<5;k++) tick(5'b00001<<k,0); // independent class mapping
        repeat(7) tick(5'b11111,0); // one increment per high input edge
        repeat(16) tick(0,0); // evidence persists with no events
        // Every same-edge clear/event combination, including all five at once.
        for(int mask=0;mask<32;mask++) begin tick(5'(mask),1); tick(0,0); end
        tick(5'b11111,1);
        // Explicit bounded saturation setup, not a claim of 2^32 event edges.
        // No production seed/debug port is introduced.
        dut.underflow_count=32'hfffffffe;
        dut.overflow_count=32'hfffffffe;
        dut.late_discard_count=32'hfffffffe;
        dut.stall_timeout_count=32'hfffffffe;
        dut.recovered_clock_loss_count=32'hfffffffe;
        foreach(expected[k]) expected[k]=64'hfffffffe;
        #1; check_outputs();
        tick(5'b11111,0); // reaches maximum
        repeat(5) tick(5'b11111,0); // saturates, never wraps
        tick(5'b10101,1); // clear plus events becomes one even after saturation
        tick(0,0);
        repeat(10000) begin
            rng^=rng<<13; rng^=rng>>17; rng^=rng<<5;
            if(rng[16:11]==0) begin initialize_diagnostics(); diagnostic_reset_n=1; end
            tick(rng[4:0],rng[10:5]==0);
        end
        initialize_diagnostics(); tick(5'b11111,1); // init reset beats both
        diagnostic_reset_n=1; tick(0,0);
        $display("DIAGNOSTICS_PASS seed=%0d ticks=%0d sampled_events=%0d clears=%0d initializations=%0d",
                 seed,ticks,sampled_events,clears,initializations);
        $finish;
    end
    initial begin #2000000; $fatal(1,"DIAGNOSTICS_FAIL timeout"); end
endmodule
`default_nettype wire
