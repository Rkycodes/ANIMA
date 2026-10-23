`timescale 1ns/1fs
`default_nettype none

// Owns next-due waiting storage. Selection is a PRE-EDGE transaction:
// TX samples select_ce and the whole payload on the boundary edge.
module anima_frame_scheduler #(
    parameter integer TX_WAIT_DEPTH = 1
) (
    input wire audio_clk,
    input wire reset_n,
    input wire warm_reset_apply,
    input wire left_boundary_ce,
    input wire in_valid,
    output wire in_ready,
    input wire signed [23:0] in_left,
    input wire signed [23:0] in_right,
    input wire [31:0] in_frame_id,
    output wire select_ce,
    output wire select_real,
    output wire signed [23:0] select_left,
    output wire signed [23:0] select_right,
    output wire [31:0] select_frame_id,
    output wire underflow_event,
    output wire late_discard_event,
    output wire ambiguous_id_event,
    output wire waiting_nonempty,
    output wire waiting_progress
);
    generate
        if ((TX_WAIT_DEPTH != 1) && (TX_WAIT_DEPTH != 2) &&
            (TX_WAIT_DEPTH != 4) && (TX_WAIT_DEPTH != 8)) begin : invalid_depth
            ANIMA_TX_WAIT_DEPTH_MUST_BE_1_2_4_OR_8 configuration_error ();
        end
    endgenerate

    // Only the next unfilled slot may be reserved. Additional configured
    // capacity cannot authorize future prefetch; one physical entry suffices.
    reg started;
    reg [31:0] expected_id;
    reg waiting_valid;
    reg signed [23:0] waiting_left, waiting_right;
    wire active = reset_n && !warm_reset_apply;
    wire boundary = active && left_boundary_ce && started;
    wire [31:0] next_id = expected_id + 32'd1;
    // A stored due pair fills this deadline. On its promotion edge only,
    // admission can instead reserve the immediately following slot.
    wire [31:0] admission_id = (boundary && waiting_valid) ? next_id : expected_id;
    wire [31:0] difference = in_frame_id - admission_id;
    wire ambiguous = difference == 32'h80000000;
    wire late = difference[31] && !ambiguous;
    wire due = difference == 32'd0;
    wire room = !waiting_valid || boundary;
    wire transfer = in_valid && in_ready;
    wire direct = boundary && !waiting_valid && transfer && due;

    // Observe waiting ownership, excluding current TX serialization.
    assign waiting_nonempty = active && waiting_valid;
    assign waiting_progress = boundary && waiting_valid;
    assign in_ready = active && started && !ambiguous && (late || (due && room));
    assign select_ce = reset_n && left_boundary_ce;
    assign select_real = boundary && (waiting_valid || direct);
    assign select_left = select_real ? (waiting_valid ? waiting_left : in_left) : 24'sd0;
    assign select_right = select_real ? (waiting_valid ? waiting_right : in_right) : 24'sd0;
    assign select_frame_id = boundary ? expected_id : 32'd0;
    assign underflow_event = boundary && !select_real;
    assign late_discard_event = active && transfer && late;
    // Contract violation: integration must assert this is absent. Never play it.
    assign ambiguous_id_event = active && started && in_valid && ambiguous;

    always @(posedge audio_clk or negedge reset_n) begin
        if (!reset_n) begin
            started <= 1'b0;
            expected_id <= 32'd0;
            waiting_valid <= 1'b0;
            waiting_left <= 24'sd0;
            waiting_right <= 24'sd0;
        end else if (warm_reset_apply) begin
            // Application is boundary-qualified upstream; this boundary starts
            // fresh frame-zero capture, with playback due one boundary later.
            started <= left_boundary_ce;
            expected_id <= 32'd0;
            waiting_valid <= 1'b0;
            waiting_left <= 24'sd0;
            waiting_right <= 24'sd0;
        end else begin
            if (left_boundary_ce) begin
                started <= 1'b1;
                if (started) expected_id <= next_id;
            end
            if (boundary) waiting_valid <= 1'b0;
            if (transfer && due && !direct) begin
                waiting_left <= in_left;
                waiting_right <= in_right;
                waiting_valid <= 1'b1;
            end
        end
    end
endmodule

`default_nettype wire
