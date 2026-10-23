`timescale 1ns/1fs
`default_nettype none

// Complete-pair ingress event to stable stored-head valid/ready.
// Contract: docs/planning.md, "RX frame queue block contract".
module anima_rx_frame_queue #(
    parameter integer DEPTH = 2
) (
    input  wire              audio_clk,
    input  wire              reset_n,
    input  wire              warm_reset_apply,
    input  wire              pair_complete,
    input  wire signed [23:0] in_left,
    input  wire signed [23:0] in_right,
    input  wire       [31:0] in_frame_id,
    output wire              out_valid,
    input  wire              out_ready,
    output wire signed [23:0] out_left,
    output wire signed [23:0] out_right,
    output wire       [31:0] out_frame_id,
    output wire              overflow_event
);
    // Verilog-2001 constant function; at least one bit even for depth 1.
    function integer bits_for;
        input integer maximum;
        integer remaining;
        begin
            bits_for = 1;
            remaining = maximum;
            while (remaining > 1) begin
                remaining = remaining >> 1;
                bits_for = bits_for + 1;
            end
        end
    endfunction
    localparam integer PTR_WIDTH = bits_for(DEPTH - 1);
    localparam integer COUNT_WIDTH = bits_for(DEPTH);
    localparam integer LAST_INDEX = DEPTH - 1;
    localparam [PTR_WIDTH-1:0] LAST_PTR = LAST_INDEX[PTR_WIDTH-1:0];
    localparam [COUNT_WIDTH-1:0] FULL_COUNT = DEPTH[COUNT_WIDTH-1:0];

    // Deliberately unresolved only for invalid configurations: fail elaboration
    // instead of silently supporting an unreviewed depth or zero-width pointer.
    generate
        if ((DEPTH != 1) && (DEPTH != 2) && (DEPTH != 4) && (DEPTH != 8)) begin : invalid_depth
            ANIMA_RX_QUEUE_DEPTH_MUST_BE_1_2_4_OR_8 configuration_error ();
        end
    endgenerate

    reg [79:0] storage [0:DEPTH-1];
    reg [PTR_WIDTH-1:0] read_ptr;
    reg [PTR_WIDTH-1:0] write_ptr;
    reg [COUNT_WIDTH-1:0] count;
    wire active = reset_n && !warm_reset_apply;
    wire dequeue = out_valid && out_ready;
    wire room = (count < FULL_COUNT) || dequeue;
    wire enqueue = active && pair_complete && room;

    // Count and stored data, not incoming data or ready, determine this head.
    // A new enqueue becomes visible after Q and is first consumable at Q+1.
    assign out_valid = active && (count != {COUNT_WIDTH{1'b0}});
    assign out_frame_id = out_valid ? storage[read_ptr][79:48] : 32'd0;
    assign out_left = out_valid ? $signed(storage[read_ptr][47:24]) : 24'sd0;
    assign out_right = out_valid ? $signed(storage[read_ptr][23:0]) : 24'sd0;
    assign overflow_event = active && pair_complete && !room;

    always @(posedge audio_clk or negedge reset_n) begin
        if (!reset_n) begin
            read_ptr <= {PTR_WIDTH{1'b0}};
            write_ptr <= {PTR_WIDTH{1'b0}};
            count <= {COUNT_WIDTH{1'b0}};
        end else if (warm_reset_apply) begin
            read_ptr <= {PTR_WIDTH{1'b0}};
            write_ptr <= {PTR_WIDTH{1'b0}};
            count <= {COUNT_WIDTH{1'b0}};
        end else begin
            if (enqueue) begin
                storage[write_ptr] <= {in_frame_id, in_left, in_right};
                write_ptr <= (write_ptr == LAST_PTR) ? {PTR_WIDTH{1'b0}} : write_ptr + 1'b1;
            end
            if (dequeue)
                read_ptr <= (read_ptr == LAST_PTR) ? {PTR_WIDTH{1'b0}} : read_ptr + 1'b1;
            case ({enqueue, dequeue})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: begin end // Neither or both: occupancy stays unchanged.
            endcase
        end
    end
endmodule

`default_nettype wire
