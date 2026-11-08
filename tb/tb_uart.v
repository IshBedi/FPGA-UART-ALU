// tb_uart.v
// Ish Bedi
//
// UART loopback test at 50 MHz / 115200 baud.
//  1. Every byte 0x00-0xFF goes through uart_tx -> uart_rx and must come back unchanged.
//  2. A timing monitor on the TX line checks every edge lands on a bit boundary
//     (start bit at t0, edges at t0 + k * 8680 ns) and every frame is 10 bits long.
//  3. A hand-built frame with a low stop bit must raise frame_err, not valid.
//  4. A low glitch shorter than half a bit must not start a frame.

`timescale 1ns/1ps

module tb_uart;
    localparam integer CLK_HZ   = 50_000_000;
    localparam integer BAUD     = 115_200;
    localparam real    CLK_NS   = 20.0;
    localparam integer CLKS_BIT = (CLK_HZ + BAUD / 2) / BAUD;   // 434
    localparam real    BIT_NS   = CLKS_BIT * CLK_NS;            // 8680 ns

    reg clk = 0, rst = 1;
    always #(CLK_NS / 2) clk = ~clk;

    // TX
    reg        tx_start = 0;
    reg  [7:0] tx_data  = 0;
    wire       tx_line, tx_busy, tx_done;

    // RX input is either the transmitter or a hand-driven line
    reg  use_manual = 0, manual_line = 1;
    wire rx_line = use_manual ? manual_line : tx_line;
    wire [7:0] rx_data;
    wire       rx_valid, rx_ferr, rx_busy;

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_tx (
        .clk(clk), .rst(rst), .start(tx_start), .data(tx_data),
        .tx(tx_line), .busy(tx_busy), .done(tx_done));

    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_rx (
        .clk(clk), .rst(rst), .rx(rx_line),
        .data(rx_data), .valid(rx_valid), .frame_err(rx_ferr), .busy(rx_busy));

    integer errors = 0;

    // ---------- bit-timing monitor ----------
    realtime t_frame;
    real     off, k;
    integer  edges = 0, timing_err = 0;
    reg      in_frame = 0;

    always @(tx_line) if (!rst && !use_manual) begin
        if (!in_frame && tx_line == 1'b0) begin
            in_frame = 1; t_frame = $realtime;
        end else if (in_frame) begin
            off = $realtime - t_frame;
            k   = off / BIT_NS;
            if (off - $rtoi(k + 0.5) * BIT_NS > 0.5 || off - $rtoi(k + 0.5) * BIT_NS < -0.5) begin
                timing_err = timing_err + 1;
                if (timing_err <= 5) $display("  TIMING: edge at %0.1f ns into frame is not on a bit boundary", off);
            end
            edges = edges + 1;
        end
    end

    always @(posedge tx_done) begin
        off = $realtime - t_frame;
        // done is raised by the clock edge that ends the stop bit
        if (off < 10 * BIT_NS - 0.5 || off > 10 * BIT_NS + CLK_NS + 0.5) begin
            timing_err = timing_err + 1;
            $display("  TIMING: frame length %0.1f ns, expected %0.1f ns", off, 10 * BIT_NS);
        end
        in_frame = 0;
    end

    // ---------- helpers ----------
    task send_byte(input [7:0] d);
        begin
            @(posedge clk); tx_data <= d; tx_start <= 1;
            @(posedge clk); tx_start <= 0;
            @(posedge tx_done);
        end
    endtask

    task drive_bit(input v); begin manual_line = v; #(BIT_NS); end endtask

    reg [7:0] got;
    reg       got_flag;
    always @(posedge clk) if (rx_valid) begin got <= rx_data; got_flag <= 1; end

    integer i;
    integer ferr_seen = 0, valid_seen = 0;
    always @(posedge clk) begin
        if (rx_ferr)  ferr_seen  = ferr_seen + 1;
        if (rx_valid) valid_seen = valid_seen + 1;
    end

    initial begin
        $dumpfile("build/tb_uart.vcd");
        $dumpvars(0, tb_uart);
        repeat (5) @(posedge clk); rst = 0;
        repeat (2 * CLKS_BIT) @(posedge clk);          // idle line before the first frame

        // 1. loopback of all 256 values (first one is 0xA5 for the waveform)
        $display("tb_uart: loopback of 256 bytes at %0d baud (%0d clocks/bit)", BAUD, CLKS_BIT);
        for (i = -1; i < 256; i = i + 1) begin
            got_flag = 0;
            send_byte(i < 0 ? 8'hA5 : i[7:0]);
            repeat (CLKS_BIT) @(posedge clk);          // rx reports at mid-stop, give it margin
            if (!got_flag || got !== (i < 0 ? 8'hA5 : i[7:0])) begin
                errors = errors + 1;
                $display("  LOOPBACK FAIL: sent %02h, got %02h (valid=%0d)", (i < 0 ? 8'hA5 : i[7:0]), got, got_flag);
            end
        end
        $display("  loopback: 257 frames, %0d data errors", errors);
        $display("  timing:   %0d TX edges checked, %0d off-boundary", edges, timing_err);

        // 2. framing error: stop bit driven low
        use_manual = 1; manual_line = 1; #(2 * BIT_NS);
        ferr_seen = 0; valid_seen = 0;
        drive_bit(0);                                   // start
        for (i = 0; i < 8; i = i + 1) drive_bit(i[0]);  // 0x55 pattern
        drive_bit(0);                                   // bad stop
        drive_bit(1); drive_bit(1);
        if (ferr_seen != 1 || valid_seen != 0) begin
            errors = errors + 1;
            $display("  FRAMING FAIL: frame_err=%0d valid=%0d", ferr_seen, valid_seen);
        end else $display("  framing:  bad stop bit flagged, byte discarded");

        // 3. glitch: low pulse of 1/4 bit must not start a frame
        ferr_seen = 0; valid_seen = 0;
        manual_line = 0; #(BIT_NS / 4); manual_line = 1;
        #(12 * BIT_NS);
        if (ferr_seen != 0 || valid_seen != 0 || rx_busy) begin
            errors = errors + 1;
            $display("  GLITCH FAIL: receiver reacted to a 1/4-bit pulse");
        end else $display("  glitch:   1/4-bit low pulse rejected");

        errors = errors + timing_err;
        if (errors == 0) $display("PASS");
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end
endmodule
