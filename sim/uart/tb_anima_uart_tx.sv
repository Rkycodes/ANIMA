`timescale 1ns/1ps
module tb_anima_uart_tx;
    string wave_file;
    initial begin
        if ($value$plusargs("WAVE_FILE=%s", wave_file)) begin
            $dumpfile(wave_file);
            $dumpvars(0, tb_anima_uart_tx);
        end
    end
    parameter integer BAUD = 115200;
    parameter integer USE_DEFAULT = 0;
    localparam integer CPB = (100000000 + BAUD/2)/BAUD;
    reg clk=0, rst=1, request=0;
    reg [7:0] data=0;
    wire active, serial, done;
    always #5 clk=~clk;
    generate
        if (USE_DEFAULT != 0) begin : defaults
            anima_uart_tx dut(.clk(clk), .rst(rst), .data_byte(data),
                .data_available(request), .TX_Active(active),
                .output_serial_data(serial), .transmission_done(done));
        end else begin : configured
            anima_uart_tx #(.CLKS_PER_BIT(CPB)) dut(.clk(clk), .rst(rst),
                .data_byte(data), .data_available(request), .TX_Active(active),
                .output_serial_data(serial), .transmission_done(done));
        end
    endgenerate
    integer failures=0, done_count=0;
    bit previous_done=0, wide_reported=0;
    task automatic check(input bit ok, input string message);
        if (!ok) begin
            failures++;
            $display("FAIL t=%0t: %s", $time, message);
        end
    endtask
    // Delayed observation avoids racing nonblocking output updates.
    always @(posedge clk) begin
        #1;
        if (rst) begin
            if (done && !previous_done) done_count++;
            if (done && previous_done && !wide_reported) begin
                check(0, "completion pulse exceeds one clock");
                wide_reported=1;
            end
            if (!done) wide_reported=0;
        end
        previous_done=done;
    end
    task automatic reset_tx;
        @(negedge clk); #2; rst=0; request=0;
        #1;
        check(serial === 1'b1, "reset immediately drives line high");
        check(active === 1'b0, "reset clears active");
        check(done === 1'b0, "reset clears done");
        repeat (4) begin
            @(negedge clk);
            check(serial === 1'b1 && active === 1'b0 && done === 1'b0,
                  "outputs remain idle during reset");
        end
        rst=1;
        repeat (3) @(negedge clk);
    endtask
    // Issue a one-clock request; detect start from the wire, never DUT state.
    task automatic launch(input reg [7:0] b);
        integer waited;
        @(negedge clk); data=b; request=1;
        @(posedge clk); #2;
        check(active === 1'b1, "idle request accepted / active asserted");
        @(negedge clk); request=0; data=~b; // Prove input was latched.
        waited=0;
        while (serial !== 1'b0 && waited<8) begin
            @(posedge clk); #2; waited++;
        end
        check(serial === 1'b0, "start bit appears within eight clocks");
    endtask
    task automatic frame(input reg [7:0] b, input bit busy_pulse);
        integer slot, cycle, count_before;
        bit expected_level, bit_ok, busy_ok, completion_early;
        count_before=done_count;
        launch(b);
        // Observe every clock in ten expected wire slots, not just midpoints.
        // Slot zero begins at the detected falling edge; LSB is slot one.
        for (slot=0; slot<10; slot++) begin
            expected_level=(slot==0) ? 0 : ((slot==9) ? 1 : b[slot-1]);
            bit_ok=1; busy_ok=1; completion_early=0;
            for (cycle=0; cycle<CPB; cycle++) begin
                if (serial !== expected_level) bit_ok=0;
                // Allow completion on the final stop-bit processing edge.
                if (!(slot==9 && cycle==CPB-1)) begin
                    if (active !== 1'b1) busy_ok=0;
                    if (done === 1'b1) completion_early=1;
                end
                @(negedge clk);
                if (busy_pulse && slot==3 && cycle==0) begin request=1; data=8'h69; end
                if (busy_pulse && slot==3 && cycle==1) request=0;
                @(posedge clk); #2;
            end
            check(bit_ok, $sformatf("byte %02x slot %0d: polarity/order/duration", b, slot));
            check(busy_ok, $sformatf("active remains asserted in slot %0d", slot));
            check(!completion_early, "completion must not precede end of stop bit");
        end
        repeat (4) @(negedge clk);
        check(done_count==count_before+1, "exactly one completion per request");
        check(active === 0 && done === 0 && serial === 1,
              "return to idle with completion cleared");
        // No queued retransmission of the busy-time pulse.
        repeat (CPB*2) begin
            @(negedge clk);
            if (serial !== 1 || active !== 0 || done !== 0) begin
                check(0, "unexpected activity without a new idle request");
                break;
            end
        end
    endtask
    integer i, stage, old_count;
    reg [7:0] pattern;
    initial begin
        $display("TX TEST baud=%0d CPB=%0d default=%0d",BAUD,CPB,USE_DEFAULT);
        reset_tx();
        repeat (20) begin
            @(negedge clk);
            check(serial===1 && active===0 && done===0, "idle output levels");
        end
        for (i=0;i<8;i++) begin
            case(i)
                0:pattern=8'h51; 1:pattern=8'hff; 2:pattern=8'h00;
                3:pattern=8'h55; 4:pattern=8'haa; 5:pattern=8'h80;
                6:pattern=8'h01; 7:pattern=8'hfe;
            endcase
            frame(pattern, i==3);
        end
        // Abort at midpoint of start, data, and stop, then send a fresh byte.
        for(stage=0;stage<3;stage++) begin
            old_count=done_count;
            launch(8'h55);
            repeat ((stage==0 ? 0 : (stage==1 ? 4 : 9))*CPB+CPB/2)
                @(negedge clk);
            reset_tx();
            check(done_count==old_count, "aborted byte must not complete");
            frame(8'ha5,0);
        end
        if(failures != 0) $fatal(1,"TX suite failed: %0d checks",failures);
        $display("PASS TX suite");
        $finish;
    end
    initial begin
        #(1000.0*CPB*10.0);
        $fatal(1,"TX watchdog timeout");
    end
endmodule
