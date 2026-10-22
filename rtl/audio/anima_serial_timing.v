`timescale 1ns/1fs
`default_nettype none

// Serial timing for the fixed first-build clock ratios.
// Contract: docs/planning.md, "Serial-timing block contract".
// All state uses audio_clk. mclk/sclk/lrck are output waveforms, not internal clocks.
module anima_serial_timing (
    input  wire        audio_clk,
    input  wire        reset_n,
    output reg  [10:0] phase_cycle,
    output reg         mclk,
    output reg         sclk,
    output reg         lrck,
    output wire        sclk_rise_ce,
    output wire        sclk_fall_ce,
    output wire        left_boundary_ce,
    output wire [4:0]  slot_bit,
    output wire        right_slot
);
    // Fixed first-build relationships (processing-clock periods):
    // MCLK period = 8; SCLK period = 32; channel slot = 1024; stereo frame = 2048.
    // phase_cycle is UNSIGNED and labels the edge ABOUT TO execute: 0..2047.
    localparam [10:0] FIRST_PHASE = 11'd0;

    // reset_n is an active-low HARD timing reset: asynchronous assertion,
    // release synchronized to audio_clk by the eventual clock/reset supervisor.
    // A normal warm audio reset must NOT reset this block or stop codec clocks.
    always @(posedge audio_clk or negedge reset_n) begin
        if (!reset_n) begin
            phase_cycle <= FIRST_PHASE;
        end else begin
            // The explicitly sized unsigned addition wraps naturally at 2048.
            phase_cycle <= phase_cycle + 11'd1;
        end
    end

    // Registered serial pins. These assignments read the PRE-EDGE phase value.
    // At edge p, pins must become:
    //   MCLK: low 4 cycles, high 4 cycles, repeat.
    //   SCLK: low 16 cycles, high 16 cycles, repeat.
    //   LRCK: low 1024 cycles (left), high 1024 cycles (right), repeat.
    // Binary counter bits provide these divisions; no gated internal clocks.
    always @(posedge audio_clk or negedge reset_n) begin
        if (!reset_n) begin
            mclk <= 1'b0;
            sclk <= 1'b0;
            lrck <= 1'b0;
        end else begin
            // Nonblocking assignments all use the same pre-edge phase.
            mclk <= phase_cycle[2];
            sclk <= phase_cycle[4];
            lrck <= phase_cycle[10];
        end
    end

    // Combinational enables describe the UPCOMING processing edge.
    // A receiver/transmitter samples them on that same audio_clk rising edge.
    //   SCLK fall: p = 0, 32, 64, ...
    //   SCLK rise: p = 16, 48, 80, ...
    //   Left boundary: p = 0 only.
    // Gate every enable with reset_n so none is asserted during hard reset.
    // Do not register these a cycle late; the bench checks PRE-EDGE visibility.
    assign sclk_rise_ce     = reset_n && (phase_cycle[4:0] == 5'd16);
    assign sclk_fall_ce     = reset_n && (phase_cycle[4:0] == 5'd0);
    assign left_boundary_ce = reset_n && (phase_cycle == FIRST_PHASE);

    // Unsigned metadata describes that same upcoming edge.
    // slot_bit = 0..31 within one channel; right_slot = 0 left / 1 right.
    // Slot position 0 is the I2S preceding-word tail. Payload positions are 1..24;
    // the seven remaining positions are padding. These are not sample bits yet.
    // Both metadata outputs must be zero during hard reset.
    assign slot_bit   = reset_n ? phase_cycle[9:5] : 5'd0;
    assign right_slot = reset_n && phase_cycle[10];
endmodule

`default_nettype wire
