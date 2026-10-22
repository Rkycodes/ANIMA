`timescale 1ns/1fs
`default_nettype none

// Assemble one aligned stereo pair; publish an event for next-edge queue ingress.
// Contract: docs/planning.md, "Receiver block contract".
module anima_i2s_receiver (
    input  wire               audio_clk,
    input  wire               reset_n,
    input  wire               warm_reset_apply,
    input  wire               left_boundary_ce,
    input  wire               sclk_rise_ce,
    input  wire [4:0]         slot_bit,
    input  wire               right_slot,
    input  wire               adc_sdata,
    output reg signed [23:0]  left_sample,
    output reg signed [23:0]  right_sample,
    output reg        [31:0]  frame_id,
    output reg                pair_complete
);
    reg capture_active;
    reg left_complete;
    reg [31:0] next_frame_id;

    // reset_n is the RX hard reset, with synchronized release supplied upstream.
    // Holding it low during cold qualification does not hold serial timing reset.
    // All other inputs belong to audio_clk; timing metadata is the fixed contract.
    always @(posedge audio_clk or negedge reset_n) begin
        if (!reset_n) begin
            left_sample <= 24'sd0;
            right_sample <= 24'sd0;
            frame_id <= 32'd0;
            pair_complete <= 1'b0;
            next_frame_id <= 32'd0;
            capture_active <= 1'b0;
            left_complete <= 1'b0;
        end else begin
            // The queue consumes the previous cycle's event and data before
            // this nonblocking clear. This is a pulse, not backpressurable valid.
            pair_complete <= 1'b0;

            if (warm_reset_apply) begin
                left_sample <= 24'sd0;
                right_sample <= 24'sd0;
                frame_id <= 32'd0;
                next_frame_id <= 32'd0;
                left_complete <= 1'b0;
                // The shared controller applies at a left boundary: allow this
                // same interval to become frame zero after reset has won.
                capture_active <= left_boundary_ce;
            end else if (left_boundary_ce) begin
                // Start only with a whole left/right interval, never a partial
                // interval remaining after hard-reset release.
                capture_active <= 1'b1;
                left_complete <= 1'b0;
                left_sample <= 24'sd0;
                right_sample <= 24'sd0;
            end else if (capture_active && sclk_rise_ce &&
                         (slot_bit >= 5'd1) && (slot_bit <= 5'd24)) begin
                // MSB first. Shifting selected payload bits preserves the raw
                // two's-complement pattern; no sign extension or DSP is needed.
                if (!right_slot) begin
                    left_sample <= {left_sample[22:0], adc_sdata};
                    if (slot_bit == 5'd24)
                        left_complete <= 1'b1;
                end else begin
                    right_sample <= {right_sample[22:0], adc_sdata};
                    if ((slot_bit == 5'd24) && left_complete) begin
                        // On final capture edge E, all outputs update together.
                        // At E+1 the queue sees the new R LSB and this exact ID.
                        frame_id <= next_frame_id;
                        next_frame_id <= next_frame_id + 32'd1;
                        pair_complete <= 1'b1;
                    end
                end
            end
        end
    end
endmodule

`default_nettype wire
