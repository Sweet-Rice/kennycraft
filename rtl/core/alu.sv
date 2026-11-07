// RV32I ALU. op = {sub/sra, funct3}, as decoded by inst_decoder.
// SLL reuses the right shifter on the bit-reversed operand.
module alu #(
    parameter int W = 32
) (
    input  logic [W-1:0] a,
    input  logic [W-1:0] b,
    input  logic [3:0]   op,
    output logic [W-1:0] result
);

    logic [W-1:0] sh_in, sh_out, rev_a, rev_out, sum;
    logic         lt, ltu;

    for (genvar i = 0; i < W; i++) begin : g_rev
        assign rev_a[i]   = a[W-1-i];
        assign rev_out[i] = sh_out[W-1-i];
    end

    assign sh_in = (op[2:0] == 3'b001) ? rev_a : a;   // SLL : SRL/SRA

    barrel_shifter #(.W(W)) u_sh (
        .a(sh_in), .b(b[$clog2(W)-1:0]), .sel(op[3] & a[W-1]), .result(sh_out)
    );

    // SUB, and SLT/SLTU (op[1]) subtract.
    addsub #(.W(W)) u_addsub (
        .a(a), .b(b), .sub(op[3] | op[1]), .sum(sum), .lt(lt), .ltu(ltu)
    );

    always_comb begin
        unique case (op[2:0])
            3'b000: result = sum;                    // ADD, SUB
            3'b001: result = rev_out;                // SLL
            3'b010: result = {{(W-1){1'b0}}, lt};    // SLT
            3'b011: result = {{(W-1){1'b0}}, ltu};   // SLTU
            3'b100: result = a ^ b;                  // XOR
            3'b101: result = sh_out;                 // SRL, SRA
            3'b110: result = a | b;                  // OR
            3'b111: result = a & b;                  // AND
        endcase
    end

endmodule
