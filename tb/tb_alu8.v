// tb_alu8.v
// Ish Bedi
//
// Exhaustive self-checking test: every opcode x every (a, b) pair = 524,288 vectors,
// compared against a behavioural reference model written with integer arithmetic.

`timescale 1ns/1ps

module tb_alu8;
    reg  [2:0] op;
    reg  [7:0] a, b;
    wire [7:0] y;
    wire [3:0] flags;

    alu8 dut (.op(op), .a(a), .b(b), .y(y), .flags(flags));

    // ---------- reference model ----------
    reg [7:0] ref_y;
    reg       ref_c, ref_v;
    integer   sa, sb, sr, n, k;

    task automatic model;
        begin
            sa = (a > 127) ? a - 256 : a;          // signed views
            sb = (b > 127) ? b - 256 : b;
            ref_c = 0; ref_v = 0;
            n = b % 8;
            case (op)
                0: begin ref_y = (a + b) % 256; ref_c = (a + b) > 255;
                         sr = sa + sb; ref_v = (sr > 127) || (sr < -128); end
                1: begin ref_y = (a - b + 256) % 256; ref_c = a < b;
                         sr = sa - sb; ref_v = (sr > 127) || (sr < -128); end
                2: ref_y = a & b;
                3: ref_y = a | b;
                4: ref_y = a ^ b;
                5: begin ref_y = (a * (1 << n)) % 256;
                         ref_c = (n == 0) ? 0 : ((a >> (8 - n)) & 1); end
                6: begin ref_y = a / (1 << n);
                         ref_c = (n == 0) ? 0 : ((a >> (n - 1)) & 1); end
                default: ref_y = 255 - a;
            endcase
        end
    endtask

    integer errors = 0, checked = 0;
    integer o, i, j;
    reg [3:0] ref_flags;

    initial begin
        $display("tb_alu8: exhaustive check, 8 ops x 256 x 256");
        for (o = 0; o < 8; o = o + 1)
            for (i = 0; i < 256; i = i + 1)
                for (j = 0; j < 256; j = j + 1) begin
                    op = o; a = i; b = j;
                    #1;
                    model;
                    ref_flags = {ref_v, ref_y[7], ref_c, ref_y == 0};
                    checked = checked + 1;
                    if (y !== ref_y || flags !== ref_flags) begin
                        errors = errors + 1;
                        if (errors <= 10)
                            $display("  MISMATCH op=%0d a=%02h b=%02h : y=%02h flags=%b, expected y=%02h flags=%b",
                                     op, a, b, y, flags, ref_y, ref_flags);
                    end
                end
        if (errors == 0) $display("PASS: %0d vectors, 0 mismatches", checked);
        else             $display("FAIL: %0d of %0d vectors mismatched", errors, checked);
        $finish;
    end
endmodule
