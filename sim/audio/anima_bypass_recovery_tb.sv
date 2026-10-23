`timescale 1ns/1fs
`default_nettype none
module anima_bypass_recovery_tb(output bit done=0);
    logic audio_clk=0, reset_n=0, data_reset_n=0, reset_request=0, adc_sdata=0;
    wire mclk, sclk, lrck, dac_sdata, warm_reset_apply, reset_pending;
    wire overflow_event, underflow_event, late_discard_event, stall_timeout_event, ambiguous_id_event;
    wire frame_select_ce, frame_real;
    wire [31:0] frame_id;
    anima_bypass_core dut (.*);
    int phase=0, ticks=0, incidents=0, applications=0, next_id=0, checked_restarts=0;
    int requests=0, overflows=0;
    bit injecting=0, checking_restart=0, was_pending=0;
    task automatic tick;
        bit apply;
        #2; apply=warm_reset_apply;
        assert(!apply || phase==0) else $fatal(1,"BYPASS_FAIL reset alignment");
        if (apply) begin
            // Only fault injection writes implementation state. Expected IDs,
            // clocks and event accounting use public observations and elapsed time.
            release dut.scheduler.started;
            injecting=0; applications++; checking_restart=1; next_id=0;
            assert(!frame_real && !underflow_event && !late_discard_event)
                else $fatal(1,"BYPASS_FAIL reset must select intentional silence");
        end else if (checking_restart && phase==0) begin
            assert(frame_select_ce && frame_real && frame_id==32'(next_id))
                else $fatal(1,"BYPASS_FAIL fresh frame numbering/playback after recovery");
            next_id++; checked_restarts++;
        end
        if (overflow_event) overflows++;
        if (reset_pending && !was_pending) requests++;
        was_pending=reset_pending;
        assert(!ambiguous_id_event && !late_discard_event)
            else $fatal(1,"BYPASS_FAIL unexpected stream violation");
        if (!injecting && !apply)
            assert(!underflow_event) else $fatal(1,"BYPASS_FAIL unexpected normal underflow");
        audio_clk=1; #1;
        assert(mclk===((phase%8)>=4) && sclk===((phase%32)>=16) && lrck===(phase>=1024))
            else $fatal(1,"BYPASS_FAIL recovery must not reset codec clocks");
        assert(!dac_sdata) else $fatal(1,"BYPASS_FAIL zero source must decode as silence");
        if (stall_timeout_event) incidents++;
        if (!data_reset_n)
            assert(!frame_select_ce && !frame_real && !reset_pending && !stall_timeout_event)
                else $fatal(1,"BYPASS_FAIL data reset qualification masking");
        audio_clk=0; #1; phase=(phase+1)%2048; ticks++;
    endtask
    initial begin
        #1; reset_n=1;
        repeat(2171) tick(); // clocks run while all data blocks remain reset
        data_reset_n=1;
        while(phase!=0) tick(); tick(); // aligned first capture interval
        // Block scheduler before its first reservation: RX alone must time out.
        force dut.scheduler.started=1'b0;
        injecting=1;
        while(applications<1 && ticks<15000) tick();
        assert(incidents==1 && applications==1) else $fatal(1,"BYPASS_FAIL RX recovery");
        repeat(4096) tick();
        // Stop promotion after a normal pair has reached waiting storage.
        // Its waiting timer must expire even before RX accumulates 2048 stalls.
        while(phase!=1811) tick();
        force dut.scheduler.started=1'b0;
        injecting=1; checking_restart=0;
        while(applications<2 && ticks<25000) tick();
        assert(incidents==2 && applications==2) else $fatal(1,"BYPASS_FAIL TX recovery");
        repeat(4096) tick();
        assert(checked_restarts>=4 && requests==2)
            else $fatal(1,"BYPASS_FAIL one request per recovery and fresh frame checks");
        data_reset_n=0; #1;
        assert(!dac_sdata && !frame_real && !stall_timeout_event)
            else $fatal(1,"BYPASS_FAIL async data-only reset");
        repeat(32) tick();
        $display("BYPASS_RECOVERY_PASS ticks=%0d incidents=%0d applications=%0d restarts=%0d overflows=%0d",ticks,incidents,applications,checked_restarts,overflows);
        done=1;
    end
endmodule
`default_nettype wire
