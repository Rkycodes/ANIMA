`timescale 1ns/1fs
`default_nettype none
module anima_frame_scheduler_tb;
    wire [3:0] done;
    anima_frame_scheduler_case #(.DEPTH(1)) a(done[0]);
    anima_frame_scheduler_case #(.DEPTH(2)) b(done[1]);
    anima_frame_scheduler_case #(.DEPTH(4)) c(done[2]);
    anima_frame_scheduler_case #(.DEPTH(8)) d(done[3]);
    initial begin
        wait (&done);
        $display("SCHEDULER_PASS depths=1,2,4,8"); $finish;
    end
    initial begin #2000000; $fatal(1,"SCHEDULER_FAIL timeout"); end
endmodule
`default_nettype wire
