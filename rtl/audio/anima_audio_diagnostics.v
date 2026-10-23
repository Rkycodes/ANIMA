`timescale 1ns/1fs
`default_nettype none

// Evidence lifetime is independent of audio data/timing reset. Only FPGA
// initialization/reconfiguration asserts diagnostic_reset_n. Clear is qualified
// in audio_clk; no asynchronous button, CDC or recovered-clock detector here.
module anima_audio_diagnostics (
    input wire audio_clk,
    input wire diagnostic_reset_n,
    input wire diagnostic_clear,
    input wire underflow_event,
    input wire overflow_event,
    input wire late_discard_event,
    input wire stall_timeout_event,
    input wire recovered_clock_loss_event,
    output reg [31:0] underflow_count,
    output reg [31:0] overflow_count,
    output reg [31:0] late_discard_count,
    output reg [31:0] stall_timeout_count,
    output reg [31:0] recovered_clock_loss_count,
    output reg fault_sticky
);
    wire any_fault = underflow_event || overflow_event || late_discard_event ||
                     stall_timeout_event || recovered_clock_loss_event;

    function [31:0] next_count;
        input [31:0] current;
        input clear_now;
        input occurrence;
        begin
            // Clear begins a new diagnostic interval on this edge. A new
            // occurrence belongs to it even when the old count was saturated.
            if (clear_now)
                next_count = occurrence ? 32'd1 : 32'd0;
            else if (occurrence && (current != 32'hffffffff))
                next_count = current + 32'd1;
            else
                next_count = current;
        end
    endfunction

    always @(posedge audio_clk or negedge diagnostic_reset_n) begin
        if (!diagnostic_reset_n) begin
            underflow_count <= 32'd0;
            overflow_count <= 32'd0;
            late_discard_count <= 32'd0;
            stall_timeout_count <= 32'd0;
            recovered_clock_loss_count <= 32'd0;
            fault_sticky <= 1'b0;
        end else begin
            underflow_count <= next_count(underflow_count, diagnostic_clear, underflow_event);
            overflow_count <= next_count(overflow_count, diagnostic_clear, overflow_event);
            late_discard_count <= next_count(late_discard_count, diagnostic_clear, late_discard_event);
            stall_timeout_count <= next_count(stall_timeout_count, diagnostic_clear, stall_timeout_event);
            recovered_clock_loss_count <= next_count(recovered_clock_loss_count, diagnostic_clear,
                                                     recovered_clock_loss_event);
            if (diagnostic_clear)
                fault_sticky <= any_fault;
            else if (any_fault)
                fault_sticky <= 1'b1;
        end
    end
endmodule

`default_nettype wire
