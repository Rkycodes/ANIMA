`timescale 1ns/1fs
`default_nettype none

// Reference-clock loss supervision survives a stopped audio clock. The MMCM
// itself remains external. One recovery mailbox coalesces repeated failures
// until qualified audio has restarted and its diagnostic event is acknowledged.
module anima_clock_supervisor #(
    parameter integer HEARTBEAT_CYCLES = 64,
    parameter integer TIMEOUT_REF_CYCLES = 1024,
    parameter integer MMCM_RESET_REF_CYCLES = 16,
    parameter integer STARTUP_AUDIO_CYCLES = 98305085
) (
    input wire ref_clk,
    input wire audio_clk,
    input wire initial_reset_n,
    input wire mmcm_locked,
    input wire codec_lrck,
    input wire frame_select_ce,
    output reg mmcm_reset,
    output wire timing_reset_n,
    output wire data_reset_n,
    output wire diagnostic_reset_n,
    output reg loss_pending,
    output reg recovered_clock_loss_event
);
    function integer bits_for;
        input integer maximum;
        integer remaining;
        begin
            bits_for=1; remaining=maximum;
            while(remaining>1) begin remaining=remaining>>1; bits_for=bits_for+1; end
        end
    endfunction
    localparam integer HB_W=bits_for(HEARTBEAT_CYCLES-1);
    localparam integer AGE_W=bits_for(TIMEOUT_REF_CYCLES-1);
    localparam integer HOLD_W=bits_for(MMCM_RESET_REF_CYCLES-1);
    localparam integer GUARD_W=bits_for(STARTUP_AUDIO_CYCLES-1);
    localparam integer HB_LAST_I=HEARTBEAT_CYCLES-1, AGE_LAST_I=TIMEOUT_REF_CYCLES-1;
    localparam integer HOLD_LAST_I=MMCM_RESET_REF_CYCLES-1, GUARD_LAST_I=STARTUP_AUDIO_CYCLES-1;
    localparam [HB_W-1:0] HB_LAST=HB_LAST_I[HB_W-1:0];
    localparam [AGE_W-1:0] AGE_LAST=AGE_LAST_I[AGE_W-1:0];
    localparam [HOLD_W-1:0] HOLD_LAST=HOLD_LAST_I[HOLD_W-1:0];
    localparam [GUARD_W-1:0] GUARD_LAST=GUARD_LAST_I[GUARD_W-1:0];
    localparam [1:0] RESET=2'd0, WAIT_CLOCK=2'd1, RUN=2'd2;
    generate if(HEARTBEAT_CYCLES<4 || TIMEOUT_REF_CYCLES<32 || TIMEOUT_REF_CYCLES/8<HEARTBEAT_CYCLES ||
                MMCM_RESET_REF_CYCLES<1 || STARTUP_AUDIO_CYCLES<1) begin : invalid_config
        ANIMA_CLOCK_SUPERVISOR_INVALID_PARAMETERS invalid_configuration ();
    end endgenerate

    wire ref_reset_n, locked_ref;
    anima_reset_sync reference_reset (.clk(ref_clk), .async_reset_n(initial_reset_n), .reset_n(ref_reset_n));
    // A short LOCKED drop asynchronously empties this release pipeline, so it
    // remains visible to reference logic even if LOCKED returns between edges.
    anima_reset_sync lock_qualification (.clk(ref_clk),
        .async_reset_n(initial_reset_n && mmcm_locked), .reset_n(locked_ref));
    anima_reset_sync diagnostic_reset (.clk(audio_clk), .async_reset_n(initial_reset_n),
        .reset_n(diagnostic_reset_n));

    reg [HB_W-1:0] heartbeat_count;
    reg heartbeat;
    always @(posedge audio_clk or negedge diagnostic_reset_n) begin
        if(!diagnostic_reset_n) begin heartbeat_count<=0; heartbeat<=0; end
        else if(heartbeat_count==HB_LAST) begin heartbeat_count<=0; heartbeat<=!heartbeat; end
        else heartbeat_count<=heartbeat_count+1'b1;
    end
    (* ASYNC_REG = "TRUE" *) reg [1:0] heartbeat_sync, ready_sync, ack_sync;
    reg heartbeat_last, saw_heartbeat, recovery_request;
    reg [1:0] state;
    reg [AGE_W-1:0] heartbeat_age;
    reg [HOLD_W-1:0] reset_hold;
    wire heartbeat_change=heartbeat_sync[1]!=heartbeat_last;
    wire heartbeat_expired=!heartbeat_change && heartbeat_age==AGE_LAST;
    wire clock_good_async=initial_reset_n && mmcm_locked && locked_ref && state==RUN;
    reg recovery_ack;

    anima_reset_sync timing_release (.clk(audio_clk), .async_reset_n(clock_good_async),
        .reset_n(timing_reset_n));
    reg codec_started, guard_done;
    reg [GUARD_W-1:0] guard_count;
    always @(posedge audio_clk or negedge timing_reset_n) begin
        if(!timing_reset_n) begin codec_started<=0; guard_done<=0; guard_count<=0; end
        else if(!codec_started) begin
            // Start AFTER LRCK first becomes high: MCLK/SCLK/LRCK have all run.
            if(codec_lrck) codec_started<=1;
        end else if(!guard_done) begin
            if(guard_count==GUARD_LAST) guard_done<=1;
            else guard_count<=guard_count+1'b1;
        end
    end
    anima_reset_sync data_release (.clk(audio_clk),
        .async_reset_n(timing_reset_n && guard_done), .reset_n(data_reset_n));
    reg audio_aligned;
    always @(posedge audio_clk or negedge data_reset_n) begin
        if(!data_reset_n) audio_aligned<=0;
        else if(frame_select_ce) audio_aligned<=1;
    end

    always @(posedge ref_clk or negedge ref_reset_n) begin
        if(!ref_reset_n) begin
            heartbeat_sync<=0; ready_sync<=0; ack_sync<=0;
            heartbeat_last<=0; saw_heartbeat<=0; heartbeat_age<=0; reset_hold<=0;
            state<=RESET; mmcm_reset<=1; loss_pending<=0; recovery_request<=0;
        end else begin
            heartbeat_sync<={heartbeat_sync[0],heartbeat};
            ready_sync<={ready_sync[0],audio_aligned};
            ack_sync<={ack_sync[0],recovery_ack};
            heartbeat_last<=heartbeat_sync[1];
            // Four-phase level handshake: request is not withdrawn until the
            // event was consumed by diagnostics AND current restart is aligned.
            if(recovery_request && ack_sync[1] && ready_sync[1] && state==RUN && locked_ref && !heartbeat_expired) begin
                recovery_request<=0; loss_pending<=0;
            end else if(loss_pending && !recovery_request && !ack_sync[1] &&
                        ready_sync[1] && state==RUN && locked_ref && !heartbeat_expired) recovery_request<=1;
            case(state)
                RESET: begin
                    heartbeat_age<=0; saw_heartbeat<=0;
                    if(reset_hold==HOLD_LAST) begin
                        reset_hold<=0; mmcm_reset<=0; state<=WAIT_CLOCK;
                    end else reset_hold<=reset_hold+1'b1;
                end
                WAIT_CLOCK: begin
                    if(!locked_ref) begin heartbeat_age<=0; saw_heartbeat<=0; end
                    else if(heartbeat_change) begin
                        heartbeat_age<=0;
                        if(saw_heartbeat) state<=RUN;
                        else saw_heartbeat<=1;
                    end else if(heartbeat_expired) begin
                        state<=RESET; mmcm_reset<=1; reset_hold<=0;
                    end else heartbeat_age<=heartbeat_age+1'b1;
                end
                RUN: begin
                    if(!locked_ref || heartbeat_expired) begin
                        state<=RESET; mmcm_reset<=1; reset_hold<=0;
                        heartbeat_age<=0; loss_pending<=1;
                    end else if(heartbeat_change) heartbeat_age<=0;
                    else heartbeat_age<=heartbeat_age+1'b1;
                end
                default: begin state<=RESET; mmcm_reset<=1; reset_hold<=0; end
            endcase
        end
    end

    (* ASYNC_REG = "TRUE" *) reg [1:0] request_sync;
    // This mailbox resets ONLY on initialization. If audio stops while the
    // pulse is high, it remains high until the next edge actually counts it.
    always @(posedge audio_clk or negedge diagnostic_reset_n) begin
        if(!diagnostic_reset_n) begin
            request_sync<=0; recovery_ack<=0; recovered_clock_loss_event<=0;
        end else begin
            request_sync<={request_sync[0],recovery_request};
            recovered_clock_loss_event<=0;
            if(recovered_clock_loss_event) recovery_ack<=1;
            else if(!request_sync[1]) recovery_ack<=0;
            else if(!recovery_ack && audio_aligned && frame_select_ce)
                recovered_clock_loss_event<=1;
        end
    end
endmodule
`default_nettype wire
