// UART Transmitter Module for ANIMA
// CLKS_PER_BIT is the number of clock cycles to establish a baud rate of 115200
// Temporary placeholder; Basys3 Clock Frequency is 100MHz;
// 100 MHz / 115200 ~ 868 Clock cycles per bit

module anima_uart_tx #(
    parameter CLKS_PER_BIT = 868
)(
    input wire          clk,
    input wire          rst,
    input wire [7:0]    data_byte,
    input wire          data_available,
    output reg          TX_Active,
    output reg          output_serial_data,
    output reg          transmission_done
);
    // FSM states for UART Transmission
    localparam IDLE             = 3'b000;
    localparam START            = 3'b001;
    localparam TRANSMITTING     = 3'b010;
    localparam STOP             = 3'b011;
    localparam CLEANUP          = 3'b100;

    // $clog2(CLKS_PER_BIT) register to track clock cycles for bit tracking
    reg [$clog2(CLKS_PER_BIT) - 1 : 0] clk_counter = 0;

    // State register
    reg [2:0] TX_State = 0;

    // Tracks which of the 8 data bits is currently being transmitted
    reg [2:0] bit_index = 0; 

    // Internal copy of data_byte
    reg [7:0] TX_Byte = 0;

    // flag --> finished sending byte
    reg TX_Done = 0; 

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            TX_State <= IDLE;
            clk_counter <= 0;
            bit_index   <= 0;
            TX_Done     <= 0;
            TX_Active   <= 0;
            output_serial_data <= 1'b1;
        end else begin
            case (TX_State)
                IDLE : begin
                    clk_counter <= 0;
                    bit_index   <= 0;
                    TX_Done     <= 0;
                    TX_Active   <= 0;

                    // Drive line high while idle
                    output_serial_data <= 1'b1; 

                    if (data_available == 1'b1) begin
                        TX_Active   <= 1'b1;
                        TX_Byte     <= data_byte;
                        TX_State    <= START;
                    end else begin
                        TX_State    <= IDLE;
                    end
                end

                START : begin
                    // Drive line low to indicate the start of data transmission
                    output_serial_data <= 1'b0;

                    if (clk_counter == CLKS_PER_BIT - 1) begin
                        clk_counter <= 0;
                        TX_State    <= TRANSMITTING;
                    end else begin
                        clk_counter     <= clk_counter + 1;
                        TX_State        <= START;
                    end
                end

                TRANSMITTING : begin
                    output_serial_data <= TX_Byte[bit_index];

                    if (clk_counter == CLKS_PER_BIT - 1) begin
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                            clk_counter <= 0;
                        end else begin
                            bit_index   <= 0;
                            clk_counter <= 0;
                            TX_State    <= STOP;
                        end
                    end else begin
                        clk_counter <= clk_counter + 1;
                        TX_State    <= TRANSMITTING;
                    end
                end

                STOP : begin
                    // Drive line high to indicate stop bit
                    output_serial_data <= 1'b1; 

                    if (clk_counter == CLKS_PER_BIT - 1) begin
                        clk_counter         <= 0;
                        TX_Active           <= 0;
                        TX_State            <= CLEANUP;
                        TX_Done             <= 1'b1;
                    end else begin
                        clk_counter      <= clk_counter + 1;
                        TX_State         <= STOP;
                    end
                end

                CLEANUP : begin
                    TX_Done <= 1'b0;
                    TX_State <= IDLE;
                end

                default : begin
                    TX_State <= IDLE;
                end
            endcase
        end
    end

    assign transmission_done = TX_Done;

endmodule
