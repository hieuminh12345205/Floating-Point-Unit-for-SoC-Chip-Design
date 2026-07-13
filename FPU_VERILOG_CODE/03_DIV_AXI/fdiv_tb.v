`timescale 1ns/1ps

module fdiv_tb;

reg         clk;
reg         rst_n;
reg         start;
reg  [31:0] operand_a;
reg  [31:0] operand_b;
wire [31:0] result;
wire        done;
wire        overflow;
wire        underflow;
wire        div_by_zero;
wire        invalid_op;
wire [4:0]  flags;

integer pass_count;
integer fail_count;

fdiv_top dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .operand_a(operand_a),
    .operand_b(operand_b),
    .result(result),
    .done(done),
    .overflow(overflow),
    .underflow(underflow),
    .div_by_zero(div_by_zero),
    .invalid_op(invalid_op),
    .flags(flags)
);

always #5 clk = ~clk;

task run_check;
    input [31:0] a;
    input [31:0] b;
    input [31:0] expected_result;
    input [4:0]  expected_flags;
    input [8*32-1:0] name;
    integer wait_cycles;
    begin
        @(posedge clk);
        operand_a <= a;
        operand_b <= b;
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        wait_cycles = 0;
        while ((done !== 1'b1) && (wait_cycles < 200)) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end

        if (done !== 1'b1) begin
            fail_count = fail_count + 1;
            $display("TIMEOUT [%0s] done did not assert", name);
        end else begin
            #1;

            if ((result === expected_result) && (flags === expected_flags)) begin
                pass_count = pass_count + 1;
                $display("PASS [%0s] result=0x%08h flags=%b", name, result, flags);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL [%0s]", name);
                $display("  got      result=0x%08h flags=%b", result, flags);
                $display("  expected result=0x%08h flags=%b", expected_result, expected_flags);
            end
        end
    end
endtask

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    start = 1'b0;
    operand_a = 32'd0;
    operand_b = 32'd0;
    pass_count = 0;
    fail_count = 0;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    run_check(32'h3F800000, 32'h40000000, 32'h3F000000, 5'b00000, "1.0/2.0");
    run_check(32'h41200000, 32'h40800000, 32'h40200000, 5'b00000, "10.0/4.0");
    run_check(32'h40E00000, 32'h40000000, 32'h40600000, 5'b00000, "7.0/2.0");
    run_check(32'hC0C00000, 32'h40400000, 32'hC0000000, 5'b00000, "-6.0/3.0");
    run_check(32'h40C00000, 32'hC0400000, 32'hC0000000, 5'b00000, "6.0/-3.0");
    run_check(32'hC0000000, 32'hC0800000, 32'h3F000000, 5'b00000, "-2.0/-4.0");

    run_check(32'h3F800000, 32'h40400000, 32'h3EAAAAAB, 5'b00001, "1.0/3.0");

    run_check(32'h00000000, 32'h40A00000, 32'h00000000, 5'b00000, "0.0/5.0");
    run_check(32'h80000000, 32'h40000000, 32'h80000000, 5'b00000, "-0.0/2.0");
    run_check(32'h40A00000, 32'h00000000, 32'h7F800000, 5'b01000, "5.0/0.0");
    run_check(32'h40A00000, 32'h80000000, 32'hFF800000, 5'b01000, "5.0/-0.0");
    run_check(32'h00000000, 32'h00000000, 32'h7FC00000, 5'b10000, "0.0/0.0");

    run_check(32'h7F800000, 32'h40000000, 32'h7F800000, 5'b00000, "inf/2.0");
    run_check(32'hFF800000, 32'hC0000000, 32'h7F800000, 5'b00000, "-inf/-2.0");
    run_check(32'h7F800000, 32'h7F800000, 32'h7FC00000, 5'b10000, "inf/inf");
    run_check(32'h40400000, 32'h7F800000, 32'h00000000, 5'b00000, "3.0/inf");
    run_check(32'h7FC00000, 32'h3F800000, 32'h7FC00000, 5'b10000, "nan/1.0");
    run_check(32'h3F800000, 32'h7FC00000, 32'h7FC00000, 5'b10000, "1.0/nan");

    run_check(32'h7F7FFFFF, 32'h00800000, 32'h7F800000, 5'b00101, "max/min_normal");
    run_check(32'h00800000, 32'h7F7FFFFF, 32'h00000000, 5'b00011, "min_normal/max");

    $display("===========================================");
    $display("FDIV SUMMARY: PASS=%0d FAIL=%0d", pass_count, fail_count);
    $display("===========================================");

    if (fail_count != 0) begin
        $display("TEST FAILED");
        $finish;
    end
    $finish;
end

endmodule
