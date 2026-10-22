`timescale 1ns/1ps
// Independent wire stimulus; internal probes only for alignment/reset checks.
module tb_anima_uart_rx;
    parameter integer BAUD = 115200;
    localparam integer CPB = (100000000 + BAUD/2) / BAUD;
    localparam real BIT_NS = 1.0e9 / BAUD;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1, rx = 1;
    wire [7:0] value;
    wire valid;
    anima_uart_rx #(.CLKS_PER_BIT(CPB)) dut (
        .clk(clk), .rst(rst), .input_serial_data(rx),
        .received_byte(value), .received_data_valid(valid));
    integer failures = 0, observed = 0, expected_count = 0;
    reg [7:0] expected [0:1023];
    reg previous_valid = 0, checking = 0, timing_check = 0;
    real frame_start, ideal, error_ns;
    localparam real DIV_ERROR = (CPB*10.0 > BIT_NS) ? CPB*10.0-BIT_NS : BIT_NS-CPB*10.0;
    integer samples = 0, starts = 0;
    task automatic check(input bit condition, input string message);
        if (!condition) begin
            failures = failures + 1;
            $display("FAIL baud=%0d t=%0t: %s", BAUD, $time, message);
        end
    endtask
    // Observe the pre-edge sampling decision, independently compare its time
    // to the ideal wire midpoint. Allow <=5 clocks for synchronization/FSM delay.
    always @(posedge clk) begin
        if (rst && timing_check) begin
            if (dut.RX_State == 1 && dut.clk_counter == (CPB-1)/2) begin
                starts = starts + 1;
                error_ns = $realtime - (frame_start + 0.5*BIT_NS);
                check(error_ns >= -10 && error_ns <= 50, "start midpoint alignment");
            end
            if (dut.RX_State == 2 && dut.clk_counter == CPB-1) begin
                ideal = frame_start + (1.5 + dut.bit_index)*BIT_NS;
                error_ns = $realtime - ideal;
                check(error_ns >= -10-(1.5+dut.bit_index)*DIV_ERROR &&
                      error_ns <= 50+(1.5+dut.bit_index)*DIV_ERROR, "data midpoint alignment");
                samples = samples + 1;
            end
        end
        #1; // Observe registered outputs after nonblocking updates.
        if (checking) begin
            check(valid === 0 || valid === 1, "valid is known");
            if (!rst) check(valid === 0, "valid stays low during reset");
            if (valid === 1) begin
                check(!previous_valid, "valid pulse lasts one clock");
                if (observed >= expected_count)
                    check(0, "unexpected byte / duplicate / malformed-frame acceptance");
                else check(value === expected[observed],
                    $sformatf("byte %0d expected=%02x actual=%02x", observed, expected[observed], value));
                observed = observed + 1;
            end
        end
        previous_valid = (valid === 1);
    end
    task automatic expect_byte(input reg [7:0] b);
        expected[expected_count] = b;
        expected_count = expected_count + 1;
    endtask
    task automatic send_byte(input reg [7:0] b, input real period_ns, input bit good_stop);
        integer i;
        frame_start = $realtime;
        rx = 0;
        #(period_ns);
        for (i=0; i<8; i=i+1) begin
            rx = b[i];
            #(period_ns);
        end
        rx = good_stop;
        #(period_ns);
        rx = 1;
    endtask
    task automatic settle;
        #(2*BIT_NS);
        check(observed == expected_count, "all expected bytes received");
    endtask
    task automatic reset_receiver;
        rx = 1;
        #2.3 rst = 0;
        checking = 1;
        #1;
        check(dut.RX_State === 0, "asynchronous reset enters IDLE");
        check(dut.clk_counter === 0, "reset clears counter");
        check(dut.bit_index === 0, "reset clears bit index");
        check(valid === 0, "reset clears valid immediately");
        repeat (5) @(negedge clk);
        rst = 1;
        #(BIT_NS);
        check(dut.RX_State === 0, "idle after reset release");
    endtask
    integer i, offset, before_failures;
    reg [7:0] pattern;
    initial begin
        reset_receiver();
        $display("TEST reset held while RX low");
        rst=0; rx=0;
        repeat (8) begin
            @(negedge clk);
            check(dut.RX_State === 0, "reset holds FSM idle despite low RX");
        end
        reset_receiver();
        $display("TEST nominal reconstruction and midpoint sampling baud=%0d CPB=%0d", BAUD, CPB);
        timing_check = 1;
        for (i=0; i<8; i=i+1) begin
            case(i)
                0: pattern=8'h51; 1: pattern=8'hff; 2: pattern=8'h00;
                3: pattern=8'h55; 4: pattern=8'haa; 5: pattern=8'h80;
                6: pattern=8'h01; 7: pattern=8'hfe;
            endcase
            // Vary the start phase relative to the FPGA clock.
            #(i+0.37);
            expect_byte(pattern);
            send_byte(pattern, BIT_NS, 1);
        end
        timing_check = 0;
        settle();
        check(starts == 8 && samples == 64, "one start and eight data samples per frame");
        $display("TEST false start");
        rx=0; #(BIT_NS/4); rx=1;
        settle();
        check(dut.RX_State === 0, "short start glitch returns to idle");
        $display("TEST bad stop rejection and recovery");
        send_byte(8'h51, BIT_NS, 0);
        settle();
        expect_byte(8'ha5); send_byte(8'ha5, BIT_NS, 1); settle();
        $display("TEST reset during data");
        rx=0; #(BIT_NS); rx=1; #(2*BIT_NS);
        reset_receiver(); settle();
        expect_byte(8'h3c); send_byte(8'h3c, BIT_NS, 1); settle();
        $display("TEST reset while valid");
        fork
            begin expect_byte(8'h96); send_byte(8'h96, BIT_NS, 1); end
            begin wait(valid === 1); #2; rst=0; #1;
                check(valid === 0, "reset immediately clears asserted valid");
            end
        join
        reset_receiver(); settle();
        // Positive offset means transmitter BAUD is faster, not period longer.
        for (offset=-5; offset<=5; offset=offset+1) begin
            if (offset != 0) begin
                reset_receiver();
                before_failures = failures;
                observed=0; expected_count=0;
                for (i=0; i<16; i=i+1) begin
                    pattern = (i%2) ? 8'h55 : 8'haa;
                    expect_byte(pattern);
                    send_byte(pattern, BIT_NS/(1.0+offset/100.0), 1);
                end
                settle();
                $display("BAUD OFFSET %0d%%: %0d failures", offset, failures-before_failures);
                // Characterization only outside the proposed +/-2% requirement.
                if (offset < -2 || offset > 2) failures = before_failures;
            end
        end
        if (failures) $fatal(1, "UART suite failed: %0d required checks", failures);
        $display("PASS required UART checks baud=%0d; inspect tolerance characterization above", BAUD);
        $finish;
    end
    initial begin
        #(3000*BIT_NS);
        $fatal(1, "watchdog: simulation stalled");
    end
endmodule
