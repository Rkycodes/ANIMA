`timescale 1ns/1fs
`default_nettype none

// Schedule qualified audio reset requests without stopping codec timing.
// Contract: docs/planning.md, "Warm-reset controller interface".
module anima_warm_reset_controller (
    input  wire audio_clk,
    input  wire reset_n,
    input  wire reset_request,
    input  wire left_boundary_ce,
    output reg  reset_pending,
    output wire warm_reset_apply
);
    // All inputs except hard-reset assertion belong to audio_clk.
    // reset_request is a qualified event, normally one processing-clock cycle.
    // A raw button or asynchronous request must be conditioned upstream.
    // Repeated requests before application coalesce into one pending reset.
    // reset_n asserts asynchronously; release must be synchronized upstream.
    always @(posedge audio_clk or negedge reset_n) begin
        if (!reset_n) begin
            reset_pending <= 1'b0;
        end else if (warm_reset_apply) begin
            // A request on the application edge is included in this reset.
            reset_pending <= 1'b0;
        end else if (reset_request) begin
            reset_pending <= 1'b1;
        end
    end

    // Visible BEFORE the boundary edge so every audio-data consumer can give
    // reset priority over its normal transfer on that same edge. Registering
    // this output would delay those consumers until after the selected boundary.
    assign warm_reset_apply = reset_n && left_boundary_ce &&
                              (reset_pending || reset_request);

    // This output must never drive the timing block's hard reset or clocks.
    // Diagnostics also have a separate reset lifetime. RX/queues/TX consumers
    // will perform the actual flush and frame-number restart when integrated.
endmodule

`default_nettype wire
