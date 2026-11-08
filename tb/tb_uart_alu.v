// tb_uart_alu.v
// Ish Bedi
//
// System test: the testbench acts as the PC. It serializes [OP][A][B] onto the FPGA's
// RX pin at 115200 baud, decodes the [RESULT][FLAGS] reply from the TX pin, and checks
// both against a reference model. Also checks the HEX/LED register outputs.

`timescale 1ns/1ps

module tb_uart_alu;
    localparam integer CLK_HZ = 50_000_000;
    localparam integer BAUD   = 115_200;
    localparam real    CLK_NS = 20.0;
    localparam real    BIT_NS = ((CLK_HZ + BAUD / 2) / BAUD) * CLK_NS;

    reg clk = 0, rst = 1;
    always #(CLK_NS / 2) clk = ~clk;

    reg  host_tx = 1;           // PC -> FPGA
    wire fpga_tx;               // FPGA -> PC
    wire [7:0] last_result;
    wire [3:0] last_flags;
    wire ferr, rx_busy, tx_busy;

    uart_alu #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) dut (
        .clk(clk), .rst(rst), .rx(host_tx), .tx(fpga_tx),
        .last_result(last_result), .last_flags(last_flags), .frame_err_seen(ferr),
        .rx_busy(rx_busy), .tx_busy(tx_busy));

    // ---------- host-side serial driver and decoder ----------
    task host_send(input [7:0] d);
        integer i;
        begin
            host_tx = 0; #(BIT_NS);
            for (i = 0; i < 8; i = i + 1) begin host_tx = d[i]; #(BIT_NS); end
            host_tx = 1; #(BIT_NS);
        end
    endtask

    task host_recv(output [7:0] d, output ok);
        integer i;
        begin
            @(negedge fpga_tx);
            #(BIT_NS / 2);
            ok = (fpga_tx == 0);
            for (i = 0; i < 8; i = i + 1) begin #(BIT_NS); d[i] = fpga_tx; end
            #(BIT_NS);
            ok = ok && (fpga_tx == 1);
        end
    endtask

    // ---------- reference model ----------
    function [11:0] model(input [2:0] op, input [7:0] a, input [7:0] b);  // {flags, y}
        reg [8:0] w; reg [7:0] y; reg c, v; integer n;
        begin
            c = 0; v = 0; n = b[2:0];
            case (op)
                0: begin w = a + b; y = w[7:0]; c = w[8]; v = (a[7] == b[7]) && (y[7] != a[7]); end
                1: begin w = {1'b0, a} - b; y = w[7:0]; c = (a < b); v = (a[7] != b[7]) && (y[7] != a[7]); end
                2: y = a & b;
                3: y = a | b;
                4: y = a ^ b;
                5: begin y = a << n; c = (n == 0) ? 0 : a[8 - n]; end
                6: begin y = a >> n; c = (n == 0) ? 0 : a[n - 1]; end
                default: y = ~a;
            endcase
            model = {v, y[7], c, (y == 0), y};
        end
    endfunction

    integer errors = 0, cmds = 0;
    reg [8*3-1:0] name;
    reg [7:0] r_res, r_flg;
    reg ok1, ok2;
    reg [11:0] exp;

    task run_cmd(input [2:0] op, input [7:0] a, input [7:0] b);
        begin
            exp = model(op, a, b);
            fork
                begin host_send({5'b0, op}); host_send(a); host_send(b); end
                begin host_recv(r_res, ok1); host_recv(r_flg, ok2); end
            join
            cmds = cmds + 1;
            case (op) 0: name="ADD"; 1: name="SUB"; 2: name="AND"; 3: name="OR "; 4: name="XOR";
                      5: name="SHL"; 6: name="SHR"; default: name="NOT"; endcase
            if (!ok1 || !ok2 || r_res !== exp[7:0] || r_flg !== {4'b0, exp[11:8]}
                || last_result !== exp[7:0] || last_flags !== exp[11:8]) begin
                errors = errors + 1;
                $display("  FAIL %s %02h,%02h -> got %02h flags %04b, expected %02h flags %04b",
                         name, a, b, r_res, r_flg[3:0], exp[7:0], exp[11:8]);
            end else
                $display("  %s %02h, %02h -> %02h  VNCZ=%04b", name, a, b, r_res, r_flg[3:0]);
        end
    endtask

    integer i;
    initial begin
        $dumpfile("build/tb_uart_alu.vcd");
        $dumpvars(0, tb_uart_alu);
        repeat (5) @(posedge clk); rst = 0;
        #(2 * BIT_NS);

        $display("tb_uart_alu: commands over UART at %0d baud", BAUD);
        run_cmd(0, 8'h7F, 8'h01);   // signed overflow
        run_cmd(0, 8'hFF, 8'h01);   // carry and zero
        run_cmd(1, 8'h10, 8'h20);   // borrow, negative
        run_cmd(1, 8'h80, 8'h01);   // signed overflow
        run_cmd(2, 8'hF0, 8'h3C);
        run_cmd(3, 8'hF0, 8'h0F);
        run_cmd(4, 8'hAA, 8'hAA);   // zero
        run_cmd(5, 8'h81, 8'h01);   // carry out of bit 7
        run_cmd(6, 8'h03, 8'h01);   // carry out of bit 0
        run_cmd(7, 8'h00, 8'h00);
        for (i = 0; i < 40; i = i + 1)
            run_cmd($random, $random, $random);

        if (ferr !== 1'b0) begin errors = errors + 1; $display("  FAIL: unexpected framing error"); end

        if (errors == 0) $display("PASS: %0d commands, 0 mismatches", cmds);
        else             $display("FAIL: %0d of %0d commands", errors, cmds);
        $finish;
    end
endmodule
