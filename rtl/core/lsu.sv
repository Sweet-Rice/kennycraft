// Load/store lane logic. Combinational; the core drives the bus.
//
// Store side: byte enables and data replicated across the word (SB repeats
// the byte four times, SH the halfword twice), so a byte-wide slave or an MMIO
// register can take wdata[7:0] for any byte address.
// Load side: picks and extends the addressed byte or halfword from the word
// the bus returned. misaligned follows Tai_2 section 1 (LW/SW 4-aligned,
// LH/LHU/SH 2-aligned) and halts the core with ERR.ILLEGAL.
module lsu
    import kc_isa_pkg::*;
(
    // Store / address phase
    input  logic [2:0]  funct3,
    input  logic [1:0]  addr_lo,
    input  logic [31:0] rs2,
    output logic [3:0]  be,
    output logic [31:0] wdata,
    output logic        misaligned,

    // Load phase (funct3 and address bits of the access in flight)
    input  logic [2:0]  ld_funct3,
    input  logic [1:0]  ld_addr_lo,
    input  logic [31:0] rdata,
    output logic [31:0] ld_value
);

    assign misaligned = is_misaligned(funct3, addr_lo);

    always_comb begin
        unique case (funct3[1:0])
            2'b00: begin
                be    = 4'b0001 << addr_lo;
                wdata = {4{rs2[7:0]}};
            end
            2'b01: begin
                be    = addr_lo[1] ? 4'b1100 : 4'b0011;
                wdata = {2{rs2[15:0]}};
            end
            default: begin
                be    = 4'b1111;
                wdata = rs2;
            end
        endcase
    end

    logic [7:0]  byte_v;
    logic [15:0] half_v;

    assign byte_v = rdata[ld_addr_lo*8 +: 8];
    assign half_v = ld_addr_lo[1] ? rdata[31:16] : rdata[15:0];

    always_comb begin
        unique case (ld_funct3)
            F3_LB:   ld_value = {{24{byte_v[7]}}, byte_v};
            F3_LBU:  ld_value = {24'b0, byte_v};
            F3_LH:   ld_value = {{16{half_v[15]}}, half_v};
            F3_LHU:  ld_value = {16'b0, half_v};
            default: ld_value = rdata;   // LW
        endcase
    end

endmodule
