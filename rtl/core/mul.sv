// Zmmul multiplier: MUL, MULH, MULHSU, MULHU (funct3 000..011).
//
// One 33 x 33 signed multiply covers all four: each operand is sign- or
// zero-extended by one bit per its signedness. The product is registered
// (Vivado maps it onto DSP48E1 slices with the output register), so the
// result is valid the cycle after en, which is the core's second EXECUTE
// cycle.
module mul (
    input  logic        clk,
    input  logic        en,
    input  logic [1:0]  op,       // funct3[1:0]
    input  logic [31:0] a,        // rs1
    input  logic [31:0] b,        // rs2
    output logic [31:0] result
);

    logic               a_signed, b_signed;
    logic signed [32:0] a_x, b_x;
    logic signed [65:0] p;
    logic               hi_q;

    assign a_signed = (op != 2'b11);   // MUL, MULH, MULHSU
    assign b_signed = (op[1] == 1'b0); // MUL, MULH
    assign a_x = {a_signed & a[31], a};
    assign b_x = {b_signed & b[31], b};

    always_ff @(posedge clk) begin
        if (en) begin
            p    <= a_x * b_x;
            hi_q <= (op != 2'b00);
        end
    end

    // p[65:64] only repeat the sign of the 64-bit product.
    /* verilator lint_off UNUSEDSIGNAL */
    logic [65:0] p_u;
    /* verilator lint_on UNUSEDSIGNAL */
    assign p_u    = p;
    assign result = hi_q ? p_u[63:32] : p_u[31:0];

endmodule
