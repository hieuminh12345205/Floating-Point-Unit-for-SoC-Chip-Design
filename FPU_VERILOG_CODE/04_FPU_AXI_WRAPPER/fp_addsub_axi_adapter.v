`timescale 1ns / 1ps

// Compatibility adapter between the AXI wrapper and the all-Verilog
// fpu_add_sub core. The arithmetic core is combinational; this module
// registers its result and returns valid_o on the following clock cycle.
module fp_addsub (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        op,
    input  wire        valid_i,
    output reg  [31:0] result,
    output reg         valid_o,
    output reg         exc_nan,
    output reg         exc_inf,
    output reg         exc_zero
);
    wire [31:0] core_result;
    wire [4:0]  core_flags;

    fpu_add_sub core (
        .a      (a),
        .b      (b),
        .op_sub (op),
        .result (core_result),
        .flags  (core_flags)
    );

    wire core_nan  = (&core_result[30:23]) && (|core_result[22:0]);
    wire core_inf  = (&core_result[30:23]) && !(|core_result[22:0]);
    wire core_zero = !(|core_result[30:0]);

    always @(posedge clk) begin
        if (rst) begin
            result   <= 32'd0;
            valid_o  <= 1'b0;
            exc_nan  <= 1'b0;
            exc_inf  <= 1'b0;
            exc_zero <= 1'b1;
        end else begin
            valid_o <= valid_i;
            if (valid_i) begin
                result   <= core_result;
                exc_nan  <= core_nan;
                exc_inf  <= core_inf;
                exc_zero <= core_zero;
            end
        end
    end

    // Keep the full IEEE-754 flag bus connected for synthesis diagnostics.
    wire unused_core_flags = ^core_flags;

endmodule
