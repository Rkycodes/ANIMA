// UART Receiver Module for ANIMA
// CLKS_PER_BIT is the number of clock cycles to establish a baud rate of 115200
// Temporary placeholder; Basys3 Clock Frequency is 100MHz;
// 100 MHz / 115200 ~ 868 Clock cycles per bit

module anima_uart_rx #(
    parameter CLKS_PER_BIT = 868
)(
    input   wire        clk,
    input   wire        rst,
    input   wire        input_serial_data,
    output  wire [7:0]  received_byte,
    output  wire        received_data_valid
); 
    // State machine states for UART
    localparam IDLE             = 3'b000;
    localparam START_RECEIVED   = 3'b001;
    localparam DATA_RECEPTION   = 3'b010;
    localparam STOP             = 3'b011;
    localparam CLEANUP          = 3'b100;

    // $clog2(CLKS_PER_BIT) register to track clock cycles for bit tracking
    reg [$clog2(CLKS_PER_BIT) - 1 : 0] clk_counter = 0;

    // Register to track current bit index
    reg [2:0] bit_index = 0;

    // 2 input buffer registers;
    reg input_buffer    = 1'b1;
    reg serial_data     = 1'b1;

    // State register
    reg [2:0] RX_State  = 0;

    // Data valid flag
    reg data_valid = 0;

    // Data byte
    reg [7:0] data_byte;

    // 2 input buffer to protect against metastability
    always @(posedge clk) begin
        input_buffer <= input_serial_data;
        serial_data <= input_buffer;
    end

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            RX_State <= IDLE;
            data_byte <= 8'b0;
            data_valid  <= 0;
            clk_counter <= 0;
            bit_index   <= 0;
        end else begin

            case (RX_State)
                IDLE : begin
                    data_valid  <= 0;
                    clk_counter <= 0;
                    bit_index   <= 0;

                    // Serial line pulled low to indicate the start of incoming data
                    if (serial_data == 1'b0) begin
                        RX_State <= START_RECEIVED;
                    end else begin
                        RX_State <= IDLE;
                    end
                end

                START_RECEIVED : begin
                    // Sample at the midpoint; if it remains low, valid start, and move on to transmission
                    if (clk_counter == ((CLKS_PER_BIT - 1) / 2)) begin
                        if (serial_data == 1'b0) begin
                            clk_counter <= 0;
                            RX_State <= DATA_RECEPTION;
                        end else begin
                            // Invalid sample
                            RX_State <= IDLE;
                        end 
                    end else begin
                        clk_counter <= clk_counter + 1;
                    end
                end

                DATA_RECEPTION : begin
                    if (clk_counter == CLKS_PER_BIT - 1) begin
                        clk_counter <= 0;
                        data_byte[bit_index] <= serial_data;

                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            bit_index <= 0;
                            RX_State <= STOP;
                        end
                    end else begin
                        clk_counter <= clk_counter + 1;
                    end
                end

                STOP : begin
                    if (clk_counter == CLKS_PER_BIT - 1) begin
                        if (serial_data == 1'b1) begin
                            data_valid <= 1'b1;
                        end else begin
                            data_valid <= 1'b0;
                        end
                        clk_counter <= 0;
                        RX_State <= CLEANUP;
                    end else begin 
                        clk_counter <= clk_counter + 1;
                    end
                    
                end

                CLEANUP : begin
                    data_valid <= 1'b0;
                    RX_State <= IDLE;
                end

                default : begin
                    RX_State <= IDLE;
                end
            endcase
        end
    end

    assign received_data_valid = data_valid;
    assign received_byte = data_byte;

endmodule
