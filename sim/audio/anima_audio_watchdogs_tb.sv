`timescale 1ns/1fs
`default_nettype none
module anima_audio_watchdogs_tb(output bit done=0);
    logic audio_clk=0, reset_n=0, warm_reset_apply=0;
    logic rx_nonempty=0, rx_progress=0, tx_nonempty=0, tx_progress=0;
    wire recovery_request, stall_timeout_event;
    anima_audio_watchdogs dut (.*);
    int rx_age=0, tx_age=0, ticks=0, events=0;
    bit pending=0;
    logic [31:0] rng;
    int seed=2026;
    task automatic tick(input bit rn, rp, tn, tp, flush);
        bit event_expected;
        rx_nonempty=rn; rx_progress=rp; tx_nonempty=tn; tx_progress=tp;
        warm_reset_apply=flush; event_expected=0;
        if (!reset_n || flush) begin rx_age=0; tx_age=0; pending=0; end
        else if (!pending) begin
            rx_age=(rn && !rp) ? rx_age+1 : 0;
            tx_age=(tn && !tp) ? tx_age+1 : 0;
            if (rx_age>=2048 || tx_age>=2048) begin pending=1; event_expected=1; events++; end
        end
        #2; audio_clk=1; #1;
        assert (recovery_request===pending && stall_timeout_event===event_expected)
            else $fatal(1,"BYPASS_FAIL watchdog tick=%0d age=%0d/%0d",ticks,rx_age,tx_age);
        audio_clk=0; #1; ticks++;
    endtask
    initial begin
        void'($value$plusargs("SEED_%d",seed)); rng=32'(seed);
        tick(1,0,1,0,0); reset_n=1;
        repeat(2047) tick(1,0,0,0,0);
        tick(1,1,0,0,0); // threshold-edge RX progress wins
        repeat(2047) tick(0,0,1,0,0);
        tick(0,0,1,1,0); // threshold-edge promotion wins
        repeat(2048) tick(1,0,1,0,0); // simultaneous expiry is one event
        repeat(4096) tick(1,0,1,0,0); // pending cannot retrigger
        tick(1,0,1,0,1); // reset has priority
        repeat(2048) tick(1,0,0,0,0); // RX-only expiry
        tick(0,0,0,0,1);
        repeat(2048) tick(0,0,1,0,0); // TX-only expiry
        tick(0,0,0,0,1);
        repeat(2047) tick(1,0,1,0,0);
        tick(0,0,0,0,0); // empty threshold edge restarts both timers
        repeat(2047) tick(1,0,1,0,0);
        tick(1,1,1,0,0); // RX progress cannot hide TX expiry
        tick(0,0,0,0,1);
        repeat(10000) begin
            rng^=rng<<13; rng^=rng>>17; rng^=rng<<5;
            tick(rng[0],rng[1],rng[2],rng[3],rng[7:4]==0);
        end
        tick(0,0,0,0,1);
        repeat(2047) tick(1,0,1,0,0);
        tick(1,0,1,0,1); // reset on the would-be expiry edge wins
        repeat(2048) tick(1,0,1,0,0);
        reset_n=0; #1;
        assert (!recovery_request && !stall_timeout_event) else $fatal(1,"BYPASS_FAIL watchdog async reset");
        tick(0,0,0,0,0); reset_n=1;
        assert(events==5) else $fatal(1,"BYPASS_FAIL watchdog coverage events=%0d",events);
        $display("WATCHDOG_PASS seed=%0d ticks=%0d incidents=%0d",seed,ticks,events); done=1;
    end
endmodule
`default_nettype wire
