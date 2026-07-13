

`timescale 1ns/1ps

module fmul_tb;

reg  [31:0] a, b;
wire [31:0] result;
wire [4:0]  flags;

fmul uut (.a(a), .b(b), .result(result), .flags(flags));

task check;
    input [31:0] exp;
    input [63:0] name;
    begin
        #10;
        if (result === exp)
            $display("PASS [%0s] result=0x%h", name, result);
        else
            $display("FAIL [%0s] got=0x%h exp=0x%h",
                      name, result, exp);
    end
endtask

initial begin
    $display("=== FMUL TESTBENCH ===");

    // 2.0 × 3.0 = 6.0
    a=32'h40000000; b=32'h40400000;
    check(32'h40C00000, "2x3");

    // 1.5 × 2.5 = 3.75
    a=32'h3FC00000; b=32'h40200000;
    check(32'h40700000, "1.5x2.5");

    // -2.0 × 3.0 = -6.0
    a=32'hC0000000; b=32'h40400000;
    check(32'hC0C00000, "-2x3");

    // 0.0 × 5.0 = 0.0
    a=32'h00000000; b=32'h40A00000;
    check(32'h00000000, "0x5");

    // Inf × 2.0 = Inf
    a=32'h7F800000; b=32'h40000000;
    check(32'h7F800000, "Infx2");

    // Inf × 0 = NaN
    a=32'h7F800000; b=32'h00000000;
    check(32'h7FC00000, "Infx0");

    // -1.0 × -1.0 = 1.0
    a=32'hBF800000; b=32'hBF800000;
    check(32'h3F800000, "-1x-1");

    $display("=== XONG ===");
    $finish;
end

endmodule