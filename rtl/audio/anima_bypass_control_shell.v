`timescale 1ns/1fs
`default_nettype none

// Logical board-control/clock-supervision shell. Clock generation, physical
// clock routing and complete audio I/O constraints remain an external build.
module anima_bypass_control_shell #(
    parameter integer RX_DEPTH=2,
    parameter integer TX_WAIT_DEPTH=1,
    parameter integer BUTTON_STABLE_CYCLES=983051,
    parameter integer HEARTBEAT_CYCLES=64,
    parameter integer TIMEOUT_REF_CYCLES=1024,
    parameter integer MMCM_RESET_REF_CYCLES=16,
    parameter integer STARTUP_AUDIO_CYCLES=98305085
) (
    input wire ref_clk,
    input wire audio_clk,
    input wire initial_reset_n,
    input wire mmcm_locked,
    input wire button_center,
    input wire button_down,
    input wire adc_sdata,
    output wire mmcm_reset,
    output wire led0,
    output wire mclk,
    output wire sclk,
    output wire lrck,
    output wire dac_sdata,
    output wire timing_reset_n,
    output wire data_reset_n,
    output wire loss_pending,
    output wire [31:0] underflow_count,
    output wire [31:0] overflow_count,
    output wire [31:0] late_discard_count,
    output wire [31:0] stall_timeout_count,
    output wire [31:0] recovered_clock_loss_count
);
    wire diagnostic_reset_n, recovered_clock_loss_event, frame_select_ce;
    wire reset_request, diagnostic_clear;
    wire unused_warm, unused_pending, unused_overflow, unused_underflow;
    wire unused_late, unused_stall, unused_ambiguous, unused_real;
    wire [31:0] unused_frame_id;
    anima_clock_supervisor #(.HEARTBEAT_CYCLES(HEARTBEAT_CYCLES),
        .TIMEOUT_REF_CYCLES(TIMEOUT_REF_CYCLES), .MMCM_RESET_REF_CYCLES(MMCM_RESET_REF_CYCLES),
        .STARTUP_AUDIO_CYCLES(STARTUP_AUDIO_CYCLES)) clocks (
        .ref_clk(ref_clk), .audio_clk(audio_clk), .initial_reset_n(initial_reset_n),
        .mmcm_locked(mmcm_locked), .codec_lrck(lrck), .frame_select_ce(frame_select_ce),
        .mmcm_reset(mmcm_reset), .timing_reset_n(timing_reset_n), .data_reset_n(data_reset_n),
        .diagnostic_reset_n(diagnostic_reset_n), .loss_pending(loss_pending),
        .recovered_clock_loss_event(recovered_clock_loss_event));
    anima_button_event #(.STABLE_CYCLES(BUTTON_STABLE_CYCLES)) reset_button (
        .clk(audio_clk), .reset_n(data_reset_n), .button_async(button_center), .press_event(reset_request));
    anima_button_event #(.STABLE_CYCLES(BUTTON_STABLE_CYCLES)) clear_button (
        .clk(audio_clk), .reset_n(data_reset_n), .button_async(button_down), .press_event(diagnostic_clear));
    anima_bypass_core #(.RX_DEPTH(RX_DEPTH), .TX_WAIT_DEPTH(TX_WAIT_DEPTH)) core (
        .audio_clk(audio_clk), .reset_n(timing_reset_n), .data_reset_n(data_reset_n),
        .reset_request(reset_request), .adc_sdata(adc_sdata),
        .diagnostic_reset_n(diagnostic_reset_n), .diagnostic_clear(diagnostic_clear),
        .recovered_clock_loss_event(recovered_clock_loss_event), .mclk(mclk), .sclk(sclk), .lrck(lrck),
        .dac_sdata(dac_sdata), .warm_reset_apply(unused_warm), .reset_pending(unused_pending),
        .overflow_event(unused_overflow), .underflow_event(unused_underflow),
        .late_discard_event(unused_late), .stall_timeout_event(unused_stall),
        .ambiguous_id_event(unused_ambiguous), .frame_select_ce(frame_select_ce),
        .frame_real(unused_real), .frame_id(unused_frame_id),
        .underflow_count(underflow_count), .overflow_count(overflow_count),
        .late_discard_count(late_discard_count), .stall_timeout_count(stall_timeout_count),
        .recovered_clock_loss_count(recovered_clock_loss_count), .fault_sticky(led0));
endmodule
`default_nettype wire
