// de10_lite_top.v
// Ish Bedi
//
// Board top level for the Terasic DE10-Lite (MAX 10, 50 MHz clock).
//   KEY[0]        : reset (active low, synchronized)
//   ARDUINO_IO[0] : UART RX  (connect to the TX pin of a 3.3 V USB-serial adapter)
//   ARDUINO_IO[1] : UART TX  (connect to the RX pin of the adapter)
//   HEX1:HEX0     : last ALU result in hex
//   LEDR[3:0]     : last flags {V, N, C, Z}
//   LEDR[7]       : RX busy, LEDR[8] : TX busy, LEDR[9] : framing error seen

module de10_lite_top (
    input  wire       MAX10_CLK1_50,
    input  wire [1:0] KEY,
    inout  wire [15:0] ARDUINO_IO,
    output wire [9:0] LEDR,
    output wire [7:0] HEX0,
    output wire [7:0] HEX1
);
    // reset synchronizer: async assert from the button, sync release
    reg [1:0] rst_sync;
    always @(posedge MAX10_CLK1_50 or negedge KEY[0]) begin
        if (!KEY[0]) rst_sync <= 2'b11;
        else         rst_sync <= {rst_sync[0], 1'b0};
    end
    wire rst = rst_sync[1];

    wire       uart_tx_pin;
    wire [7:0] result;
    wire [3:0] flags;
    wire       ferr, rx_busy, tx_busy;

    uart_alu #(.CLK_HZ(50_000_000), .BAUD(115_200)) u_core (
        .clk(MAX10_CLK1_50), .rst(rst),
        .rx(ARDUINO_IO[0]), .tx(uart_tx_pin),
        .last_result(result), .last_flags(flags), .frame_err_seen(ferr),
        .rx_busy(rx_busy), .tx_busy(tx_busy)
    );

    assign ARDUINO_IO[0]    = 1'bz;          // input
    assign ARDUINO_IO[1]    = uart_tx_pin;
    assign ARDUINO_IO[15:2] = 14'bz;

    assign LEDR = {ferr, tx_busy, rx_busy, 3'b000, flags};

    hex7seg u_h0 (.nibble(result[3:0]), .seg(HEX0[6:0]));
    hex7seg u_h1 (.nibble(result[7:4]), .seg(HEX1[6:0]));
    assign HEX0[7] = 1'b1;                   // decimal points off
    assign HEX1[7] = 1'b1;
endmodule
