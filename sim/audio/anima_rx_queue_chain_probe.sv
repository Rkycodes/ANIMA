`timescale 1ns/1fs
`default_nettype none

// Real receiver/timing/reset -> default-depth queue -> downstream ready.
// The surrounding receiver bench independently checks ADC bits and publication.
module anima_rx_queue_chain_probe (
    input wire audio_clk, reset_n, warm_reset_apply, pair_complete, out_ready,
    input wire signed [23:0] in_left, in_right,
    input wire [31:0] in_frame_id
);
    wire out_valid, overflow_event;
    wire signed [23:0] out_left, out_right;
    wire [31:0] out_frame_id;
    anima_rx_frame_queue dut (.*);
    logic [79:0] expected [$];
    int accepted = 0, rejected = 0, warm_resets = 0;

    task automatic check(input bit condition, input string message);
        if (!condition) begin
            $display("RX_QUEUE_FAIL chain: %s", message);
            $fatal(1, "receiver/queue integration failed");
        end
    endtask
    task automatic check_head;
        bit valid_expected;
        valid_expected = reset_n && !warm_reset_apply && expected.size() != 0;
        check(out_valid === valid_expected, "valid/empty mismatch");
        if (valid_expected)
            check({out_frame_id, out_left, out_right} === expected[0], "stored pair order/data/ID mismatch");
        else check({out_frame_id, out_left, out_right} === 80'd0, "invalid output not zero");
    endtask
    always @(posedge audio_clk or negedge reset_n) begin : scoreboard
        bit pop, reject;
        check_head();
        pop = reset_n && !warm_reset_apply && expected.size() != 0 && out_ready;
        reject = reset_n && !warm_reset_apply && pair_complete && expected.size() == 2 && !pop;
        check(overflow_event === reject, "overflow edge or reset priority mismatch");
        if (!reset_n || warm_reset_apply) begin
            expected.delete();
            if (reset_n && warm_reset_apply) warm_resets <= warm_resets + 1;
        end else begin
            if (pop) begin void'(expected.pop_front()); accepted <= accepted + 1; end
            if (pair_complete) begin
                if (reject) rejected <= rejected + 1;
                else expected.push_back({in_frame_id, in_left, in_right});
            end
        end
        #0.000001;
        check_head();
    end
    task automatic report(input int seed);
        check(expected.size() == 0 && !out_valid, "undrained final queue");
        check(accepted > 258 && rejected >= 2 && warm_resets >= 9, "chain coverage missing");
        $display("RX_QUEUE_CHAIN_PASS seed=%0d accepted=%0d overflow=%0d warm=%0d", seed, accepted, rejected, warm_resets);
    endtask
endmodule

`default_nettype wire
