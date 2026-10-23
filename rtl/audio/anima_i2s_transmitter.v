`timescale 1ns/1fs
`default_nettype none

// Scheduler selection is a whole-pair pre-edge boundary transaction.
// Codec clocks continue independently; this block drives serial data only.
module anima_i2s_transmitter (
    input wire audio_clk,
    input wire reset_n,
    input wire warm_reset_apply,
    input wire select_ce,
    input wire signed [23:0] select_left,
    input wire signed [23:0] select_right,
    input wire sclk_fall_ce,
    input wire [4:0] slot_bit,
    input wire right_slot,
    output reg dac_sdata
);
    reg signed [23:0] current_left, current_right;
    wire payload_bit = (slot_bit >= 5'd1) && (slot_bit <= 5'd24);
    wire [4:0] sample_bit = 5'd24 - slot_bit;

    always @(posedge audio_clk or negedge reset_n) begin
        if (!reset_n) begin
            current_left <= 24'sd0;
            current_right <= 24'sd0;
            dac_sdata <= 1'b0;
        end else if (warm_reset_apply) begin
            // Shared warm application occurs at a left boundary, after the
            // preceding right payload has finished. Never mix reset epochs.
            current_left <= 24'sd0;
            current_right <= 24'sd0;
            dac_sdata <= 1'b0;
        end else begin
            if (select_ce) begin
                current_left <= select_left;
                current_right <= select_right;
            end
            if (sclk_fall_ce) begin
                // Slot zero is the preceding word's tail. The new MSB is
                // launched at slot one, a whole SCLK period after LRCK changes.
                if (payload_bit)
                    dac_sdata <= right_slot ? current_right[sample_bit] : current_left[sample_bit];
                else
                    dac_sdata <= 1'b0;
            end
        end
    end
endmodule

`default_nettype wire
