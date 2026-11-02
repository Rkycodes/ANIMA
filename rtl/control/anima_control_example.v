// Educational control-path reference, Verilog-2001. Not an audio integration.
// All ports use clk; rst_n is active-low. See sim/control/README.md.
`timescale 1ns/1ps
module anima_control_example #(
    parameter FIFO_ADDR_BITS = 4,
    parameter TIMEOUT_CYCLES = 1000000
)(
    input wire clk,
    input wire rst_n,
    input wire [7:0] rx_byte,
    input wire rx_valid,
    input wire rx_error,
    input wire frame_start,
    output wire rx_overflow,
    output wire packet_error,
    output wire reply_valid,
    output wire [7:0] reply_sequence,
    output wire [7:0] reply_status,
    output wire [15:0] reply_generation,
    output wire active_bypass,
    output wire signed [15:0] active_gain,
    output wire [15:0] active_generation,
    output wire pending_valid,
    output wire applied_valid,
    output wire [7:0] applied_sequence
);
    wire [7:0] fifo_byte;
    wire fifo_valid, fifo_ready, fifo_pop;
    wire abort_packet = rx_error || rx_overflow;
    wire packet_valid;
    wire [7:0] version, opcode, sequence_id, length;
    wire [127:0] payload;
    wire shadow_write, commit, shadow_valid, shadow_bypass;
    wire signed [15:0] shadow_gain;
    wire [15:0] next_generation;

    assign rx_overflow = rx_valid && !fifo_ready && !rx_error;

    anima_example_byte_fifo #(.ADDR_BITS(FIFO_ADDR_BITS)) fifo (
        .clk(clk), .rst_n(rst_n), .flush(abort_packet),
        .in_data(rx_byte), .in_valid(rx_valid), .in_ready(fifo_ready),
        .out_data(fifo_byte), .out_valid(fifo_valid), .out_ready(fifo_pop)
    );
    anima_example_packet_rx #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) parser (
        .clk(clk), .rst_n(rst_n), .abort_packet(abort_packet),
        .byte_data(fifo_byte), .byte_valid(fifo_valid), .byte_ready(fifo_pop),
        .packet_valid(packet_valid), .packet_ready(1'b1),
        .version(version), .opcode(opcode), .sequence_id(sequence_id),
        .length(length), .payload(payload), .packet_error(packet_error)
    );
    anima_example_dispatch dispatcher (
        .clk(clk), .rst_n(rst_n), .packet_valid(packet_valid),
        .version(version), .opcode(opcode), .sequence_id(sequence_id),
        .length(length), .payload(payload), .shadow_valid(shadow_valid),
        .next_generation(next_generation), .shadow_write(shadow_write),
        .shadow_bypass(shadow_bypass), .shadow_gain(shadow_gain), .commit(commit),
        .reply_valid(reply_valid), .reply_sequence(reply_sequence),
        .reply_status(reply_status), .reply_generation(reply_generation)
    );
    anima_example_config config_store (
        .clk(clk), .rst_n(rst_n), .shadow_write(shadow_write),
        .write_bypass(shadow_bypass), .write_gain(shadow_gain),
        .commit(commit), .commit_sequence(sequence_id), .frame_start(frame_start),
        .shadow_valid(shadow_valid), .next_generation(next_generation),
        .pending_valid(pending_valid), .active_bypass(active_bypass),
        .active_gain(active_gain), .active_generation(active_generation),
        .applied_valid(applied_valid), .applied_sequence(applied_sequence)
    );
endmodule

// Power-of-two synchronous FIFO with combinational head/read data.
// ADDR_BITS >= 1. Full plus simultaneous pop permits a replacement write.
module anima_example_byte_fifo #(parameter ADDR_BITS = 4)(
    input wire clk, rst_n, flush,
    input wire [7:0] in_data,
    input wire in_valid,
    output wire in_ready,
    output wire [7:0] out_data,
    output wire out_valid,
    input wire out_ready
);
    localparam [ADDR_BITS:0] CAPACITY = {1'b1, {ADDR_BITS{1'b0}}};
    reg [7:0] memory [0:(1 << ADDR_BITS)-1];
    reg [ADDR_BITS-1:0] read_ptr, write_ptr;
    reg [ADDR_BITS:0] count;
    wire pop = out_valid && out_ready;
    wire push = in_valid && in_ready;
    assign out_valid = count != 0;
    assign out_data = memory[read_ptr];
    assign in_ready = (count != CAPACITY) || pop;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_ptr <= 0;
            write_ptr <= 0;
            count <= 0;
        end else if (flush) begin
            read_ptr <= 0;
            write_ptr <= 0;
            count <= 0;
        end else begin
            if (push) begin
                memory[write_ptr] <= in_data;
                write_ptr <= write_ptr + 1'b1;
            end
            if (pop) read_ptr <= read_ptr + 1'b1;
            case ({push, pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end
endmodule

// Wire: 55 | escaped(VERSION OPCODE SEQUENCE LENGTH PAYLOAD CRC_H CRC_L) | 55.
// Escape 55 -> 7D 75, 7D -> 7D 5D. Maximum decoded payload: 16 bytes.
// CRC-16: poly 1021, init FFFF, no reflection/final XOR. Appended CRC has
// zero residue when included in the calculation. Header/payload are protected.
module anima_example_packet_rx #(parameter TIMEOUT_CYCLES = 1000000)(
    input wire clk, rst_n, abort_packet,
    input wire [7:0] byte_data,
    input wire byte_valid,
    output wire byte_ready,
    output reg packet_valid,
    input wire packet_ready,
    output reg [7:0] version, opcode, sequence_id, length,
    output reg [127:0] payload,
    output reg packet_error
);
    reg collecting, escaped, dropping;
    reg [5:0] count;
    reg [15:0] crc;
    reg [7:0] work_version, work_opcode, work_sequence, work_length;
    reg [127:0] work_payload;
    integer idle_cycles;
    wire [7:0] decoded = escaped ? (byte_data ^ 8'h20) : byte_data;
    assign byte_ready = !packet_valid;

    function [15:0] crc_byte;
        input [15:0] previous;
        input [7:0] data;
        integer bit_number;
        reg [15:0] value;
        begin
            value = previous ^ {data, 8'h00};
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1)
                value = value[15] ? ((value << 1) ^ 16'h1021) : (value << 1);
            crc_byte = value;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            collecting <= 0; escaped <= 0; dropping <= 0;
            count <= 0; crc <= 16'hffff; idle_cycles <= 0;
            work_version <= 0; work_opcode <= 0;
            work_sequence <= 0; work_length <= 0; work_payload <= 0;
            packet_valid <= 0; packet_error <= 0;
            version <= 0; opcode <= 0; sequence_id <= 0;
            length <= 0; payload <= 0;
        end else begin
            packet_error <= 0;
            if (packet_valid && packet_ready) packet_valid <= 0;
            // Abort only unfinished assembly; a previously validated packet
            // already belongs to the output interface and remains deliverable.
            if (abort_packet) begin
                collecting <= 0; escaped <= 0; dropping <= 0;
                count <= 0; crc <= 16'hffff; idle_cycles <= 0;
                packet_error <= 1;
            end else if (byte_valid && byte_ready) begin
                idle_cycles <= 0;
                if (byte_data == 8'h55) begin
                    if (collecting && !dropping && (count != 0 || escaped)) begin
                        if (!escaped && count >= 6 &&
                            {2'b00, count} == work_length + 8'd6 && crc == 0) begin
                            version <= work_version; opcode <= work_opcode;
                            sequence_id <= work_sequence; length <= work_length;
                            payload <= work_payload; packet_valid <= 1;
                        end else packet_error <= 1;
                    end
                    // A delimiter closes the old candidate and opens a new one.
                    collecting <= 1; escaped <= 0; dropping <= 0;
                    count <= 0; crc <= 16'hffff; work_payload <= 0;
                end else if (collecting && !dropping) begin
                    if (!escaped && byte_data == 8'h7d) escaped <= 1;
                    else if ((escaped && byte_data != 8'h75 && byte_data != 8'h5d)
                             || count >= 22) begin
                        dropping <= 1; escaped <= 0; packet_error <= 1;
                    end else begin
                        escaped <= 0;
                        crc <= crc_byte(crc, decoded);
                        count <= count + 1'b1;
                        case (count)
                            0: work_version <= decoded;
                            1: work_opcode <= decoded;
                            2: work_sequence <= decoded;
                            3: begin
                                work_length <= decoded;
                                if (decoded > 16) begin
                                    dropping <= 1; packet_error <= 1;
                                end
                            end
                            default: begin
                                if (count >= 4 && {2'b00, count} < work_length + 8'd4)
                                    work_payload[(count-4)*8 +: 8] <= decoded;
                            end
                        endcase
                    end
                end
            end else if (!packet_valid && collecting && (count != 0 || escaped || dropping)) begin
                // Parser wait timeout, not timestamped physical UART gap timing.
                // Paused while a validated packet waits downstream.
                if (idle_cycles == TIMEOUT_CYCLES - 1) begin
                    collecting <= 0; escaped <= 0; dropping <= 0;
                    count <= 0; crc <= 16'hffff; idle_cycles <= 0;
                    packet_error <= 1;
                end else idle_cycles <= idle_cycles + 1;
            end
        end
    end
endmodule

// Commands: 01 status/no-op (length 0), 10 replace shadow (length 3),
// 11 commit (length 0). Payload: bypass, gain low byte, gain high byte.
// Gain is signed dB * 256; +/-12 dB is an EXAMPLE limit, not agreed DSP limits.
// Status: 00 OK, 01 accepted, 02 opcode, 03 length, 04 value,
// 05 no shadow, 06 sequence conflict, 07 version.
// One-entry duplicate cache assumes one unacknowledged request, one session.
module anima_example_dispatch (
    input wire clk, rst_n, packet_valid,
    input wire [7:0] version, opcode, sequence_id, length,
    input wire [127:0] payload,
    input wire shadow_valid,
    input wire [15:0] next_generation,
    output wire shadow_write, shadow_bypass,
    output wire signed [15:0] shadow_gain,
    output wire commit,
    output reg reply_valid,
    output reg [7:0] reply_sequence, reply_status,
    output reg [15:0] reply_generation
);
    reg cache_valid;
    reg [7:0] cached_version, cached_opcode, cached_sequence, cached_length;
    reg [127:0] cached_payload;
    reg [7:0] cached_status;
    reg [15:0] cached_generation;
    reg [7:0] status;
    wire same_sequence = cache_valid && sequence_id == cached_sequence;
    wire same_request = version == cached_version && opcode == cached_opcode &&
                        length == cached_length && payload == cached_payload;
    wire execute = packet_valid && !same_sequence;
    assign shadow_bypass = payload[0];
    assign shadow_gain = payload[23:8];
    assign shadow_write = execute && status == 0 && opcode == 8'h10;
    assign commit = execute && status == 1 && opcode == 8'h11;

    always @* begin
        status = 0;
        if (version != 1) status = 7;
        else case (opcode)
            8'h01: if (length != 0) status = 3;
            8'h10: begin
                if (length != 3) status = 3;
                else if (payload[7:0] > 1 || shadow_gain < -16'sd3072 ||
                         shadow_gain > 16'sd3072) status = 4;
            end
            8'h11: begin
                if (length != 0) status = 3;
                else if (!shadow_valid) status = 5;
                else status = 1;
            end
            default: status = 2;
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cache_valid <= 0; cached_version <= 0; cached_opcode <= 0;
            cached_sequence <= 0; cached_length <= 0; cached_payload <= 0;
            cached_status <= 0; cached_generation <= 0;
            reply_valid <= 0; reply_sequence <= 0;
            reply_status <= 0; reply_generation <= 0;
        end else begin
            reply_valid <= packet_valid;
            if (packet_valid) begin
                reply_sequence <= sequence_id;
                if (same_sequence) begin
                    reply_status <= same_request ? cached_status : 8'd6;
                    reply_generation <= same_request ? cached_generation : 16'd0;
                end else begin
                    reply_status <= status;
                    reply_generation <= commit ? next_generation : 16'd0;
                    cache_valid <= 1;
                    cached_version <= version; cached_opcode <= opcode;
                    cached_sequence <= sequence_id; cached_length <= length;
                    cached_payload <= payload; cached_status <= status;
                    cached_generation <= commit ? next_generation : 16'd0;
                end
            end
        end
    end
endmodule

// Small register snapshots. frame_start pins BOTH active parameters together.
// On simultaneous activation/commit, old pending activates and new commit waits.
// Exposes active registers only: a real pipelined DSP must separately retain
// parameters for older in-flight frames. Superseded notifications are omitted.
module anima_example_config (
    input wire clk, rst_n, shadow_write, write_bypass,
    input wire signed [15:0] write_gain,
    input wire commit,
    input wire [7:0] commit_sequence,
    input wire frame_start,
    output reg shadow_valid,
    output wire [15:0] next_generation,
    output reg pending_valid,
    output reg active_bypass,
    output reg signed [15:0] active_gain,
    output reg [15:0] active_generation,
    output reg applied_valid,
    output reg [7:0] applied_sequence
);
    reg shadow_bypass, pending_bypass;
    reg signed [15:0] shadow_gain, pending_gain;
    reg [15:0] generation_counter, pending_generation;
    reg [7:0] pending_sequence;
    assign next_generation = generation_counter + 16'd1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shadow_valid <= 0; shadow_bypass <= 1; shadow_gain <= 0;
            pending_valid <= 0; pending_bypass <= 1; pending_gain <= 0;
            generation_counter <= 0; pending_generation <= 0; pending_sequence <= 0;
            active_bypass <= 1; active_gain <= 0; active_generation <= 0;
            applied_valid <= 0; applied_sequence <= 0;
        end else begin
            applied_valid <= 0;
            if (shadow_write) begin
                shadow_bypass <= write_bypass;
                shadow_gain <= write_gain;
                shadow_valid <= 1;
            end
            if (frame_start && pending_valid) begin
                active_bypass <= pending_bypass;
                active_gain <= pending_gain;
                active_generation <= pending_generation;
                applied_sequence <= pending_sequence;
                applied_valid <= 1;
                pending_valid <= 0;
            end
            // Later nonblocking assignment wins for pending_valid on a tie.
            if (commit && shadow_valid) begin
                pending_bypass <= shadow_bypass;
                pending_gain <= shadow_gain;
                pending_sequence <= commit_sequence;
                pending_generation <= next_generation;
                generation_counter <= next_generation;
                pending_valid <= 1;
            end
        end
    end
endmodule
