`timescale 1ns/1fs
`default_nettype none

// One fixed first-build frame period = 2048 processing clocks. Counts use
// pre-edge occupancy/progress: the first nonempty stalled edge is cycle one.
module anima_audio_watchdogs (
    input wire audio_clk,
    input wire reset_n,
    input wire warm_reset_apply,
    input wire rx_nonempty,
    input wire rx_progress,
    input wire tx_nonempty,
    input wire tx_progress,
    output reg recovery_request,
    output reg stall_timeout_event
);
    reg [10:0] rx_cycles, tx_cycles;
    wire rx_stalled = rx_nonempty && !rx_progress;
    wire tx_stalled = tx_nonempty && !tx_progress;
    wire rx_expired = rx_stalled && (rx_cycles == 11'd2047);
    wire tx_expired = tx_stalled && (tx_cycles == 11'd2047);

    always @(posedge audio_clk or negedge reset_n) begin
        if (!reset_n) begin
            rx_cycles <= 11'd0;
            tx_cycles <= 11'd0;
            recovery_request <= 1'b0;
            stall_timeout_event <= 1'b0;
        end else if (warm_reset_apply) begin
            rx_cycles <= 11'd0;
            tx_cycles <= 11'd0;
            recovery_request <= 1'b0;
            stall_timeout_event <= 1'b0;
        end else begin
            stall_timeout_event <= 1'b0;
            if (!recovery_request) begin
                // Empty and progress both restart their own timer. A progress
                // edge at count 2047 prevents expiry, including stale discard.
                rx_cycles <= rx_stalled ? rx_cycles + 11'd1 : 11'd0;
                tx_cycles <= tx_stalled ? tx_cycles + 11'd1 : 11'd0;
                if (rx_expired || tx_expired) begin
                    recovery_request <= 1'b1;
                    stall_timeout_event <= 1'b1;
                end
            end
        end
    end
endmodule

`default_nettype wire
