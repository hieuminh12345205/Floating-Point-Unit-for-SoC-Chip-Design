// =============================================================================
//  tb_fpu_add_sub_fixed.v
//  Testbench self-contained cho fpu_add_sub_fixed.v
//
//  Cach chay:
//    iverilog -o sim tb_fpu_add_sub_fixed.v ../rtl/fpu_add_sub_fixed.v
//    vvp sim
//  hoac voi Vivado xsim:
//    xvlog tb_fpu_add_sub_fixed.v ../rtl/fpu_add_sub_fixed.v
//    xelab -debug typical tb_fpu_add_sub_fixed -s sim
//    xsim sim -R
//
//  Cot ket qua: PASS / FAIL kem trace gia tri input, output, expected,
//  flags. Cuoi cung in tong so PASS/total. $finish voi exit code khac 0
//  neu co FAIL.
//
//  Quy uoc flag (5 bit): {invalid, div_zero, overflow, underflow, inexact}
//   - underflow chi raise khi tiny AND inexact (IEEE 754 default).
//   - overflow -> implies inexact.
// =============================================================================
`timescale 1ns/1ps

module tb_fpu_add_sub_fixed;
    reg  [31:0] a;
    reg  [31:0] b;
    reg         op_sub;
    wire [31:0] result;
    wire [4:0]  flags;

    integer total;
    integer passed;
    integer failed;

    fpu_add_sub dut (
        .a(a), .b(b), .op_sub(op_sub),
        .result(result), .flags(flags)
    );

    // -------------------------------------------------------------------------
    // Task kiem tra ket qua + flags
    //   description: string mo ta (toi da 32 ky tu, dung trong cho bo)
    // -------------------------------------------------------------------------
    task check;
        input [511:0] description;   // toi da 64 ky tu ASCII
        input [31:0]  a_in;
        input [31:0]  b_in;
        input         op_sub_in;
        input [31:0]  expected_result;
        input [4:0]   expected_flags;
        begin
            a      = a_in;
            b      = b_in;
            op_sub = op_sub_in;
            #1;
            total = total + 1;
            if ((result === expected_result) && (flags === expected_flags)) begin
                passed = passed + 1;
                $display("[PASS] %0s | %h %s %h = %h flags=%b",
                         description, a_in, (op_sub_in ? "-" : "+"),
                         b_in, result, flags);
            end else begin
                failed = failed + 1;
                $display("[FAIL] %0s", description);
                $display("       inputs : a=%h b=%h op_sub=%b", a_in, b_in, op_sub_in);
                $display("       got    : result=%h flags=%b", result, flags);
                $display("       expect : result=%h flags=%b", expected_result, expected_flags);
            end
        end
    endtask

    // Tien ich: bit position
    localparam [4:0] F_NONE     = 5'b00000;
    localparam [4:0] F_INVALID  = 5'b10000;
    localparam [4:0] F_OVERFLOW = 5'b00100; // overflow alone (without inexact)
    localparam [4:0] F_OVF_INX  = 5'b00101; // overflow + inexact
    localparam [4:0] F_UF_INX   = 5'b00011; // underflow + inexact
    localparam [4:0] F_INEXACT  = 5'b00001;

    initial begin
        total  = 0;
        passed = 0;
        failed = 0;
        a      = 32'h0;
        b      = 32'h0;
        op_sub = 1'b0;

        $display("============================================================");
        $display("  FPU ADD/SUB Test Suite (binary32 IEEE 754)");
        $display("============================================================");

        // ====================================================================
        // 1. Cac case binh thuong (normal ranges)
        // ====================================================================
        $display("-- [Group 1] Phep cong/tru thong thuong --");
        check("1 + 2 = 3",                32'h3F800000, 32'h40000000, 1'b0, 32'h40400000, F_NONE);
        check("-1.5 + 0.5 = -1",          32'hBFC00000, 32'h3F000000, 1'b0, 32'hBF800000, F_NONE);
        check("1 + 1 = 2 (carry-norm)",   32'h3F800000, 32'h3F800000, 1'b0, 32'h40000000, F_NONE);
        check("-1 + -1 = -2",             32'hBF800000, 32'hBF800000, 1'b0, 32'hC0000000, F_NONE);
        check("1 + (-1) = +0 (cancel)",   32'h3F800000, 32'hBF800000, 1'b0, 32'h00000000, F_NONE);
        check("3 - 1 = 2",                32'h40400000, 32'h3F800000, 1'b1, 32'h40000000, F_NONE);
        check("1 - 2 = -1",               32'h3F800000, 32'h40000000, 1'b1, 32'hBF800000, F_NONE);
        check("1 - 1 = +0 (RNE)",         32'h3F800000, 32'h3F800000, 1'b1, 32'h00000000, F_NONE);
        check("1 - 0.5 = 0.5",            32'h3F800000, 32'h3F000000, 1'b1, 32'h3F000000, F_NONE);

        // ====================================================================
        // 2. Lam tron va ULP (mat tinh chinh xac)
        // ====================================================================
        $display("-- [Group 2] Rounding (round-to-nearest, ties-to-even) --");
        // 1 + 2^-23 = 1.0 + ULP(1) -> 0x3F800001, exact (ULP bit dat duoc)
        check("1 + 2^-23 = next-after-1", 32'h3F800000, 32'h34000000, 1'b0, 32'h3F800001, F_NONE);
        // 1 + 2^-24: tie giua 1.0 va next-after-1; LSB hien tai = 0 -> tie down ve 1.0
        check("1 + 2^-24 = 1 (tie even)", 32'h3F800000, 32'h33800000, 1'b0, 32'h3F800000, F_INEXACT);
        // 1 + 3*2^-25 = 1 + 1.5*2^-24 > tie -> round up
        check("1 + 3*2^-25 -> round up",  32'h3F800000, 32'h33A00000, 1'b0, 32'h3F800001, F_INEXACT);
        // 1 + 2^-149 (smallest subnorm) chi anh huong sticky
        check("1 + 2^-149 (sticky only)", 32'h3F800000, 32'h00000001, 1'b0, 32'h3F800000, F_INEXACT);
        // 1 - (1 - 2^-24): cancellation cho 2^-24
        check("1 - (1-2^-24) = 2^-24",    32'h3F800000, 32'h3F7FFFFF, 1'b1, 32'h33800000, F_NONE);

        // ====================================================================
        // 3. SUBNORMAL - phan bug truoc day! (critical regression tests)
        // ====================================================================
        $display("-- [Group 3] Subnormal arithmetic (FIX trong tam) --");
        // 2^-149 + 2^-149 = 2 * 2^-149 = 0x00000002, van subnormal, exact
        check("smallest_sub + itself",    32'h00000001, 32'h00000001, 1'b0, 32'h00000002, F_NONE);
        // 0x7FFFFF + 0x000001 = 0x800000 = smallest normal
        check("largest_sub + smallest_sub -> smallest_norm",
                                          32'h007FFFFF, 32'h00000001, 1'b0, 32'h00800000, F_NONE);
        // 0x10 + 0x20 = 0x30, van subnormal, exact
        check("subn + subn -> subn (grow)",32'h00000010, 32'h00000020, 1'b0, 32'h00000030, F_NONE);
        // smallest_normal - largest_subnormal = smallest_subnormal (cancel)
        check("smallest_norm - largest_sub = smallest_sub",
                                          32'h00800000, 32'h007FFFFF, 1'b1, 32'h00000001, F_NONE);
        // 0x00800001 - 0x00800000 = 0x00000001 (cancel to subnormal)
        check("0x00800001 - 0x00800000",  32'h00800001, 32'h00800000, 1'b1, 32'h00000001, F_NONE);
        // subnormal - subnormal stays subnormal
        check("subn 0x10 - subn 0x08",    32'h00000010, 32'h00000008, 1'b1, 32'h00000008, F_NONE);
        check("subn 0x03 - subn 0x02",    32'h00000003, 32'h00000002, 1'b1, 32'h00000001, F_NONE);
        // smallest_normal + 0 = smallest_normal
        check("smallest_norm + 0",        32'h00800000, 32'h00000000, 1'b0, 32'h00800000, F_NONE);
        // subn + 0 = subn (no underflow because exact)
        check("subnormal + 0 (exact)",    32'h00000003, 32'h00000000, 1'b0, 32'h00000003, F_NONE);
        // negative subnormals
        check("-subn + -subn",            32'h80000001, 32'h80000001, 1'b0, 32'h80000002, F_NONE);
        check("-smallest_norm + smallest_norm = +0",
                                          32'h80800000, 32'h00800000, 1'b0, 32'h00000000, F_NONE);

        // ====================================================================
        // 4. Zeros (+0/-0) - rules RNE
        // ====================================================================
        $display("-- [Group 4] Zeros (+0 / -0) per RNE --");
        check("+0 + +0 = +0",             32'h00000000, 32'h00000000, 1'b0, 32'h00000000, F_NONE);
        check("+0 + -0 = +0 (RNE)",       32'h00000000, 32'h80000000, 1'b0, 32'h00000000, F_NONE);
        check("-0 + +0 = +0",             32'h80000000, 32'h00000000, 1'b0, 32'h00000000, F_NONE);
        check("-0 + -0 = -0",             32'h80000000, 32'h80000000, 1'b0, 32'h80000000, F_NONE);
        check("+0 - +0 = +0",             32'h00000000, 32'h00000000, 1'b1, 32'h00000000, F_NONE);
        check("-0 - -0 = +0 (RNE)",       32'h80000000, 32'h80000000, 1'b1, 32'h00000000, F_NONE);
        check("-0 - +0 = -0",             32'h80000000, 32'h00000000, 1'b1, 32'h80000000, F_NONE);
        check("+0 - -0 = +0",             32'h00000000, 32'h80000000, 1'b1, 32'h00000000, F_NONE);

        // ====================================================================
        // 5. Overflow & Infinity
        // ====================================================================
        $display("-- [Group 5] Overflow / Infinity --");
        // FLT_MAX + FLT_MAX -> +inf, overflow + inexact
        check("FLT_MAX + FLT_MAX -> +inf",
                                          32'h7F7FFFFF, 32'h7F7FFFFF, 1'b0, 32'h7F800000, F_OVF_INX);
        // FLT_MAX - (-FLT_MAX) -> +inf
        check("FLT_MAX - (-FLT_MAX) -> +inf",
                                          32'h7F7FFFFF, 32'hFF7FFFFF, 1'b1, 32'h7F800000, F_OVF_INX);
        // -FLT_MAX + -FLT_MAX -> -inf
        check("-FLT_MAX + -FLT_MAX -> -inf",
                                          32'hFF7FFFFF, 32'hFF7FFFFF, 1'b0, 32'hFF800000, F_OVF_INX);
        // +inf + finite = +inf (special case, no flag)
        check("+inf + 1 = +inf",          32'h7F800000, 32'h3F800000, 1'b0, 32'h7F800000, F_NONE);
        check("1 + -inf = -inf",          32'h3F800000, 32'hFF800000, 1'b0, 32'hFF800000, F_NONE);
        check("+inf + +inf = +inf",       32'h7F800000, 32'h7F800000, 1'b0, 32'h7F800000, F_NONE);
        check("-inf + -inf = -inf",       32'hFF800000, 32'hFF800000, 1'b0, 32'hFF800000, F_NONE);
        check("1 - +inf = -inf",          32'h3F800000, 32'h7F800000, 1'b1, 32'hFF800000, F_NONE);
        check("+inf - 1 = +inf",          32'h7F800000, 32'h3F800000, 1'b1, 32'h7F800000, F_NONE);

        // ====================================================================
        // 6. NaN propagation va Inf-Inf invalid
        // ====================================================================
        $display("-- [Group 6] NaN propagation / Invalid --");
        // inf + (-inf): invalid -> qNaN
        check("+inf + -inf -> NaN invalid",32'h7F800000, 32'hFF800000, 1'b0, 32'h7FC00000, F_INVALID);
        check("-inf + +inf -> NaN invalid",32'hFF800000, 32'h7F800000, 1'b0, 32'h7FC00000, F_INVALID);
        // inf - inf same sign -> invalid
        check("+inf - +inf -> NaN invalid",32'h7F800000, 32'h7F800000, 1'b1, 32'h7FC00000, F_INVALID);
        check("-inf - -inf -> NaN invalid",32'hFF800000, 32'hFF800000, 1'b1, 32'h7FC00000, F_INVALID);
        // qNaN propagation (no invalid flag)
        check("qNaN + 1 = qNaN",          32'h7FC00000, 32'h3F800000, 1'b0, 32'h7FC00000, F_NONE);
        check("1 + qNaN = qNaN",          32'h3F800000, 32'h7FC00000, 1'b0, 32'h7FC00000, F_NONE);
        // sNaN: signal invalid (kiem tra MSB cua frac = 0)
        check("sNaN + 1 -> qNaN, invalid",32'h7FA00000, 32'h3F800000, 1'b0, 32'h7FC00000, F_INVALID);

        // ====================================================================
        // 7. Mot vai case nguy hiem (smoke test bo sung)
        // ====================================================================
        $display("-- [Group 7] Misc smoke tests --");
        // x + (-x) = +0 voi x = 2^123 (cancel exact)
        check("2^123 + (-2^123) = +0",    32'h7D000000, 32'hFD000000, 1'b0, 32'h00000000, F_NONE);
        // Co the underflow that su (rounding boundary)
        // 0x00800000 + (-0x00400000): 2^-126 - 2^-127 = 2^-127... cho subnormal exact
        // 2^-127 = 0x00400000 (subnormal). Wait: 2^-127 khong bieu dien duoc dang normal.
        // 2^-127 = 0.5 * 2^-126 = subnormal frac = 0x400000 -> 0x00400000.
        check("2^-126 - 2^-127 = 2^-127 (subn)",
                                          32'h00800000, 32'h00400000, 1'b1, 32'h00400000, F_NONE);

        // ====================================================================
        // Tong ket
        // ====================================================================
        $display("============================================================");
        $display("  Passed %0d / %0d   (failed %0d)", passed, total, failed);
        $display("============================================================");
        if (failed != 0) $display("RESULT: FAIL");
        else             $display("RESULT: PASS");
        $finish;
    end

    // Watchdog
    initial begin
        #100000;
        $display("[ERROR] Watchdog timeout!");
        $finish;
    end
endmodule
