// baud_gen.v
// Ish Bedi
//
// Produces a one-clock enable pulse at BAUD * OVERSAMPLE Hz from the system clock.
// The divider is rounded to the nearest integer at elaboration time.
// When `en` is low the counter is held at zero, so the first tick after `en`
// rises arrives exactly DIV clocks later. The transmitter relies on this so the
// start bit is the same width as every other bit.

module baud_gen #(
    parameter integer CLK_HZ     = 50_000_000,
    parameter integer BAUD       = 115_200,
    parameter integer OVERSAMPLE = 1
) (
    input  wire clk,
    input  wire rst,
    input  wire en,
    output wire tick
);
    localparam integer RATE = BAUD * OVERSAMPLE;
    localparam integer DIV  = (CLK_HZ + RATE / 2) / RATE;
    localparam integer W    = (DIV > 1) ? $clog2(DIV) : 1;

    reg [W-1:0] count;

    assign tick = en && (count == DIV - 1);

    always @(posedge clk) begin
        if (rst || !en || tick)
            count <= {W{1'b0}};
        else
            count <= count + 1'b1;
    end
endmodule
