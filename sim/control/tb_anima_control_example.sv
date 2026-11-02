`timescale 1ns/1ps
module tb_anima_control_example;
    reg clk = 0;
    always #5 clk = !clk;
    reg rst_n = 0;
    reg [7:0] rx_byte = 0;
    reg rx_valid = 0, rx_error = 0, frame_start = 0;
    wire rx_overflow, packet_error, reply_valid, active_bypass, pending_valid;
    wire applied_valid;
    wire [7:0] reply_sequence, reply_status, applied_sequence;
    wire [15:0] reply_generation, active_generation;
    wire signed [15:0] active_gain;
    integer replies = 0, errors = 0, applications = 0, overflows = 0, baseline;
    reg [7:0] last_sequence, last_status;
    reg [15:0] last_generation;
    anima_control_example #(.TIMEOUT_CYCLES(64)) dut (.*);

    always @(negedge clk) begin
        if (rst_n) begin
            if (reply_valid) begin
                replies = replies + 1;
                last_sequence = reply_sequence;
                last_status = reply_status;
                last_generation = reply_generation;
            end
            if (packet_error) errors = errors + 1;
            if (applied_valid) applications = applications + 1;
        end
    end
    always @(posedge clk)
        if (rst_n && rx_overflow) overflows = overflows + 1;

    task reset_dut;
        begin
            @(negedge clk);
            rst_n = 0; rx_valid = 0; frame_start = 0; rx_error = 0;
            repeat (3) @(negedge clk);
            rst_n = 1;
            repeat (2) @(negedge clk);
            #1;
            replies = 0; errors = 0; applications = 0; overflows = 0;
        end
    endtask
    task send_byte(input [7:0] value);
        begin
            @(negedge clk);
            rx_byte = value;
            rx_valid = 1;
        end
    endtask
    task stop_bytes;
        begin
            @(negedge clk);
            rx_valid = 0;
        end
    endtask
    task settle;
        begin repeat (40) @(negedge clk); #1; end
    endtask
    task activate;
        begin
            @(negedge clk); frame_start = 1;
            @(negedge clk); frame_start = 0;
            #1;
        end
    endtask
    task expect_reply(input integer count, input [7:0] seq,
                      input [7:0] status, input [15:0] generation);
        begin
            if (replies != count || last_sequence !== seq ||
                last_status !== status || last_generation !== generation)
                $fatal(1, "reply count=%0d seq=%h status=%h gen=%0d; expected %0d/%h/%h/%0d",
                       replies, last_sequence, last_status, last_generation,
                       count, seq, status, generation);
        end
    endtask
    task expect_active(input bit bypass, input signed [15:0] gain,
                       input [15:0] generation);
        begin
            if (active_bypass !== bypass || active_gain !== gain ||
                active_generation !== generation)
                $fatal(1, "active configuration differs from expected generation %0d", generation);
        end
    endtask

    // Exercise the reusable FIFO separately against an independent queue.
    reg fifo_flush = 0, fifo_in_valid = 0, fifo_out_ready = 0;
    reg [7:0] fifo_in_data = 0;
    wire fifo_in_ready, fifo_out_valid;
    wire [7:0] fifo_out_data;
    anima_example_byte_fifo #(.ADDR_BITS(2)) fifo_test (
        .clk(clk), .rst_n(rst_n), .flush(fifo_flush),
        .in_data(fifo_in_data), .in_valid(fifo_in_valid), .in_ready(fifo_in_ready),
        .out_data(fifo_out_data), .out_valid(fifo_out_valid), .out_ready(fifo_out_ready)
    );
    reg [7:0] model [0:4095];
    integer head = 0, tail = 0;
    task test_fifo;
        integer i;
        begin
            for (i = 0; i < 2000; i = i + 1) begin
                @(negedge clk);
                fifo_flush = (i % 79 == 0);
                fifo_in_valid = $urandom_range(0, 1);
                fifo_out_ready = $urandom_range(0, 1);
                fifo_in_data = $urandom_range(0, 255);
                @(posedge clk);
                if (fifo_flush) begin head = 0; tail = 0; end
                else begin
                    if (fifo_out_valid !== (head != tail)) $fatal(1, "FIFO empty flag");
                    if (fifo_in_ready !== ((tail-head < 4) ||
                                          ((head != tail) && fifo_out_ready)))
                        $fatal(1, "FIFO ready flag");
                    if (fifo_out_valid && fifo_out_ready) begin
                        if (fifo_out_data !== model[head]) $fatal(1, "FIFO order");
                        head = head + 1;
                    end
                    if (fifo_in_valid && fifo_in_ready) begin
                        model[tail] = fifo_in_data;
                        tail = tail + 1;
                    end
                end
            end
            @(negedge clk);
            fifo_in_valid = 0; fifo_out_ready = 0; fifo_flush = 0;
        end
    endtask
    initial begin
        `include "control_stimulus.vh"
        $display("PASS: control reference scenarios and randomized FIFO scoreboard");
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "Simulation watchdog");
    end
endmodule
