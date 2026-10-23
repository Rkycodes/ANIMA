`timescale 1ns/1fs
`default_nettype none
module anima_bypass_core_tb;
    wire watchdog_done, recovery_done;
    anima_audio_watchdogs_tb watchdog_case(watchdog_done);
    anima_bypass_recovery_tb recovery_case(recovery_done);
    logic audio_clk=0, reset_n=0, reset_request=0;
    wire [10:0] unused_phase_cycle;
    wire mclk, sclk, lrck, sclk_rise_ce, sclk_fall_ce, left_boundary_ce, right_slot;
    wire [4:0] slot_bit;
    anima_serial_timing timing (.phase_cycle(unused_phase_cycle), .*);
    wire unused_reset_pending, warm_reset_apply;
    anima_warm_reset_controller reset_control (.reset_pending(unused_reset_pending), .*);

    logic select_ce=0;
    logic signed [23:0] select_left=0, select_right=0;
    wire dac_sdata;
    anima_i2s_transmitter dut (.*);

    logic adc_sdata=0;
    wire [15:0] core_data, core_mclk, core_sclk, core_lrck;
    wire [15:0] core_warm, core_pending, core_overflow, core_underflow, core_late;
    wire [15:0] core_stall, core_ambiguous, core_select, core_real;
    wire [31:0] core_id [0:15];
    genvar r, t;
    generate for (r=0;r<4;r=r+1) begin : rx_configs
        for (t=0;t<4;t=t+1) begin : tx_configs
            localparam integer INDEX=r*4+t;
            anima_bypass_core #(.RX_DEPTH(1<<r), .TX_WAIT_DEPTH(1<<t)) core (
                .audio_clk(audio_clk), .reset_n(reset_n), .data_reset_n(reset_n),
                .reset_request(reset_request), .adc_sdata(adc_sdata),
                .mclk(core_mclk[INDEX]), .sclk(core_sclk[INDEX]), .lrck(core_lrck[INDEX]),
                .dac_sdata(core_data[INDEX]), .warm_reset_apply(core_warm[INDEX]),
                .reset_pending(core_pending[INDEX]), .overflow_event(core_overflow[INDEX]),
                .underflow_event(core_underflow[INDEX]), .late_discard_event(core_late[INDEX]),
                .stall_timeout_event(core_stall[INDEX]), .ambiguous_id_event(core_ambiguous[INDEX]),
                .frame_select_ce(core_select[INDEX]), .frame_real(core_real[INDEX]),
                .frame_id(core_id[INDEX]));
        end
    end endgenerate
    wire chain_select_ce=core_select[0], chain_real=core_real[0], chain_sdata=core_data[0];
    wire [31:0] chain_id=core_id[0];
    int seed=2026, phase=0, ticks=0, frame_count=0, resets=0, warm_count=0;
    int dac_pairs=0, unit_pairs=0, hard_count=0;
    logic [31:0] rng, source_id=0;
    bit started=0, pending=0, expected_unit_bit=0, expected_chain_bit=0;
    logic [47:0] unit_pair=0, chain_pair=0, decoded_unit=0, decoded_chain=0;
    bit decode_complete=0;

    function automatic logic [23:0] sample(input logic [31:0] id, input bit right_channel);
        // Known signed extrema, zero, alternating and asymmetric patterns, then
        // reproducible frame/channel-specific words. Not derived from DUT data.
        case (id[2:0])
            0: sample=right_channel ? 24'h7fffff : 24'h800000;
            1: sample=right_channel ? 24'hffffff : 24'h000001;
            2: sample=right_channel ? 24'h555555 : 24'haaaaaa;
            3: sample=24'd0;
            default: sample=id[23:0] ^ {16'd0,id[31:24]} ^ (right_channel ? 24'hc3a571 : 24'h159de2);
        endcase
    endfunction
    task automatic check(input bit ok, input string msg);
        if (!ok) $fatal(1,"BYPASS_FAIL seed=%0d tick=%0d phase=%0d: %s",seed,ticks,phase,msg);
    endtask
    task automatic random_word;
        rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
    endtask
    task automatic hard_reset;
        reset_n=0; reset_request=0; select_ce=0; #1;
        check(dac_sdata===0 && chain_sdata===0,"hard reset must clear pins without a clock");
        phase=0; source_id=0; started=0; pending=0;
        unit_pair=0; chain_pair=0; expected_unit_bit=0; expected_chain_bit=0;
        decoded_unit=0; decoded_chain=0; decode_complete=0;
        resets++; hard_count++;
    endtask
    task automatic tick;
        bit boundary, fall_edge, rise_edge, warm, real_expected;
        int slot_index;
        logic [5:0] payload_index;
        logic [23:0] source_word;
        boundary=phase==0; fall_edge=(phase%32)==0; rise_edge=(phase%32)==16;
        slot_index=(phase%1024)/32;
        warm=boundary && (pending || reset_request);
        random_word(); select_left=24'(rng);
        random_word(); select_right=24'(rng);
        // Selection bus changes every clock, including during right playback;
        // only the pair presented at the left boundary belongs to this slot.
        select_ce=boundary;
        #2;
        check(left_boundary_ce===boundary && sclk_fall_ce===fall_edge &&
              sclk_rise_ce===rise_edge,"timing enables match elapsed-edge oracle");
        check(warm_reset_apply===warm,"reset request coalesces to left boundary");
        real_expected=boundary && started && !warm;
        check(chain_select_ce===boundary,"scheduler boundary selection");
        check(chain_real===real_expected || !boundary,"next-slot real/silence selection");
        for (int config_index=0;config_index<16;config_index++) begin
            check(core_select[config_index]===boundary && core_real[config_index]===real_expected,
                  "depth-matrix pre-edge real/zero selection");
            if (real_expected) check(core_id[config_index]===source_id,"depth-matrix expected frame ID");
        end
        if (real_expected) begin
            check(chain_id===source_id,"preserve frame identity through bypass components");
        end
        check((core_overflow | core_underflow | core_late | core_stall | core_ambiguous)==16'd0,
              "normal component chain must have no data-path faults");
        if (warm) begin
            unit_pair=0; chain_pair=0; source_id=0; started=1; pending=0;
            warm_count++; decode_complete=0;
        end else begin
            if (boundary) begin
                unit_pair={select_left,select_right};
                chain_pair=started ? {sample(source_id,0),sample(source_id,1)} : 48'd0;
                if (started) source_id++;
                started=1; frame_count++;
            end
            if (reset_request) pending=1;
        end
        // Behavioral ADC launches only on falling edges, including arbitrary
        // nonzero tail/padding. RX must ignore those bits.
        if (fall_edge) begin
            if (slot_index>=1 && slot_index<=24) begin
                source_word=sample(source_id,phase>=1024);
                adc_sdata=source_word[24-slot_index];
                payload_index=6'((phase>=1024 ? 0 : 24)+24-slot_index);
                expected_unit_bit=unit_pair[payload_index];
                expected_chain_bit=chain_pair[payload_index];
            end else begin
                adc_sdata=rng[0];
                expected_unit_bit=0; expected_chain_bit=0;
            end
        end
        if (warm) begin expected_unit_bit=0; expected_chain_bit=0; end
        audio_clk=1; #1;
        check(dac_sdata===expected_unit_bit,"standalone serial bit or non-falling-edge stability");
        check(chain_sdata===expected_chain_bit,"bypass serial bit or non-falling-edge stability");
        check(mclk===((phase%8)>=4) && sclk===((phase%32)>=16) && lrck===(phase>=1024),
              "serial clocks must keep running through warm reset");
        // DAC-side reconstruction samples actual data pins on actual SCLK rises.
        if (rise_edge && slot_index>=1 && slot_index<=24) begin
            payload_index=6'((phase>=1024 ? 0 : 24)+24-slot_index);
            decoded_unit[payload_index]=dac_sdata;
            decoded_chain[payload_index]=chain_sdata;
            if (phase==1808) begin
                check(decoded_unit===unit_pair,"decoded standalone L/R expected pair");
                check(decoded_chain===chain_pair,"decoded end-to-end expected pair");
                dac_pairs++; unit_pairs++; decode_complete=1;
            end
        end
        for (int config_index=0;config_index<16;config_index++) begin
            check(core_data[config_index]===expected_chain_bit,"depth-matrix DAC bit");
            check({core_mclk[config_index],core_sclk[config_index],core_lrck[config_index]}==={mclk,sclk,lrck},"depth-matrix clocks");
            check(core_warm[config_index]===warm_reset_apply && core_pending[config_index]===pending,"depth-matrix reset");
            check(core_select[config_index]===left_boundary_ce && core_real[config_index]===core_real[0] &&
                  core_id[config_index]===chain_id,"depth-matrix selection coherence");
        end
        audio_clk=0; #1; phase=(phase+1)%2048; ticks++;
    endtask
    initial begin
        void'($value$plusargs("SEED_%d",seed)); rng=32'(seed);
        hard_reset(); reset_n=1;
        // Directed off-boundary request, boundary request, consecutive requests,
        // right-payload hard reset and a later reset in trailing padding.
        for (int i=0;i<8192;i++) begin
            reset_request=(i==777 || i==778 || i==4096);
            tick();
        end
        reset_request=0;
        repeat(1501) tick(); hard_reset(); reset_n=1;
        repeat(1899) tick(); hard_reset(); reset_n=1;
        // 96 frame units, with qualified random reset requests. Final two
        // complete frames drain the last captured input pair to DAC checking.
        for (int i=0;i<196608;i++) begin
            random_word(); reset_request=(rng[12:0]==0); tick();
        end
        reset_request=0;
        while (phase!=0) tick();
        repeat(4096) tick();
        check(decode_complete && dac_pairs>90 && frame_count>50 && warm_count>2 && hard_count==3,
              $sformatf("coverage pairs=%0d normal_frames=%0d warm=%0d hard=%0d",dac_pairs,frame_count,warm_count,hard_count));
        $display("BYPASS_PASS seed=%0d ticks=%0d decoded_pairs=%0d unit_pairs=%0d warm=%0d hard=%0d resets=%0d",seed,ticks,dac_pairs,unit_pairs,warm_count,hard_count,resets);
        wait(watchdog_done && recovery_done);
        $finish;
    end
    initial begin #2000000; $fatal(1,"BYPASS_FAIL timeout"); end
endmodule
`default_nettype wire
