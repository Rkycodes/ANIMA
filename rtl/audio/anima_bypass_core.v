`timescale 1ns/1fs
`default_nettype none

// Processing-clock bypass core, not a board clock generator or pad wrapper.
module anima_bypass_core #(
    parameter integer RX_DEPTH = 2,
    parameter integer TX_WAIT_DEPTH = 1
) (
    input wire audio_clk,
    input wire reset_n,
    input wire data_reset_n,
    input wire reset_request,
    input wire adc_sdata,
    input wire diagnostic_reset_n,
    input wire diagnostic_clear,
    input wire recovered_clock_loss_event,
    output wire mclk,
    output wire sclk,
    output wire lrck,
    output wire dac_sdata,
    output wire warm_reset_apply,
    output wire reset_pending,
    output wire overflow_event,
    output wire underflow_event,
    output wire late_discard_event,
    output wire stall_timeout_event,
    output wire ambiguous_id_event,
    output wire frame_select_ce,
    output wire frame_real,
    output wire [31:0] frame_id,
    output wire [31:0] underflow_count,
    output wire [31:0] overflow_count,
    output wire [31:0] late_discard_count,
    output wire [31:0] stall_timeout_count,
    output wire [31:0] recovered_clock_loss_count,
    output wire fault_sticky
);
    wire data_active_n = reset_n && data_reset_n;
    wire [10:0] unused_phase_cycle;
    wire sclk_rise_ce, sclk_fall_ce, left_boundary_ce, right_slot;
    wire [4:0] slot_bit;
    anima_serial_timing timing (.audio_clk(audio_clk), .reset_n(reset_n),
        .phase_cycle(unused_phase_cycle), .mclk(mclk), .sclk(sclk), .lrck(lrck),
        .sclk_rise_ce(sclk_rise_ce), .sclk_fall_ce(sclk_fall_ce),
        .left_boundary_ce(left_boundary_ce), .slot_bit(slot_bit), .right_slot(right_slot));

    wire recovery_request;
    wire combined_request = reset_request || recovery_request;
    anima_warm_reset_controller reset_control (.audio_clk(audio_clk),
        .reset_n(data_active_n), .reset_request(combined_request),
        .left_boundary_ce(left_boundary_ce), .reset_pending(reset_pending),
        .warm_reset_apply(warm_reset_apply));

    wire signed [23:0] left_sample, right_sample;
    wire [31:0] rx_frame_id;
    wire pair_complete;
    anima_i2s_receiver receiver (.audio_clk(audio_clk), .reset_n(data_active_n),
        .warm_reset_apply(warm_reset_apply), .left_boundary_ce(left_boundary_ce),
        .sclk_rise_ce(sclk_rise_ce), .slot_bit(slot_bit), .right_slot(right_slot),
        .adc_sdata(adc_sdata), .left_sample(left_sample), .right_sample(right_sample),
        .frame_id(rx_frame_id), .pair_complete(pair_complete));

    wire rx_valid, rx_ready;
    wire signed [23:0] rx_left, rx_right;
    wire [31:0] rx_id;
    anima_rx_frame_queue #(.DEPTH(RX_DEPTH)) rx_queue (.audio_clk(audio_clk),
        .reset_n(data_active_n), .warm_reset_apply(warm_reset_apply),
        .pair_complete(pair_complete), .in_left(left_sample), .in_right(right_sample),
        .in_frame_id(rx_frame_id), .out_valid(rx_valid), .out_ready(rx_ready),
        .out_left(rx_left), .out_right(rx_right), .out_frame_id(rx_id),
        .overflow_event(overflow_event));

    wire signed [23:0] selected_left, selected_right;
    wire waiting_nonempty, waiting_progress;
    anima_frame_scheduler #(.TX_WAIT_DEPTH(TX_WAIT_DEPTH)) scheduler (
        .audio_clk(audio_clk), .reset_n(data_active_n), .warm_reset_apply(warm_reset_apply),
        .left_boundary_ce(left_boundary_ce), .in_valid(rx_valid), .in_ready(rx_ready),
        .in_left(rx_left), .in_right(rx_right), .in_frame_id(rx_id),
        .select_ce(frame_select_ce), .select_real(frame_real), .select_left(selected_left),
        .select_right(selected_right), .select_frame_id(frame_id),
        .underflow_event(underflow_event), .late_discard_event(late_discard_event),
        .ambiguous_id_event(ambiguous_id_event), .waiting_nonempty(waiting_nonempty),
        .waiting_progress(waiting_progress));

    anima_i2s_transmitter transmitter (.audio_clk(audio_clk), .reset_n(data_active_n),
        .warm_reset_apply(warm_reset_apply), .select_ce(frame_select_ce),
        .select_left(selected_left), .select_right(selected_right),
        .sclk_fall_ce(sclk_fall_ce), .slot_bit(slot_bit), .right_slot(right_slot),
        .dac_sdata(dac_sdata));

    wire rx_progress = rx_valid && rx_ready;
    anima_audio_watchdogs watchdogs (.audio_clk(audio_clk), .reset_n(data_active_n),
        .warm_reset_apply(warm_reset_apply), .rx_nonempty(rx_valid),
        .rx_progress(rx_progress), .tx_nonempty(waiting_nonempty),
        .tx_progress(waiting_progress), .recovery_request(recovery_request),
        .stall_timeout_event(stall_timeout_event));
    // Do not substitute data_active_n or reset_n for diagnostic_reset_n:
    // fault evidence must survive normal/recoverable audio reset.
    anima_audio_diagnostics diagnostics (.audio_clk(audio_clk),
        .diagnostic_reset_n(diagnostic_reset_n), .diagnostic_clear(diagnostic_clear),
        .underflow_event(underflow_event), .overflow_event(overflow_event),
        .late_discard_event(late_discard_event), .stall_timeout_event(stall_timeout_event),
        .recovered_clock_loss_event(recovered_clock_loss_event),
        .underflow_count(underflow_count), .overflow_count(overflow_count),
        .late_discard_count(late_discard_count), .stall_timeout_count(stall_timeout_count),
        .recovered_clock_loss_count(recovered_clock_loss_count), .fault_sticky(fault_sticky));
endmodule

`default_nettype wire
