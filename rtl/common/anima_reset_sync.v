`timescale 1ns/1fs
`default_nettype none
module anima_reset_sync (
    input wire clk,
    input wire async_reset_n,
    output wire reset_n
);
    (* ASYNC_REG = "TRUE" *) reg [1:0] release_pipe;
    always @(posedge clk or negedge async_reset_n) begin
        if (!async_reset_n) release_pipe <= 2'b00;
        else release_pipe <= {release_pipe[0],1'b1};
    end
    assign reset_n = release_pipe[1];
endmodule
`default_nettype wire
