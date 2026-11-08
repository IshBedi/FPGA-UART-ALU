// uart_tx.v
// Ish Bedi
//
// 8N1 UART transmitter. Frame: 1 start bit (0), 8 data bits LSB first, 1 stop bit (1).
// A private baud_gen runs only while a frame is in flight, so each bit lasts
// exactly CLK_HZ/BAUD clocks (434 at 50 MHz / 115200).
//
// Handshake: pulse `start` for one clock while `busy` is low; `data` is latched then.
// `done` pulses for one clock when the stop bit has finished.

module uart_tx #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD   = 115_200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire [7:0] data,
    output reg        tx,
    output wire       busy,
    output reg        done
);
    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    reg  [1:0] state;
    reg  [7:0] shreg;     // data shift register, LSB goes out first
    reg  [2:0] bit_idx;   // which data bit is on the line
    wire       bit_tick;

    assign busy = (state != S_IDLE);

    baud_gen #(.CLK_HZ(CLK_HZ), .BAUD(BAUD), .OVERSAMPLE(1)) u_baud (
        .clk (clk),
        .rst (rst),
        .en  (busy),
        .tick(bit_tick)
    );

    always @(posedge clk) begin
        if (rst) begin
            state   <= S_IDLE;
            tx      <= 1'b1;
            shreg   <= 8'h00;
            bit_idx <= 3'd0;
            done    <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    tx <= 1'b1;
                    if (start) begin
                        shreg <= data;
                        tx    <= 1'b0;          // start bit goes out immediately
                        state <= S_START;
                    end
                end

                S_START: if (bit_tick) begin
                    tx      <= shreg[0];
                    shreg   <= {1'b0, shreg[7:1]};
                    bit_idx <= 3'd0;
                    state   <= S_DATA;
                end

                S_DATA: if (bit_tick) begin
                    if (bit_idx == 3'd7) begin
                        tx    <= 1'b1;          // stop bit
                        state <= S_STOP;
                    end else begin
                        tx      <= shreg[0];
                        shreg   <= {1'b0, shreg[7:1]};
                        bit_idx <= bit_idx + 1'b1;
                    end
                end

                S_STOP: if (bit_tick) begin
                    state <= S_IDLE;
                    done  <= 1'b1;
                end
            endcase
        end
    end
endmodule
