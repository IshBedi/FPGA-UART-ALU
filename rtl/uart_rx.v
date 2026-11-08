// uart_rx.v
// Ish Bedi
//
// 8N1 UART receiver with 16x oversampling.
//  - The asynchronous `rx` pin passes through a two-flop synchronizer.
//  - Only a high-to-low edge in IDLE starts a frame (a line held low after a bad
//    stop bit or a break does not re-trigger). The line is re-checked at the
//    middle of the start bit (8 ticks) so a short glitch is rejected.
//  - Each data bit is then sampled 16 ticks later, i.e. at its centre.
//  - The stop bit is checked at its centre: high gives `valid`, low gives `frame_err`.

module uart_rx #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD   = 115_200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid,      // one-clock pulse, `data` is good
    output reg        frame_err,  // one-clock pulse, stop bit was low
    output wire       busy
);
    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    // two-flop synchronizer, reset to the idle (high) level
    reg rx_meta, rx_sync, rx_prev;
    always @(posedge clk) begin
        if (rst) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
            rx_prev <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
            rx_prev <= rx_sync;
        end
    end
    wire fall = rx_prev & ~rx_sync;

    wire os_tick;
    baud_gen #(.CLK_HZ(CLK_HZ), .BAUD(BAUD), .OVERSAMPLE(16)) u_baud (
        .clk (clk),
        .rst (rst),
        .en  (1'b1),
        .tick(os_tick)
    );

    reg [1:0] state;
    reg [3:0] os_cnt;    // oversample ticks within the current bit
    reg [2:0] bit_idx;
    reg [7:0] shreg;

    assign busy = (state != S_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state     <= S_IDLE;
            os_cnt    <= 4'd0;
            bit_idx   <= 3'd0;
            shreg     <= 8'h00;
            data      <= 8'h00;
            valid     <= 1'b0;
            frame_err <= 1'b0;
        end else begin
            valid     <= 1'b0;
            frame_err <= 1'b0;
            case (state)
                S_IDLE: if (fall) begin
                    os_cnt <= 4'd0;
                    state  <= S_START;
                end

                S_START: if (os_tick) begin
                    if (os_cnt == 4'd7) begin          // middle of start bit
                        os_cnt  <= 4'd0;
                        bit_idx <= 3'd0;
                        state   <= rx_sync ? S_IDLE : S_DATA;
                    end else
                        os_cnt <= os_cnt + 1'b1;
                end

                S_DATA: if (os_tick) begin
                    if (os_cnt == 4'd15) begin         // middle of a data bit
                        os_cnt <= 4'd0;
                        shreg  <= {rx_sync, shreg[7:1]};
                        if (bit_idx == 3'd7) state <= S_STOP;
                        else                 bit_idx <= bit_idx + 1'b1;
                    end else
                        os_cnt <= os_cnt + 1'b1;
                end

                S_STOP: if (os_tick) begin
                    if (os_cnt == 4'd15) begin         // middle of stop bit
                        os_cnt <= 4'd0;
                        state  <= S_IDLE;
                        if (rx_sync) begin
                            data  <= shreg;
                            valid <= 1'b1;
                        end else
                            frame_err <= 1'b1;
                    end else
                        os_cnt <= os_cnt + 1'b1;
                end
            endcase
        end
    end
endmodule
