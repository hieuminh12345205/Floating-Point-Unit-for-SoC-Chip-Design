// =============================================================================
//  fpu_add_sub_fixed.v
//  IEEE 754 single-precision (binary32) ADD/SUB - self-contained
//  Bao gom: fpu_unpack, fpu_normalize, fpu_round, fpu_pack (FIXED), fpu_add_sub
//
//  Sua loi: fpu_pack ban goc khong encode dung khi ket qua la subnormal
//           (mantissa[23] = 0, exp_unbiased = -126). Phien ban nay them
//           nhanh kiem tra mantissa[23] == 0 de encode bias = 0.
// =============================================================================
`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// Hang so IEEE 754 single
// -----------------------------------------------------------------------------
`define FPU_BIAS            127
`define FPU_FLAG_INVALID      4
`define FPU_FLAG_DIV_ZERO     3
`define FPU_FLAG_OVERFLOW     2
`define FPU_FLAG_UNDERFLOW    1
`define FPU_FLAG_INEXACT      0
`define FPU_FLAGS_NONE        5'b00000
`define FPU_CANONICAL_QNAN    32'h7fc0_0000
`define FPU_POS_INF           32'h7f80_0000
`define FPU_NEG_INF           32'hff80_0000
`define FPU_POS_ZERO          32'h0000_0000
`define FPU_NEG_ZERO          32'h8000_0000

// =============================================================================
//  fpu_unpack: tach 32-bit IEEE 754 thanh (sign, exp, mantissa) va co {nan,inf,
//  subnormal,normal,zero}. Voi subnormal: mantissa khong co bit an dau, exp = -126.
// =============================================================================
module fpu_unpack (
    input  wire [31:0]       value,
    output wire              sign,
    output wire [7:0]        exp_raw,
    output wire [22:0]       frac,
    output wire [23:0]       mantissa,
    output reg  signed [9:0] exp_unbiased,
    output wire              is_zero,
    output wire              is_subnormal,
    output wire              is_normal,
    output wire              is_inf,
    output wire              is_nan
);
    assign sign    = value[31];
    assign exp_raw = value[30:23];
    assign frac    = value[22:0];

    assign is_zero      = (exp_raw == 8'h00) && (frac == 23'h0);
    assign is_subnormal = (exp_raw == 8'h00) && (frac != 23'h0);
    assign is_normal    = (exp_raw != 8'h00) && (exp_raw != 8'hff);
    assign is_inf       = (exp_raw == 8'hff) && (frac == 23'h0);
    assign is_nan       = (exp_raw == 8'hff) && (frac != 23'h0);

    assign mantissa = (exp_raw == 8'h00) ? {1'b0, frac} : {1'b1, frac};

    always @* begin
        if (exp_raw == 8'h00)
            exp_unbiased = -10'sd126;  // subnormal/zero scale
        else
            exp_unbiased = $signed({2'b00, exp_raw}) - 10'sd127;
    end
endmodule

// =============================================================================
//  fpu_normalize: dua mantissa 28-bit ve dang co bit dan dau o vi tri 26.
//   - Neu bit 27 set (carry tu phep cong): shift phai 1, exp += 1.
//   - Neu bit 26 = 0 va exp > -126: shift trai cho den khi bit 26 set hoac
//     exp cham -126 (giu nghiem subnormal). Toi da 26 lan shift -> dung 27 vong
//     lap dam bao chac chan.
// =============================================================================
module fpu_normalize (
    input  wire signed [9:0] exp_in,
    input  wire [27:0]       mant_in,
    output reg  signed [9:0] exp_out,
    output reg  [26:0]       mant_out,
    output reg               is_zero
);
    integer    shift_count;
    reg [27:0] work;

    always @* begin
        work        = mant_in;
        exp_out     = exp_in;
        is_zero     = (mant_in == 28'h0);
        shift_count = 0;
        mant_out    = 27'h0;

        if (is_zero) begin
            exp_out  = -10'sd126;
            mant_out = 27'h0;
        end else if (work[27]) begin
            // Right shift 1, OR sticky cu vao LSB moi
            mant_out    = work[27:1];
            mant_out[0] = mant_out[0] | work[0];
            exp_out     = exp_in + 10'sd1;
        end else begin
            for (shift_count = 0; shift_count < 27; shift_count = shift_count + 1) begin
                if (!work[26] && (work != 28'h0) && (exp_out > -10'sd126)) begin
                    work    = work << 1;
                    exp_out = exp_out - 10'sd1;
                end
            end
            mant_out = work[26:0];
        end
    end
endmodule

// =============================================================================
//  fpu_round: round-to-nearest, ties-to-even (RNE).
//   mant_in[26:3] = 24-bit main mantissa
//   mant_in[2]    = Guard
//   mant_in[1]    = Round
//   mant_in[0]    = Sticky
//   increment = G AND (R OR S OR LSB)  -- chuan IEEE RNE
//   Neu round gay tran bit 24, exp += 1, mantissa shift phai 1.
// =============================================================================
module fpu_round (
    input  wire signed [9:0] exp_in,
    input  wire [26:0]       mant_in,
    output reg  signed [9:0] exp_out,
    output reg  [23:0]       mant_out,
    output reg               inexact
);
    reg [23:0] mant_main;
    reg        guard_bit, round_bit, sticky_bit, increment;
    reg [24:0] rounded;

    always @* begin
        mant_main  = mant_in[26:3];
        guard_bit  = mant_in[2];
        round_bit  = mant_in[1];
        sticky_bit = mant_in[0];
        inexact    = guard_bit | round_bit | sticky_bit;

        increment = guard_bit && (round_bit || sticky_bit || mant_main[0]);
        rounded   = {1'b0, mant_main} + increment;

        if (rounded[24]) begin
            mant_out = rounded[24:1];
            exp_out  = exp_in + 10'sd1;
        end else begin
            mant_out = rounded[23:0];
            exp_out  = exp_in;
        end
    end
endmodule

// =============================================================================
//  fpu_pack (FIXED): dong goi (sign, exp, mantissa) thanh 32-bit IEEE 754.
//
//  Phan biet 4 truong hop:
//    1. Force NaN/Inf/Zero (do tang tren).
//    2. exp_unbiased > 127           -> overflow -> +/-Inf, set overflow flag.
//    3. exp_unbiased < -126          -> tiny -> shift phai de thanh subnormal.
//    4. mantissa[23] == 0            -> ket qua subnormal (exp=-126, khong co bit
//                                       an): encode bias = 0.  *** PHAN MOI SUA ***
//    5. Mac dinh                     -> normal, bias = exp_unbiased + 127.
// =============================================================================
module fpu_pack (
    input  wire              sign,
    input  wire signed [9:0] exp_unbiased,
    input  wire [23:0]       mantissa,
    input  wire              force_zero,
    input  wire              force_inf,
    input  wire              force_nan,
    output reg  [31:0]       result,
    output reg               overflow,
    output reg               underflow
);
    integer    shift_amount;
    reg [23:0] shifted;
    reg [7:0]  exp_biased;

    always @* begin
        overflow     = 1'b0;
        underflow    = 1'b0;
        shift_amount = 0;
        shifted      = 24'h0;
        exp_biased   = 8'h0;
        result       = `FPU_POS_ZERO;

        if (force_nan) begin
            result = `FPU_CANONICAL_QNAN;
        end else if (force_inf) begin
            result = {sign, 8'hff, 23'h0};
        end else if (force_zero || (mantissa == 24'h0)) begin
            result = {sign, 31'h0};
        end else if (exp_unbiased > 10'sd127) begin
            overflow = 1'b1;
            result   = {sign, 8'hff, 23'h0};
        end else if (exp_unbiased < -10'sd126) begin
            // Khong xay ra trong ADD/SUB binh thuong (normalize gioi han exp >= -126)
            // nhung giu nhanh nay cho MUL/DIV.
            underflow    = 1'b1;
            shift_amount = -10'sd126 - exp_unbiased;
            if (shift_amount >= 24) begin
                result = {sign, 31'h0};
            end else begin
                shifted = mantissa >> shift_amount;
                result  = {sign, 8'h00, shifted[22:0]};
            end
        end else if (mantissa[23] == 1'b0) begin
            // *** FIX: ket qua subnormal that su (exp = -126, khong co leading 1).
            //     exp_biased phai = 0 chu khong phai 1.
            underflow = 1'b1;
            result    = {sign, 8'h00, mantissa[22:0]};
        end else begin
            exp_biased = exp_unbiased + `FPU_BIAS;
            result     = {sign, exp_biased, mantissa[22:0]};
        end
    end
