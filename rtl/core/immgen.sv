// Immediate generator. imm_sig: 000 U, 100 I, 101 S, 110 B, 111 J.
module immgen (
    input  logic [31:7] inst,
    input  logic [2:0]  imm_sig,
    output logic [31:0] imm
);

    always_comb begin
        unique case (imm_sig)
            3'b100:  imm = {{21{inst[31]}}, inst[30:20]};
            3'b101:  imm = {{21{inst[31]}}, inst[30:25], inst[11:7]};
            3'b110:  imm = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
            3'b111:  imm = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
            default: imm = {inst[31:12], 12'b0};
        endcase
    end

endmodule
