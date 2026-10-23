`timescale 1ns/1fs
`default_nettype none
module anima_button_event_tb(output bit done=0);
    logic clk=0, reset_n=0, button_async=1;
    wire [1:0] press;
    anima_button_event #(.STABLE_CYCLES(1)) one(.press_event(press[0]), .*);
    anima_button_event #(.STABLE_CYCLES(4)) four(.press_event(press[1]), .*);
    bit pipe_first=1, pipe_second=1;
    bit stable[2]='{1,1}, armed[2]='{0,0};
    int age[2]='{0,0}, events[2]='{0,0};
    int seed=2026, ticks=0;
    logic [31:0] rng;
    task automatic tick(input bit raw);
        bit expected_press[2];
        button_async=raw;
        for(int k=0;k<2;k++) begin
            expected_press[k]=0;
            if(!reset_n) begin stable[k]=1; armed[k]=0; age[k]=0; end
            else if(pipe_second==stable[k]) age[k]=0;
            else begin
                age[k]++;
                if(age[k]==(k==0 ? 1 : 4)) begin
                    age[k]=0; stable[k]=pipe_second;
                    if(!pipe_second) armed[k]=1;
                    else if(armed[k]) begin expected_press[k]=1; armed[k]=0; end
                end
            end
        end
        if(!reset_n) begin pipe_first=1; pipe_second=1; end
        else begin pipe_second=pipe_first; pipe_first=raw; end
        #2; clk=1; #1;
        for(int k=0;k<2;k++) begin
            assert(press[k]===expected_press[k]) else $fatal(1,"BOARD_FAIL button oracle tick=%0d config=%0d",ticks,k);
            if(press[k]) events[k]++;
        end
        clk=0; #1; ticks++;
    endtask
    initial begin
        void'($value$plusargs("SEED_%d",seed)); rng=32'(seed);
        tick(1); reset_n=1;
        repeat(32) tick(1); // held at startup is not a press
        assert(events[0]==0 && events[1]==0) else $fatal(1,"BOARD_FAIL held-at-startup button");
        repeat(10) tick(0); repeat(100) tick(1);
        assert(events[0]==1 && events[1]==1) else $fatal(1,"BOARD_FAIL held press must emit once");
        repeat(10) tick(0); tick(1); tick(0); tick(1); tick(0);
        repeat(10) tick(0); repeat(10) tick(1);
        // Recovery reset while held requires a release before any new command.
        reset_n=0; #1;
        assert(press==0) else $fatal(1,"BOARD_FAIL async button reset");
        tick(1); reset_n=1; repeat(20) tick(1);
        repeat(10) tick(0); repeat(10) tick(1);
        repeat(5000) begin
            rng^=rng<<13; rng^=rng>>17; rng^=rng<<5; tick(rng[0]);
        end
        $display("BUTTON_PASS seed=%0d ticks=%0d events=%0d/%0d",seed,ticks,events[0],events[1]); done=1;
    end
endmodule
`default_nettype wire