endmodule

// =============================================================================
//  fpu_add_sub: thuat toan kinh dien
//    1. Unpack a, b.
//    2. Xu ly cac case dac biet: NaN, Inf, +/-0.
//    3. Chon lon/nho theo |.|: lon -> giu nguyen exp & sign.
//    4. Align nho bang shift_right_sticky theo exp_diff.
//    5. Cong (cung dau) hoac tru (khac dau) mantissa 27-bit.
//    6. Normalize -> Round (RNE) -> Pack.
//
//  op_sub = 1 -> dao dau cua b truoc khi xu ly (b_eff_sign).
// =============================================================================
module fpu_add_sub (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        op_sub,
    output wire [31:0] result,
    output wire [4:0]  flags
);
    // -------------------------------------------------------------------------
    // Unpack
    // -------------------------------------------------------------------------
    wire              a_sign, b_sign;
    wire [7:0]        a_exp_raw, b_exp_raw;
    wire [22:0]       a_frac, b_frac;
    wire [23:0]       a_mant, b_mant;
    wire signed [9:0] a_exp, b_exp;
    wire a_zero, a_subnormal, a_normal, a_inf, a_nan;
    wire b_zero, b_subnormal, b_normal, b_inf, b_nan;

    fpu_unpack unpack_a (
        .value(a), .sign(a_sign), .exp_raw(a_exp_raw), .frac(a_frac),
        .mantissa(a_mant), .exp_unbiased(a_exp),
        .is_zero(a_zero), .is_subnormal(a_subnormal),
        .is_normal(a_normal), .is_inf(a_inf), .is_nan(a_nan)
    );
    fpu_unpack unpack_b (
        .value(b), .sign(b_sign), .exp_raw(b_exp_raw), .frac(b_frac),
        .mantissa(b_mant), .exp_unbiased(b_exp),
        .is_zero(b_zero), .is_subnormal(b_subnormal),
        .is_normal(b_normal), .is_inf(b_inf), .is_nan(b_nan)
    );

    // -------------------------------------------------------------------------
    // Ham shift phai voi sticky
    //   Sticky = OR cua tat ca bit bi day xuong duoi bit 0.
    //   Voi shift >= 27, tat ca bit deu mat -> sticky = (|value).
    // -------------------------------------------------------------------------
    function [26:0] shift_right_sticky;
        input [26:0] value;
        input integer shift;
        integer i;
        reg sticky;
        begin
            sticky = 1'b0;
            if (shift <= 0) begin
                shift_right_sticky = value;
            end else if (shift >= 27) begin
                shift_right_sticky = {26'h0, |value};
            end else begin
                for (i = 0; i < 27; i = i + 1)
                    if (i < shift) sticky = sticky | value[i];
                shift_right_sticky    = value >> shift;
                shift_right_sticky[0] = shift_right_sticky[0] | sticky;
            end
        end
    endfunction

    // -------------------------------------------------------------------------
    // Tin hieu noi giua cac block
    // -------------------------------------------------------------------------
    reg              use_special;
    reg [31:0]       special_result;
    reg [4:0]        special_flags;
    reg              sign_res;
    reg signed [9:0] pre_norm_exp;
    reg [27:0]       pre_norm_mant;

    reg              b_eff_sign;
    reg              large_sign, small_sign;
    reg signed [9:0] large_exp;
    reg [26:0]       large_mant, small_mant;
    reg [27:0]       add_mant;
    reg [26:0]       sub_mant;
    integer          exp_diff;

    wire signed [9:0] norm_exp;
    wire [26:0]       norm_mant;
    wire              norm_zero;
    wire signed [9:0] round_exp;
    wire [23:0]       round_mant;
    wire              round_inexact;
    wire [31:0]       packed_result;
    wire              pack_overflow, pack_underflow;

    fpu_normalize normalize_unit (
        .exp_in(pre_norm_exp), .mant_in(pre_norm_mant),
        .exp_out(norm_exp), .mant_out(norm_mant), .is_zero(norm_zero)
    );
    fpu_round round_unit (
        .exp_in(norm_exp), .mant_in(norm_mant),
        .exp_out(round_exp), .mant_out(round_mant), .inexact(round_inexact)
    );
    fpu_pack pack_unit (
        .sign(sign_res), .exp_unbiased(round_exp), .mantissa(round_mant),
        .force_zero(norm_zero), .force_inf(1'b0), .force_nan(1'b0),
        .result(packed_result),
        .overflow(pack_overflow), .underflow(pack_underflow)
    );

    // -------------------------------------------------------------------------
    // Combinational datapath
    // -------------------------------------------------------------------------
    always @* begin
        b_eff_sign     = b_sign ^ op_sub;
        use_special    = 1'b0;
        special_result = `FPU_POS_ZERO;
        special_flags  = `FPU_FLAGS_NONE;
        sign_res       = 1'b0;
        pre_norm_exp   = -10'sd126;
        pre_norm_mant  = 28'h0;
        large_sign     = 1'b0;
        small_sign     = 1'b0;
        large_exp      = -10'sd126;
        large_mant     = 27'h0;
        small_mant     = 27'h0;
        add_mant       = 28'h0;
        sub_mant       = 27'h0;
        exp_diff       = 0;

        // ---- Cac case dac biet ----
        if (a_nan || b_nan) begin
            use_special    = 1'b1;
            special_result = `FPU_CANONICAL_QNAN;
            // sNaN se signal Invalid; qNaN propagate silent.
            special_flags[`FPU_FLAG_INVALID] =
                ((a_nan && !a_frac[22]) || (b_nan && !b_frac[22]));
        end else if (a_inf && b_inf && (a_sign != b_eff_sign)) begin
            // Inf - Inf  -> NaN, Invalid
            use_special    = 1'b1;
            special_result = `FPU_CANONICAL_QNAN;
            special_flags[`FPU_FLAG_INVALID] = 1'b1;
        end else if (a_inf) begin
            use_special    = 1'b1;
            special_result = {a_sign, 8'hff, 23'h0};
        end else if (b_inf) begin
            use_special    = 1'b1;
            special_result = {b_eff_sign, 8'hff, 23'h0};
        end else if (a_zero && b_zero) begin
            // RNE: dau cua zero = AND cua hai dau (chi -0 khi ca hai -0).
            use_special    = 1'b1;
            special_result = {(a_sign & b_eff_sign), 31'h0};
        end else begin
            // ---- Chon |larger|; cung exp thi so mantissa ----
            if ((a_exp > b_exp) ||
                ((a_exp == b_exp) && (a_mant >= b_mant))) begin
                large_sign = a_sign;
                small_sign = b_eff_sign;
                large_exp  = a_exp;
                large_mant = {a_mant, 3'b000};
                exp_diff   = a_exp - b_exp;
                small_mant = shift_right_sticky({b_mant, 3'b000}, exp_diff);
            end else begin
                large_sign = b_eff_sign;
                small_sign = a_sign;
                large_exp  = b_exp;
                large_mant = {b_mant, 3'b000};
                exp_diff   = b_exp - a_exp;
                small_mant = shift_right_sticky({a_mant, 3'b000}, exp_diff);
            end

            sign_res     = large_sign;
            pre_norm_exp = large_exp;

            if (large_sign == small_sign) begin
                add_mant      = {1'b0, large_mant} + {1'b0, small_mant};
                pre_norm_mant = add_mant;
            end else begin
                sub_mant      = large_mant - small_mant;
                pre_norm_mant = {1'b0, sub_mant};
                if (sub_mant == 27'h0) sign_res = 1'b0; // exact cancel -> +0 (RNE)
            end
        end
    end

    // -------------------------------------------------------------------------
    // Flag merge (IEEE 754-2008 default semantics):
    //   - Overflow -> implies Inexact (gia tri vo cung khac voi gia tri chinh xac).
    //   - Underflow flag chi raise khi "tiny AND inexact" (sau khi round).
    //   - Tiny exact (subnormal exact) khong signal underflow.
    // -------------------------------------------------------------------------
    assign result = use_special ? special_result : packed_result;
    assign flags  = use_special ? special_flags
                                : {1'b0,                              // invalid
                                   1'b0,                              // div_zero
                                   pack_overflow,                     // overflow
                                   pack_underflow & round_inexact,    // underflow
                                   round_inexact | pack_overflow};    // inexact
endmodule
