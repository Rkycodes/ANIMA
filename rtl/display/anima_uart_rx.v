// UART Module for ANIMA
// CLKS_PER_BIT is the number of clock cycles to establish a baud rate of 115200
// Temporary placeholder; Basys3 Clock Frequency is 100MHz;
// 100 MHz / 115200 ~ 868 Clock cycles per bit

module anima_uart_rx #(
    parameter CLKS_PER_BIT = 868;
)(

); 
endmodule