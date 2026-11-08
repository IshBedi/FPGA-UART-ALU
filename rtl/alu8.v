// alu8.v
// Ish Bedi
//
// Combinational 8-bit ALU with Z/C/N/V status flags.
//
//   op | name | result               | C                        | V
//  ----+------+----------------------+--------------------------+-------------------
//   0  | ADD  | a + b                | carry out of bit 7       | signed overflow
//   1  | SUB  | a - b                | borrow (a < b unsigned)  | signed overflow
//   2  | AND  | a & b                | 0                        | 0
//   3  | OR   | a | b                | 0                        | 0
//   4  | XOR  | a ^ b                | 0                        | 0
//   5  | SHL  | a << b[2:0]          | last bit shifted out     | 0
//   6  | SHR  | a >> b[2:0]          | last bit shifted out     | 0
//   7  | NOT  | ~a                   | 0                        | 0
//
// Z = (result == 0), N = result[7]. flags = {V, N, C, Z}.

module alu8 (
    input  wire [2:0] op,
    input  wire [7:0] a,
    input  wire [7:0] b,
    output reg  [7:0] y,
    output wire [3:0] flags
);
    localparam [2:0] OP_ADD = 3'd0, OP_SUB = 3'd1, OP_AND = 3'd2, OP_OR  = 3'd3,
                     OP_XOR = 3'd4, OP_SHL = 3'd5, OP_SHR = 3'd6, OP_NOT = 3'd7;

    reg        c, v;
    wire [2:0] sh   = b[2:0];
    wire [8:0] sum  = {1'b0, a} + {1'b0, b};
    wire [8:0] diff = {1'b0, a} - {1'b0, b};
    wire [8:0] shl  = {1'b0, a} << sh;            // bit 8 = last bit shifted out
    wire [8:0] shr  = {a, 1'b0} >> sh;            // bit 0 = last bit shifted out

    always @(*) begin
        c = 1'b0;
        v = 1'b0;
        case (op)
            OP_ADD: begin
                y = sum[7:0];
                c = sum[8];
                v = (a[7] == b[7]) && (y[7] != a[7]);
            end
            OP_SUB: begin
                y = diff[7:0];
                c = diff[8];                       // borrow
                v = (a[7] != b[7]) && (y[7] != a[7]);
            end
            OP_AND: y = a & b;
            OP_OR:  y = a | b;
            OP_XOR: y = a ^ b;
            OP_SHL: begin
                y = shl[7:0];
                c = shl[8];
            end
            OP_SHR: begin
                y = shr[8:1];
                c = shr[0];
            end
            default: y = ~a;                       // OP_NOT
        endcase
    end

    assign flags = {v, y[7], c, (y == 8'h00)};
endmodule
