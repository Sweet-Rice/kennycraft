// KennyCraft core, Stage 0: multi-cycle RV32I + Zmmul, LANES = 1 (D7).
//
// Grown from Tai's multicycle core (datapath.sv in RISC-V-Core-progression).
// No pipeline registers, no forwarding, no hazard logic. One FSM walks every
// instruction through the states of the Tai page, CPU Core, State machine:
//
//   IF    send PC to the instruction BRAM                          1 cycle
//   ID    instruction arrives, decode, read registers              1
//   EX    ALU, branch compare, address generation, multiply        1
//   MUL   second EXECUTE cycle for MUL family (registered product) 1
//   MEM   one bus access; stores retire here                       1 + slave wait
//   WB    write rd (load data arrives here), update PC             1
//
// Errors (Tai_2 sections 1 and 2). An illegal instruction (caught in ID), a
// fetch outside instruction memory (ID) or a misaligned load/store (EX, before
// any bus access) pulses err_set[ERR_ILLEGAL] with err_pc = the instruction's
// PC and parks the FSM in HALT until reset: nothing is fetched or written.
//
// Buses. imem_rdata is the instruction BRAM output for imem_addr one cycle
// earlier. On the data bus, bus_req is held until bus_ready; the access
// happens once in the bus_req && bus_ready cycle and load data is valid in
// bus_rdata the cycle after.
module core
    import kc_isa_pkg::*;
