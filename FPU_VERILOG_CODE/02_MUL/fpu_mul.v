// khai báo A và B
module fmul (
	input wire [31:0] a, 
	input wire [31:0] b, 
	output wire [31:0] result,
	output wire [4:0]  flags 
);

// thay cho pkg
localparam BIAS         = 127;
localparam POS_ZERO     = 32'h0000_0000;
localparam NEG_ZERO     = 32'h8000_0000;
localparam POS_INF      = 32'h7f80_0000;
localparam NEG_INF      = 32'hff80_0000;
localparam QNAN         = 32'h7fc0_0000;

// Các tphan của A và B
wire        sign_a  = a[31];
wire        sign_b  = b[31];
wire [7:0]  exp_a   = a[30:23];
wire [7:0]  exp_b   = b[30:23];
wire [22:0] frac_a  = a[22:0];
wire [22:0] frac_b  = b[22:0];
// ── Phân loại số ───────────────────────────────────────────
wire a_zero      = (exp_a == 8'h00) && (frac_a == 23'h0);
wire b_zero      = (exp_b == 8'h00) && (frac_b == 23'h0);
wire a_inf       = (exp_a == 8'hff) && (frac_a == 23'h0);
wire b_inf       = (exp_b == 8'hff) && (frac_b == 23'h0);
wire a_nan       = (exp_a == 8'hff) && (frac_a != 23'h0);
wire b_nan       = (exp_b == 8'hff) && (frac_b != 23'h0);


wire sign_res = sign_a ^ sign_b;

wire [23:0] mant_a = {1'b1, frac_a};
wire [23:0] mant_b = {1'b1, frac_b};

// Chưa trừ bias vì dùng exp raw, trừ sau
wire [9:0] exp_sum = {2'b00, exp_a} + {2'b00, exp_b}
                     - 10'd127;
//   exp_a, exp_b đang là dạng biased (đã +127)
//   exp_a + exp_b = (Ea+127) + (Eb+127) = Ea+Eb+254
//   Muốn kết quả = Ea+Eb+127 → trừ 127

//  Nhân mantissa 24×24 = 48 bit 
wire [47:0] product = mant_a * mant_b;

// product[47]=1 → dạng 1x.xxx → shift phải 1, exp+1
// product[47]=0 → dạng 01.xxx → giữ nguyên
wire        norm_bit  = product[47];
wire [9:0]  exp_norm  = norm_bit ? exp_sum + 10'd1
                                 : exp_sum;
wire [22:0] frac_norm = norm_bit ? product[46:24]
                                 : product[45:23];
// Lấy 23 bit làm fraction (bỏ hidden bit)

// Lấy guard bit để làm tròn
wire guard_bit = norm_bit ? product[23] : product[22];
// Cộng thêm 1 nếu guard=1 (round to nearest)
wire [22:0] frac_rounded = frac_norm + guard_bit;

wire overflow  = (exp_norm[9] == 0) && (exp_norm >= 10'd255);
wire underflow = exp_norm[9];
// exp_norm[9]=1 nghĩa là số âm → underflow

wire [31:0] normal_result =
    overflow  ? {sign_res, 8'hFF, 23'h000000}
  : underflow ? {sign_res, 31'h0}
  : {sign_res, exp_norm[7:0], frac_rounded};

reg        use_special;
reg [31:0] special_result;
reg [4:0]  special_flags;

always @* begin
    use_special    = 1'b0;
    special_result = POS_ZERO;
    special_flags  = 5'b00000;

    if (a_nan || b_nan) begin
        // NaN × bất kỳ = NaN
        use_special    = 1'b1;
        special_result = QNAN;
        special_flags[4] = 1'b1; // Invalid

    end else if ((a_inf && b_zero)||(b_inf && a_zero)) begin
        // Inf × 0 = NaN (không xác định)
        use_special    = 1'b1;
        special_result = QNAN;
        special_flags[4] = 1'b1; // Invalid

    end else if (a_inf || b_inf) begin
        // Inf × x = Inf
        use_special    = 1'b1;
        special_result = {sign_res, 8'hFF, 23'h000000};

    end else if (a_zero || b_zero) begin
        // 0 × x = 0
        use_special    = 1'b1;
        special_result = {sign_res, 31'h0};
    end
end

// Output 
assign result = use_special ? special_result : normal_result;
assign flags  = use_special ? special_flags
              : {1'b0,            // Invalid
                 1'b0,            // DivZero
                 overflow,        // Overflow
                 underflow,       // Underflow
                 guard_bit};      // Inexact (đơn giản)

endmodule

