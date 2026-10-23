`timescale 1ns/1fs
`default_nettype none

// Active-high button, stable press/release filter and one event per press.
// Reset requires a qualified release before arming: a held button cannot
// become a fresh command after startup or recoverable clock reset.
module anima_button_event #(
    parameter integer STABLE_CYCLES = 983051
) (
    input wire clk,
    input wire reset_n,
    input wire button_async,
    output reg press_event
);
    function integer bits_for;
        input integer maximum;
        integer remaining;
        begin
            bits_for=1; remaining=maximum;
            while(remaining>1) begin remaining=remaining>>1; bits_for=bits_for+1; end
        end
    endfunction
    localparam integer WIDTH=bits_for(STABLE_CYCLES-1);
    localparam integer LAST_VALUE=STABLE_CYCLES-1;
    localparam [WIDTH-1:0] LAST=LAST_VALUE[WIDTH-1:0];
    generate if(STABLE_CYCLES<1) begin : invalid_cycles
        ANIMA_BUTTON_STABLE_CYCLES_MUST_BE_POSITIVE invalid_configuration ();
    end endgenerate
    (* ASYNC_REG = "TRUE" *) reg [1:0] button_sync;
    reg [WIDTH-1:0] stable_count;
    reg stable_level, armed;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            // Start high so the synchronizer's reset value cannot fabricate
            // a released button when the physical button is held at startup.
            button_sync<=2'b11; stable_count<=0;
            stable_level<=1'b1; armed<=1'b0; press_event<=1'b0;
        end else begin
            button_sync<={button_sync[0],button_async};
            press_event<=1'b0;
            if(button_sync[1]==stable_level) stable_count<=0;
            else if(stable_count==LAST) begin
                stable_count<=0; stable_level<=button_sync[1];
                if(!button_sync[1]) armed<=1'b1;
                else if(armed) begin press_event<=1'b1; armed<=1'b0; end
            end else stable_count<=stable_count+1'b1;
        end
    end
endmodule
`default_nettype wire