#(
    parameter int          LANES     = 1,
    parameter logic [31:0] RESET_VEC = IMEM_BASE
) (
    input  logic                 clk,
    input  logic                 rst,

    output logic [31:0]          imem_addr,
    input  logic [31:0]          imem_rdata,

    output logic                 bus_req,
    output logic                 bus_we,
    output logic [31:0]          bus_addr,
    output logic [3:0]           bus_be,
    output logic [31:0]          bus_wdata,
    input  logic                 bus_ready,
    input  logic [31:0]          bus_rdata,

    output logic [ERR_WIDTH-1:0] err_set,
    output logic [31:0]          err_pc,
    output logic                 halted,
    output logic [31:0]          pc
);

    if (LANES != 1) begin : g_lanes_check
        $error("core: Stage 0 implements LANES = 1 only");
    end

    typedef enum logic [2:0] {
        S_IF, S_ID, S_EX, S_MUL, S_MEM, S_WB, S_HALT
    } state_t;

    state_t state;

    // ------------------------------------------------------------------
    // ID: decode the BRAM output, read registers
    // ------------------------------------------------------------------
    logic [3:0]  d_alu_ctrl;
    logic        d_alu_a_pc, d_r_we, d_res_imm, d_is_load, d_is_store, d_is_mul;
    logic        d_is_branch, d_is_jal, d_is_jalr, d_illegal;
    logic [1:0]  d_alu_b_sel;
    logic [2:0]  d_imm_sig;
    logic [31:0] d_imm, rs1_raw, rs2_raw;
    logic        id_fault;

    inst_decoder u_dec (
        .inst(imem_rdata), .alu_ctrl(d_alu_ctrl), .alu_a_pc(d_alu_a_pc),
        .alu_b_sel(d_alu_b_sel), .imm_sig(d_imm_sig), .r_we(d_r_we),
        .res_imm(d_res_imm), .is_load(d_is_load), .is_store(d_is_store),
        .is_mul(d_is_mul), .is_branch(d_is_branch), .is_jal(d_is_jal),
        .is_jalr(d_is_jalr), .illegal(d_illegal)
    );

    immgen u_imm (.inst(imem_rdata[31:7]), .imm_sig(d_imm_sig), .imm(d_imm));

    logic        rf_we;
    logic [4:0]  ex_rd;
    logic [31:0] rf_wdata;

    reg_module #(.W(32), .D(32)) u_rf (
        .clk, .we(rf_we), .wr(ex_rd),
        .rd1(instr_rs1(imem_rdata)), .rd2(instr_rs2(imem_rdata)),
        .d_in(rf_wdata), .d_out1(rs1_raw), .d_out2(rs2_raw)
    );

    assign id_fault = d_illegal || is_fetch_outside_imem(pc);

    // ID -> EX registers
    logic [3:0]  ex_alu_ctrl;
    logic        ex_alu_a_pc, ex_r_we, ex_res_imm, ex_is_load, ex_is_store, ex_is_mul;
    logic        ex_is_branch, ex_is_jal, ex_is_jalr;
    logic [1:0]  ex_alu_b_sel;
    logic [2:0]  ex_funct3;
    logic [31:0] ex_imm, ex_rs1, ex_rs2;
    logic [31:0] ir;          // instruction in flight, for the retire wires

    always_ff @(posedge clk) begin
        if (state == S_ID) begin
            ir           <= imem_rdata;
            ex_alu_ctrl  <= d_alu_ctrl;
            ex_alu_a_pc  <= d_alu_a_pc;
            ex_alu_b_sel <= d_alu_b_sel;
            ex_r_we      <= d_r_we && (instr_rd(imem_rdata) != 5'd0);
            ex_res_imm   <= d_res_imm;
            ex_is_load   <= d_is_load;
            ex_is_store  <= d_is_store;
            ex_is_mul    <= d_is_mul;
            ex_is_branch <= d_is_branch;
            ex_is_jal    <= d_is_jal;
            ex_is_jalr   <= d_is_jalr;
            ex_funct3    <= instr_funct3(imem_rdata);
            ex_rd        <= instr_rd(imem_rdata);
            ex_imm       <= d_imm;
            ex_rs1       <= (instr_rs1(imem_rdata) == 5'd0) ? 32'd0 : rs1_raw;
            ex_rs2       <= (instr_rs2(imem_rdata) == 5'd0) ? 32'd0 : rs2_raw;
        end
    end

    // ------------------------------------------------------------------
    // EX: ALU, branch, address, store lanes, multiply
    // ------------------------------------------------------------------
    logic [31:0] alu_a, alu_b, alu_y, target, mul_y;
    logic        cmp, take;
    logic [3:0]  st_be;
    logic [31:0] st_wdata, ld_value;
    logic        misaligned;

    assign alu_a = ex_alu_a_pc ? pc : ex_rs1;
    always_comb begin
        unique case (ex_alu_b_sel)
            2'b00:   alu_b = ex_rs2;
            2'b10:   alu_b = 32'd4;
            default: alu_b = ex_imm;
        endcase
    end

    alu #(.W(32)) u_alu (.a(alu_a), .b(alu_b), .op(ex_alu_ctrl), .result(alu_y));

    // BEQ/BNE compare the XOR against 0, BLT/BGE/BLTU/BGEU take the SLT bit;
    // funct3[0] inverts.
    assign cmp    = ex_funct3[2] ? alu_y[0] : (alu_y == 32'd0);
    assign take   = ex_is_jal || ex_is_jalr || (ex_is_branch && (cmp ^ ex_funct3[0]));
    assign target = ex_is_jalr ? ((ex_rs1 + ex_imm) & ~32'd1) : (pc + ex_imm);

    mul u_mul (
        .clk, .en(state == S_EX), .op(ex_funct3[1:0]),
        .a(ex_rs1), .b(ex_rs2), .result(mul_y)
    );

    // EX -> MEM/WB registers
    logic [31:0] res;        // rd value (ALU, LUI immediate, link, product) or bus address
    logic [31:0] next_pc;
    logic [2:0]  ld_funct3;
    logic [1:0]  ld_addr_lo;

    lsu u_lsu (
        .funct3(ex_funct3), .addr_lo(alu_y[1:0]), .rs2(ex_rs2),
        .be(st_be), .wdata(st_wdata), .misaligned(misaligned),
        .ld_funct3(ld_funct3), .ld_addr_lo(ld_addr_lo), .rdata(bus_rdata),
        .ld_value(ld_value)
    );

    always_ff @(posedge clk) begin
        if (state == S_EX) begin
            res        <= ex_res_imm ? ex_imm : alu_y;
            next_pc    <= take ? target : pc + 32'd4;
            bus_be     <= st_be;
            bus_wdata  <= st_wdata;
            ld_funct3  <= ex_funct3;
            ld_addr_lo <= alu_y[1:0];
        end else if (state == S_MUL) begin
            res <= mul_y;
        end
    end

    assign bus_req  = (state == S_MEM);
    assign bus_we   = ex_is_store;
    assign bus_addr = res;

    // ------------------------------------------------------------------
    // WB
    // ------------------------------------------------------------------
    assign rf_we    = (state == S_WB) && ex_r_we;
    assign rf_wdata = ex_is_load ? ld_value : res;

    // ------------------------------------------------------------------
    // FSM, PC and errors
    // ------------------------------------------------------------------
    logic ex_fault;
    assign ex_fault = (ex_is_load || ex_is_store) && misaligned;

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= S_IF;
            pc    <= RESET_VEC;
        end else begin
            unique case (state)
                S_IF:  state <= S_ID;
                S_ID:  state <= id_fault ? S_HALT : S_EX;
                S_EX: begin
                    if (ex_fault)                        state <= S_HALT;
                    else if (ex_is_mul)                  state <= S_MUL;
                    else if (ex_is_load || ex_is_store)  state <= S_MEM;
                    else                                 state <= S_WB;
                end
                S_MUL: state <= S_WB;
                S_MEM: begin
                    if (bus_ready) begin
                        if (ex_is_store) begin
                            state <= S_IF;
                            pc    <= next_pc;
                        end else begin
                            state <= S_WB;
                        end
                    end
                end
                S_WB: begin
                    state <= S_IF;
                    pc    <= next_pc;
                end
                default: state <= S_HALT;
            endcase
        end
    end

    assign imem_addr = pc;
    assign halted    = (state == S_HALT);
    assign err_pc    = pc;

    always_comb begin
        err_set = '0;
        err_set[ERR_ILLEGAL] = ((state == S_ID) && id_fault) || ((state == S_EX) && ex_fault);
    end

    // ------------------------------------------------------------------
    // Retire observation wires for Verilator harnesses and traces (not used
    // by any logic). One retire per instruction: stores in the cycle the bus
    // accepts them, everything else in WB. A halting instruction never
    // retires. retire_mask is the active mask, all ones until Stage 1.
    // ------------------------------------------------------------------
    /* verilator lint_off UNUSEDSIGNAL */
    logic             retire_valid;
    logic [31:0]      retire_pc;
    logic [31:0]      retire_inst;
    logic             retire_rd_we;
    logic [4:0]       retire_rd_addr;
    logic [31:0]      retire_rd_wdata;
    logic [LANES-1:0] retire_mask;
    /* verilator lint_on UNUSEDSIGNAL */

    assign retire_valid    = (state == S_WB) || ((state == S_MEM) && bus_ready && ex_is_store);
    assign retire_pc       = pc;
    assign retire_inst     = ir;
    assign retire_rd_we    = rf_we;
    assign retire_rd_addr  = ex_rd;
    assign retire_rd_wdata = rf_wdata;
    assign retire_mask     = '1;

endmodule
