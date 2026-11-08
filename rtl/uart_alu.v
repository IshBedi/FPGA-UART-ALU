// uart_alu.v
// Ish Bedi
//
// UART-controlled ALU. A host sends a 3-byte command and gets a 2-byte reply:
//
//   host -> FPGA :  [OP] [A] [B]          (OP uses bits [2:0], see alu8.v)
//   FPGA -> host :  [RESULT] [FLAGS]      (FLAGS = {4'b0000, V, N, C, Z})
//
// A framing error in the middle of a command throws the partial command away
// and sets the sticky `frame_err_seen` flag (cleared by reset).

module uart_alu #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD   = 115_200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output wire       tx,
    output reg  [7:0] last_result,
    output reg  [3:0] last_flags,
    output reg        frame_err_seen,
    output wire       rx_busy,
    output wire       tx_busy
);
    // ---------------- UART ----------------
    wire [7:0] rx_data;
    wire       rx_valid, rx_ferr;
    reg        tx_start;
    reg  [7:0] tx_data;
    wire       tx_done;

    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_rx (
        .clk(clk), .rst(rst), .rx(rx),
        .data(rx_data), .valid(rx_valid), .frame_err(rx_ferr), .busy(rx_busy)
    );

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_tx (
        .clk(clk), .rst(rst), .start(tx_start), .data(tx_data),
        .tx(tx), .busy(tx_busy), .done(tx_done)
    );

    // ---------------- ALU -----------------
    reg  [2:0] op_r;
    reg  [7:0] a_r, b_r;
    wire [7:0] alu_y;
    wire [3:0] alu_flags;

    alu8 u_alu (.op(op_r), .a(a_r), .b(b_r), .y(alu_y), .flags(alu_flags));

    // ------------- command FSM ------------
    localparam [2:0] S_GET_OP   = 3'd0,
                     S_GET_A    = 3'd1,
                     S_GET_B    = 3'd2,
                     S_EXEC     = 3'd3,
                     S_SEND_RES = 3'd4,
                     S_SEND_FLG = 3'd5;

    reg [2:0] state;
    reg       waiting;   // a byte has been handed to uart_tx, wait for `done`

    always @(posedge clk) begin
        if (rst) begin
            state          <= S_GET_OP;
            waiting        <= 1'b0;
            tx_start       <= 1'b0;
            tx_data        <= 8'h00;
            op_r           <= 3'd0;
            a_r            <= 8'h00;
            b_r            <= 8'h00;
            last_result    <= 8'h00;
            last_flags     <= 4'h0;
            frame_err_seen <= 1'b0;
        end else begin
            tx_start <= 1'b0;

            if (rx_ferr) frame_err_seen <= 1'b1;

            case (state)
                S_GET_OP: if (rx_valid) begin op_r <= rx_data[2:0]; state <= S_GET_A; end
                S_GET_A: begin
                    if (rx_ferr)       state <= S_GET_OP;
                    else if (rx_valid) begin a_r <= rx_data; state <= S_GET_B; end
                end
                S_GET_B: begin
                    if (rx_ferr)       state <= S_GET_OP;
                    else if (rx_valid) begin b_r <= rx_data; state <= S_EXEC; end
                end
                S_EXEC: begin                      // operands are registered, ALU output is settled
                    last_result <= alu_y;
                    last_flags  <= alu_flags;
                    state       <= S_SEND_RES;
                end
                S_SEND_RES: begin
                    if (!waiting) begin
                        tx_data  <= last_result;
                        tx_start <= 1'b1;
                        waiting  <= 1'b1;
                    end else if (tx_done) begin
                        waiting <= 1'b0;
                        state   <= S_SEND_FLG;
                    end
                end
                S_SEND_FLG: begin
                    if (!waiting) begin
                        tx_data  <= {4'b0000, last_flags};
                        tx_start <= 1'b1;
                        waiting  <= 1'b1;
                    end else if (tx_done) begin
                        waiting <= 1'b0;
                        state   <= S_GET_OP;
                    end
                end
                default: state <= S_GET_OP;
            endcase
        end
    end
endmodule
