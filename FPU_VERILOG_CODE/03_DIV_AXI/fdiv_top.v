`timescale 1ns/1ps

// IEEE 754 single-precision floating-point divider.
//
// Interface is intentionally close to the original CK.zip fdiv_top so it can
// replace that file with minimal integration work.
module fdiv_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [31:0] operand_a,
    input  wire [31:0] operand_b,
    output reg  [31:0] result,
    output reg         done,
    output reg         overflow,
    output reg         underflow,
    output reg         div_by_zero,
    output reg         invalid_op,
    output wire [4:0]  flags
);

localparam [2:0]
    S_IDLE      = 3'd0,
    S_START_DIV = 3'd1,
    S_WAIT_DIV  = 3'd2,
    S_NORMALIZE = 3'd3,
    S_ROUND     = 3'd4,
    S_PACK      = 3'd5,
    S_DONE      = 3'd6;

localparam [31:0] QNAN = 32'h7fc0_0000;

reg [2:0] state;

reg        sign_r;
reg signed [10:0] exp_r;
reg [26:0] mant_grs;
reg [23:0] mant_rounded;
reg        inexact;

reg        div_start;
reg [23:0] div_mant_a;
reg [23:0] div_mant_b;
wire [26:0] div_quotient;
wire [50:0] div_remainder;
wire        div_done;
wire [26:0] div_quotient_shifted = div_quotient << 1;

fdiv_mant_divider mant_divider (
    .clk(clk),
    .rst_n(rst_n),
    .start(div_start),
    .dividend(div_mant_a),
    .divisor(div_mant_b),
    .quotient(div_quotient),
    .remainder(div_remainder),
    .done_div(div_done)
);

assign flags = {invalid_op, div_by_zero, overflow, underflow, inexact};

function [23:0] normalized_mantissa;
    input [7:0]  exp_raw;
    input [22:0] frac;
    integer i;
    reg [23:0] tmp;
    begin
        if (exp_raw != 8'h00) begin
            normalized_mantissa = {1'b1, frac};
        end else begin
            tmp = {1'b0, frac};
            for (i = 0; i < 23; i = i + 1) begin
                if (!tmp[23] && (tmp != 24'd0)) begin
                    tmp = tmp << 1;
                end
            end
            normalized_mantissa = tmp;
        end
    end
endfunction

function signed [10:0] normalized_exponent;
    input [7:0]  exp_raw;
    input [22:0] frac;
    integer i;
    reg [23:0] tmp;
    reg signed [10:0] exp_tmp;
    begin
        if (exp_raw != 8'h00) begin
            normalized_exponent = $signed({3'b000, exp_raw}) - 11'sd127;
        end else begin
            tmp = {1'b0, frac};
            exp_tmp = -11'sd126;
            for (i = 0; i < 23; i = i + 1) begin
                if (!tmp[23] && (tmp != 24'd0)) begin
                    tmp = tmp << 1;
                    exp_tmp = exp_tmp - 11'sd1;
                end
            end
            normalized_exponent = exp_tmp;
        end
    end
endfunction

wire        sign_a = operand_a[31];
wire        sign_b = operand_b[31];
wire [7:0]  exp_a  = operand_a[30:23];
wire [7:0]  exp_b  = operand_b[30:23];
wire [22:0] frac_a = operand_a[22:0];
wire [22:0] frac_b = operand_b[22:0];

wire a_zero = (exp_a == 8'h00) && (frac_a == 23'd0);
wire b_zero = (exp_b == 8'h00) && (frac_b == 23'd0);
wire a_inf  = (exp_a == 8'hff) && (frac_a == 23'd0);
wire b_inf  = (exp_b == 8'hff) && (frac_b == 23'd0);
wire a_nan  = (exp_a == 8'hff) && (frac_a != 23'd0);
wire b_nan  = (exp_b == 8'hff) && (frac_b != 23'd0);

reg [23:0] rounded_main;
reg [24:0] rounded_ext;
reg        round_inc;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state       <= S_IDLE;
        result      <= 32'd0;
        done        <= 1'b0;
        overflow    <= 1'b0;
        underflow   <= 1'b0;
        div_by_zero <= 1'b0;
        invalid_op  <= 1'b0;
        inexact     <= 1'b0;
        sign_r      <= 1'b0;
        exp_r       <= 11'sd0;
        mant_grs    <= 27'd0;
        mant_rounded<= 24'd0;
        div_start   <= 1'b0;
        div_mant_a  <= 24'd0;
        div_mant_b  <= 24'd0;
    end else begin
        done      <= 1'b0;
        div_start <= 1'b0;

        case (state)
            S_IDLE: begin
                if (start) begin
                    result      <= 32'd0;
                    overflow    <= 1'b0;
                    underflow   <= 1'b0;
                    div_by_zero <= 1'b0;
                    invalid_op  <= 1'b0;
                    inexact     <= 1'b0;
                    sign_r      <= sign_a ^ sign_b;

                    if (a_nan || b_nan) begin
                        result <= QNAN;
                        invalid_op <= 1'b1;
                        state <= S_DONE;
                    end else if ((a_inf && b_inf) || (a_zero && b_zero)) begin
                        result <= QNAN;
                        invalid_op <= 1'b1;
                        state <= S_DONE;
                    end else if (b_zero) begin
                        result <= {sign_a ^ sign_b, 8'hff, 23'd0};
                        div_by_zero <= 1'b1;
                        state <= S_DONE;
                    end else if (a_zero) begin
                        result <= {sign_a ^ sign_b, 31'd0};
                        state <= S_DONE;
                    end else if (a_inf) begin
                        result <= {sign_a ^ sign_b, 8'hff, 23'd0};
                        state <= S_DONE;
                    end else if (b_inf) begin
                        result <= {sign_a ^ sign_b, 31'd0};
                        state <= S_DONE;
                    end else begin
                        div_mant_a <= normalized_mantissa(exp_a, frac_a);
                        div_mant_b <= normalized_mantissa(exp_b, frac_b);
                        exp_r <= normalized_exponent(exp_a, frac_a)
                               - normalized_exponent(exp_b, frac_b);
                        state <= S_START_DIV;
                    end
                end
            end

            S_START_DIV: begin
                div_start <= 1'b1;
                state <= S_WAIT_DIV;
            end

            S_WAIT_DIV: begin
                if (div_done) begin
                    if (div_quotient[26]) begin
                        mant_grs <= {div_quotient[26:1],
                                     div_quotient[0] | (div_remainder != 51'd0)};
                    end else begin
                        mant_grs <= {div_quotient_shifted[26:1],
                                     div_quotient_shifted[0] | (div_remainder != 51'd0)};
                        exp_r <= exp_r - 11'sd1;
                    end
                    state <= S_NORMALIZE;
                end
            end

            S_NORMALIZE: begin
                rounded_main = mant_grs[26:3];
                round_inc = mant_grs[2] && (mant_grs[1] || mant_grs[0] || rounded_main[0]);
                rounded_ext = {1'b0, rounded_main} + round_inc;
                inexact <= mant_grs[2] | mant_grs[1] | mant_grs[0];

                if (rounded_ext[24]) begin
                    mant_rounded <= rounded_ext[24:1];
                    exp_r <= exp_r + 11'sd1;
                end else begin
                    mant_rounded <= rounded_ext[23:0];
                end
                state <= S_PACK;
            end

            S_PACK: begin
                if (exp_r > 11'sd127) begin
                    result <= {sign_r, 8'hff, 23'd0};
                    overflow <= 1'b1;
                    inexact <= 1'b1;
                end else if (exp_r < -11'sd126) begin
                    result <= {sign_r, 31'd0};
                    underflow <= 1'b1;
                    inexact <= 1'b1;
                end else begin
                    result <= {sign_r, exp_r[7:0] + 8'd127, mant_rounded[22:0]};
                end
                state <= S_DONE;
            end

            S_DONE: begin
                done <= 1'b1;
                state <= S_IDLE;
            end

            default: begin
                state <= S_IDLE;
            end
        endcase
    end
end

endmodule
