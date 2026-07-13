`timescale 1ns/1ps

// AXI4-Lite wrapper for the single-precision FDIV core.
//
// Register map:
//   0x00 CTRL   bit 0 start, write 1 to launch a divide when busy == 0
//   0x04 STATUS bit 0 done, bit 1 busy, bits [6:2] flags
//   0x08 OP_A   operand A, raw IEEE 754 single-precision bits
//   0x0C OP_B   operand B, raw IEEE 754 single-precision bits
//   0x10 RESULT result, raw IEEE 754 single-precision bits
//   0x14 FLAGS  exception flags
module fdiv_axi_lite (
    input  wire        s_axi_aclk,
    input  wire        s_axi_aresetn,

    input  wire [5:0]  s_axi_awaddr,
    input  wire [2:0]  s_axi_awprot,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,

    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,

    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,

    input  wire [5:0]  s_axi_araddr,
    input  wire [2:0]  s_axi_arprot,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,

    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready
);

localparam [5:0]
    ADDR_CTRL   = 6'h00,
    ADDR_STATUS = 6'h04,
    ADDR_OP_A   = 6'h08,
    ADDR_OP_B   = 6'h0c,
    ADDR_RESULT = 6'h10,
    ADDR_FLAGS  = 6'h14;

reg [31:0] operand_a_reg;
reg [31:0] operand_b_reg;
reg [31:0] result_reg;
reg [4:0]  flags_reg;
reg        start_pulse;
reg        done_reg;
reg        busy_reg;

wire [31:0] core_result;
wire        core_done;
wire [4:0]  core_flags;
wire        unused_overflow;
wire        unused_underflow;
wire        unused_div_by_zero;
wire        unused_invalid_op;

wire write_fire = s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid;
wire read_fire  = s_axi_arvalid && !s_axi_rvalid;

wire unused_prot = |{s_axi_awprot, s_axi_arprot};

fdiv_top core (
    .clk(s_axi_aclk),
    .rst_n(s_axi_aresetn),
    .start(start_pulse),
    .operand_a(operand_a_reg),
    .operand_b(operand_b_reg),
    .result(core_result),
    .done(core_done),
    .overflow(unused_overflow),
    .underflow(unused_underflow),
    .div_by_zero(unused_div_by_zero),
    .invalid_op(unused_invalid_op),
    .flags(core_flags)
);

function [31:0] apply_wstrb;
    input [31:0] old_value;
    input [31:0] new_value;
    input [3:0]  strobe;
    integer i;
    begin
        apply_wstrb = old_value;
        for (i = 0; i < 4; i = i + 1) begin
            if (strobe[i]) begin
                apply_wstrb[i*8 +: 8] = new_value[i*8 +: 8];
            end
        end
    end
endfunction

function [31:0] read_mux;
    input [5:0] addr;
    begin
        case (addr)
            ADDR_CTRL:   read_mux = 32'h0000_0000;
            ADDR_STATUS: read_mux = {25'h0, flags_reg, busy_reg, done_reg};
            ADDR_OP_A:   read_mux = operand_a_reg;
            ADDR_OP_B:   read_mux = operand_b_reg;
            ADDR_RESULT: read_mux = result_reg;
            ADDR_FLAGS:  read_mux = {27'h0, flags_reg};
            default:     read_mux = 32'h0000_0000;
        endcase
    end
endfunction

always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
        operand_a_reg <= 32'h0000_0000;
        operand_b_reg <= 32'h0000_0000;
        result_reg    <= 32'h0000_0000;
        flags_reg     <= 5'b00000;
        start_pulse   <= 1'b0;
        done_reg      <= 1'b0;
        busy_reg      <= 1'b0;

        s_axi_awready <= 1'b0;
        s_axi_wready  <= 1'b0;
        s_axi_bresp   <= 2'b00;
        s_axi_bvalid  <= 1'b0;
        s_axi_arready <= 1'b0;
        s_axi_rdata   <= 32'h0000_0000;
        s_axi_rresp   <= 2'b00;
        s_axi_rvalid  <= 1'b0;
    end else begin
        start_pulse   <= 1'b0;
        s_axi_awready <= 1'b0;
        s_axi_wready  <= 1'b0;
        s_axi_arready <= 1'b0;

        if (write_fire) begin
            s_axi_awready <= 1'b1;
            s_axi_wready  <= 1'b1;
            s_axi_bresp   <= 2'b00;
            s_axi_bvalid  <= 1'b1;

            case (s_axi_awaddr)
                ADDR_CTRL: begin
                    if (s_axi_wstrb[0] && s_axi_wdata[0] && !busy_reg) begin
                        start_pulse <= 1'b1;
                        done_reg    <= 1'b0;
                        busy_reg    <= 1'b1;
                    end
                end

                ADDR_OP_A: operand_a_reg <= apply_wstrb(operand_a_reg, s_axi_wdata, s_axi_wstrb);
                ADDR_OP_B: operand_b_reg <= apply_wstrb(operand_b_reg, s_axi_wdata, s_axi_wstrb);
                default: begin
                end
            endcase
        end else if (s_axi_bvalid && s_axi_bready) begin
            s_axi_bvalid <= 1'b0;
        end

        if (read_fire) begin
            s_axi_arready <= 1'b1;
            s_axi_rdata   <= read_mux(s_axi_araddr);
            s_axi_rresp   <= 2'b00;
            s_axi_rvalid  <= 1'b1;
        end else if (s_axi_rvalid && s_axi_rready) begin
            s_axi_rvalid <= 1'b0;
        end

        if (core_done) begin
            result_reg <= core_result;
            flags_reg  <= core_flags;
            done_reg   <= 1'b1;
            busy_reg   <= 1'b0;
        end
    end
end

endmodule
