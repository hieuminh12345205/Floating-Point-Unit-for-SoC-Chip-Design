`timescale 1ns/1ps

// Restoring-style unsigned divider for normalized 24-bit mantissas.
//
// It computes:
//   quotient = floor((dividend << 26) / divisor)
//
// The 27-bit quotient is enough for:
//   quotient[26:3] = 24-bit mantissa candidate
//   quotient[2]    = guard bit
//   quotient[1]    = round bit
//   quotient[0]    = sticky candidate, OR'ed with non-zero remainder in top
module fdiv_mant_divider (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [23:0] dividend,
    input  wire [23:0] divisor,
    output reg  [26:0] quotient,
    output reg  [50:0] remainder,
    output reg         done_div
);

localparam IDLE   = 2'd0;
localparam RUN    = 2'd1;
localparam FINISH = 2'd2;

reg [1:0]  state;
reg [5:0]  bit_index;
reg [26:0] quotient_work;
reg [50:0] remainder_work;
reg [23:0] divisor_work;

wire [50:0] shifted_divisor = ({27'b0, divisor_work} << bit_index);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state          <= IDLE;
        bit_index      <= 6'd0;
        quotient       <= 27'd0;
        quotient_work  <= 27'd0;
        remainder      <= 51'd0;
        remainder_work <= 51'd0;
        divisor_work   <= 24'd0;
        done_div       <= 1'b0;
    end else begin
        done_div <= 1'b0;

        case (state)
            IDLE: begin
                if (start) begin
                    remainder_work <= {1'b0, dividend, 26'b0};
                    divisor_work   <= divisor;
                    quotient_work  <= 27'd0;
                    bit_index      <= 6'd26;
                    state          <= RUN;
                end
            end

            RUN: begin
                if (remainder_work >= shifted_divisor) begin
                    remainder_work            <= remainder_work - shifted_divisor;
                    quotient_work[bit_index]  <= 1'b1;
                end

                if (bit_index == 6'd0) begin
                    state <= FINISH;
                end else begin
                    bit_index <= bit_index - 6'd1;
                end
            end

            FINISH: begin
                quotient <= quotient_work;
                remainder <= remainder_work;
                done_div <= 1'b1;
                state <= IDLE;
            end

            default: begin
                state <= IDLE;
            end
        endcase
    end
end

endmodule
