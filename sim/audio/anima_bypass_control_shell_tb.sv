`timescale 1ns/1fs
`default_nettype none
module anima_bypass_control_shell_tb;
    logic ref_clk=0, audio_clk=0, initial_reset_n=0;
    logic run_audio=1, lock_source=1, button_center=1, button_down=1, adc_sdata=0;
    wire mmcm_reset, led0, mclk, sclk, lrck, dac_sdata;
    wire timing_reset_n, data_reset_n, loss_pending;
    wire mmcm_locked=lock_source && !mmcm_reset;
    wire [31:0] underflow_count, overflow_count, late_discard_count, stall_timeout_count, recovered_clock_loss_count;
    anima_bypass_control_shell #(.BUTTON_STABLE_CYCLES(4), .HEARTBEAT_CYCLES(4),
        .TIMEOUT_REF_CYCLES(64), .MMCM_RESET_REF_CYCLES(4), .STARTUP_AUDIO_CYCLES(32)) dut (.*);
    wire button_done;
    anima_button_event_tb button_case(button_done);
    always #5 ref_clk<=~ref_clk;
    // Behavioral first-build-ratio clock; no MMCM primitive or physical timing.
    always #5.086207 begin
        if(run_audio) audio_clk<=~audio_clk;
        else audio_clk<=0;
    end
    int seed=2026, warm_count=0, clear_count=0, guard_edges=0;
    bit saw_lrck=0;
    always @(posedge audio_clk) begin
        if(dut.core.warm_reset_apply) warm_count<=warm_count+1;
        if(dut.clear_button.press_event) clear_count<=clear_count+1;
            assert(!dac_sdata) else $fatal(1,"BOARD_FAIL zero ADC must serialize zero");
            assert({underflow_count,overflow_count,late_discard_count,stall_timeout_count}==128'd0)
                else $fatal(1,"BOARD_FAIL normal control/recovery must not create audio faults");
    end
    always @(posedge audio_clk or negedge timing_reset_n) begin
        if(!timing_reset_n) begin guard_edges<=0; saw_lrck<=0; end
        else begin
            if(lrck) saw_lrck<=1;
            if(saw_lrck && guard_edges<32) guard_edges<=guard_edges+1;
        end
    end
    always @(posedge data_reset_n)
        assert(saw_lrck && guard_edges>=32) else $fatal(1,"BOARD_FAIL short codec guard");
    task automatic audio_edges(input int count);
        repeat(count) @(negedge audio_clk);
    endtask
    task automatic wait_ready;
        int cycles;
        cycles=0;
        while(!data_reset_n && cycles<7000) begin @(negedge ref_clk); cycles++; end
        assert(data_reset_n) else $fatal(1,"BOARD_FAIL no qualified restart");
    endtask
    task automatic wait_recovery(input int expected_count);
        int cycles;
        cycles=0;
        while((recovered_clock_loss_count!=32'(expected_count) || loss_pending) && cycles<9000) begin
            @(negedge ref_clk); cycles++;
        end
        assert(recovered_clock_loss_count==32'(expected_count) && !loss_pending && led0)
            else $fatal(1,"BOARD_FAIL recovery counter/delivery expected=%0d actual=%0d pending=%b",expected_count,recovered_clock_loss_count,loss_pending);
    endtask
    initial begin
        void'($value$plusargs("SEED_%d",seed));
        repeat(8+seed%7) @(negedge ref_clk); initial_reset_n=1;
        wait_ready(); audio_edges(100);
        assert(warm_count==0 && clear_count==0 && !led0 && recovered_clock_loss_count==0)
            else $fatal(1,"BOARD_FAIL startup/held buttons must not create commands or loss events");
        button_center=0; button_down=0; audio_edges(16);
        button_center=1; audio_edges(2); button_center=0; audio_edges(2);
        button_center=1; audio_edges(1); button_center=0; audio_edges(16);
        assert(warm_count==0) else $fatal(1,"BOARD_FAIL short button bounce");
        button_center=1; audio_edges(3000);
        assert(warm_count==1 && clear_count==0 && data_reset_n && !led0)
            else $fatal(1,"BOARD_FAIL one warm reset per held center press");
        button_center=0; audio_edges(16);
        // A raw LOCKED pulse shorter than a reference period must invalidate
        // immediately; its reset-release pipeline retains reference visibility.
        @(negedge ref_clk); #1; lock_source=0; #0.001;
        assert(!timing_reset_n && !data_reset_n && !dac_sdata)
            else $fatal(1,"BOARD_FAIL asynchronous lock invalidation");
        #1; lock_source=1;
        for(int attempt=0;attempt<3;attempt++) begin
            wait(timing_reset_n); audio_edges(8);
            assert(!data_reset_n) else $fatal(1,"BOARD_FAIL qualification must restart on flaps");
            lock_source=0; repeat(3) @(negedge ref_clk); lock_source=1;
        end
        wait_ready(); wait_recovery(1);
        // Audio stops while LOCKED initially stays high. Reference watchdog
        // must invalidate without needing any further audio clock edges.
        @(negedge audio_clk); run_audio=0;
        repeat(80) @(negedge ref_clk);
        assert(!timing_reset_n && !data_reset_n && loss_pending && recovered_clock_loss_count==1 && led0)
            else $fatal(1,"BOARD_FAIL stopped clock not detected by reference heartbeat");
        repeat(160) @(negedge ref_clk);
        assert(!mclk && !sclk && !lrck && !dac_sdata && recovered_clock_loss_count==1)
            else $fatal(1,"BOARD_FAIL stopped-clock reset/evidence retention");
        button_center=1; button_down=1; run_audio=1;
        wait_ready();
        // Interrupt event delivery itself. The registered pulse must survive
        // stopping audio before its diagnostic consumer can sample it.
        wait(dut.clocks.recovered_clock_loss_event);
        run_audio=0;
        repeat(100) @(negedge ref_clk);
        assert(recovered_clock_loss_count==1 && loss_pending)
            else $fatal(1,"BOARD_FAIL unconsumed recovery pulse must not be lost or pre-counted");
        run_audio=1; audio_edges(8);
        assert(recovered_clock_loss_count==2 && !data_reset_n)
            else $fatal(1,"BOARD_FAIL consume held recovery pulse exactly once on resumed audio");
        wait_ready(); wait_recovery(2); audio_edges(3000);
        assert(warm_count==1 && clear_count==0 && recovered_clock_loss_count==2)
            else $fatal(1,"BOARD_FAIL flaps/event interruption coalesce; held buttons stay suppressed");
        button_center=0; button_down=0; audio_edges(16);
        button_down=1; audio_edges(2200);
        assert(clear_count==1 && warm_count==1 && !led0 && recovered_clock_loss_count==0 && data_reset_n)
            else $fatal(1,"BOARD_FAIL down press must clear LED/counters without warm reset");
        button_down=0; audio_edges(16);
        assert(button_done) else $fatal(1,"BOARD_FAIL button unit did not finish");
        $display("BOARD_CONTROL_PASS seed=%0d warm=%0d clear=%0d qualified_recoveries=2 lock_flaps=3 heartbeat_loss=1 interrupted_delivery=1",seed,warm_count,clear_count);
        $finish;
    end
    initial begin #2000000; $fatal(1,"BOARD_FAIL timeout"); end
endmodule
`default_nettype wire
