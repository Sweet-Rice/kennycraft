`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01.09.2026 22:57:20
// Design Name: 
// Module Name: datapath
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

//laying groundwork for pipelining. for now, just naiive multistage
module datapath #(parameter  RESET_VEC = 32'h8000_0000, W =32, D = 64, DEEP = 4096, R =32 ) (
    input logic clk, rst,
    output logic tx, illegal_out,
    output logic [W-1:0 ]if_pc
    );
    
    
    
    logic if_stall, mem_stall; 
    logic if_mem_valid;
    logic mem_mem_valid;
    logic if_mem_ready;
    logic mem_mem_ready;
    
    
    ////////////////////////////////
    //FSM
    // we nuke this when we pipeline
    
    
    
    
    typedef enum logic [2:0] {
        ST_IF = 3'b000,
        ST_ID = 3'b001,
        ST_EX= 3'b010,
        ST_MEM = 3'b011,
        ST_WB = 3'b100
    } stage_t;
    
    stage_t current_state, next_state;
    
    logic if_en, id_en, ex_en, mem_en, wb_en; //enable signals
    
    assign if_mem_valid = if_en;
    
    
    assign if_stall = if_en && ~if_mem_ready; 
    
    
    always_ff @(posedge clk) begin
        if (rst) begin
            current_state <= ST_IF;
        end else begin
            current_state <= next_state;
        end
    end
    
    always_comb begin
        if_en = 1'b0;
        id_en = 1'b0;
        ex_en = 1'b0;
        mem_en = 1'b0;
        wb_en = 1'b0;
        
        next_state = ST_IF;
        case (current_state) 
            ST_IF: begin 
                if (~if_stall)next_state = ST_ID;
                else next_state = ST_IF;
                if_en = 1'b1;
            end
            ST_ID: begin
                next_state = ST_EX;
                id_en = 1'b1;
            end
            ST_EX: begin
                ex_en = 1'b1;
                next_state = ST_MEM;
            end
            ST_MEM: begin
                mem_en = 1'b1;
                if (~mem_stall)next_state = ST_WB;
                else next_state = ST_MEM;
                
            end
            ST_WB: begin
                wb_en = 1'b1;
                next_state = ST_IF;
            end       
        endcase
    end
    
    
    ////////////////////////////////////
    
    
    
    //////////////////////////////////
    // IF/ID register
    //logic if_fetch_sig;
    
    logic [W-1:0] id_inst, if_inst;
    
    logic [W-1:0] /*if_pc,*/ id_pc;
    logic [W-1:0] if_pc_alt;
    logic if_pc_sig;
    
    always_ff @(posedge clk) begin
    
        if (rst) begin // begin fsm
            if_pc <= RESET_VEC;
            id_pc <= RESET_VEC;
            
        end else if (~if_stall && if_en)begin
                id_inst <= if_inst;
                id_pc <= if_pc;
                
            end else if (wb_en) begin
                if_pc <= (~if_pc_sig) ? if_pc + 32'd4 : if_pc_alt;
            end
            
    end
    
    fetch #(.W(W), .D(DEEP), .INIT_FILE("program.mem")) if_fetch (.fetch_sig(if_mem_valid),
                                        .addr(if_pc),
                                        .rst(rst), .clk(clk),
                                        .d_out(if_inst),
                                        .mem_ready(if_mem_ready));
                                        
                                         
                                         
    //id_pc, id_inst are passed 
    //////////////////////////////////////
    
    /////////////////////////////////////
    //ID register
    
    logic [W-1:0] wb_rd_in; 
    
    logic [W-1:0]ex_pc, rs1_val, rs2_val, ex_rs1_val, mem_rs2_val, ex_rs2_val, ex_imm, imm, mem_imm, wb_imm /*id_pc*/ ;
    logic [$clog2(D) -1:0] rd_addr, ex_rd_addr, mem_rd_addr, wb_rd_addr, rs1_addr, ex_rs1_addr, rs2_addr, ex_rs2_addr;
    
    assign rs1_addr = id_inst[19:15];
    assign rs2_addr = id_inst[24:20];
    assign rd_addr = id_inst[11:7];
    
    
    logic [3:0] alu_ctrl, ex_alu_ctrl;
    logic is_store, mem_is_store, r_we, is_load,mem_is_load, illegal, alu_a_sel, is_branch, wb_r_we, ex_r_we, mem_r_we, ex_is_load, ex_illegal, mem_illegal, wb_illegal, ex_alu_a_sel, ex_is_branch, ex_is_store, ex_inst30;
    logic [2:0] imm_sig, funct3, ex_funct3, mem_funct3;
    logic [1:0] alu_b_sel, ex_alu_b_sel, is_jump, ex_is_jump, wb_sel, ex_wb_sel, mem_wb_sel, wb_wb_sel;
    decoder#(.W(W))decoder_d ( .inst(id_inst), .alu_ctrl(alu_ctrl), .r_we(r_we),
                            .is_load(is_load), .is_store(is_store), .illegal(illegal), .alu_a_sel(alu_a_sel),
                            .is_branch(is_branch), .imm_sig(imm_sig), .funct3(funct3),
                            .alu_b_sel(alu_b_sel), .is_jump(is_jump),.wb_sel(wb_sel)); 
    
    immgen #(.W(W)) immgen_d (.inst(id_inst), .imm_sig(imm_sig), .imm(imm));
    logic we;
    assign we = wb_en && wb_r_we && ~wb_illegal;
    
    reg_module #(.W(W), .D(D), .R(R)) reg_d (.clk(clk), .we(we), .wr(wb_rd_addr), .rd1(rs1_addr), .rd2(rs2_addr), .d_in(wb_rd_in), .d_out1(rs1_val), .d_out2(rs2_val));
    always_ff @(posedge clk) begin 
    //if IF and MEM are stalled correctly, values dont change and we dont need stall logic here
        
        if (rst) begin
        ex_r_we      <= 1'b0;
        ex_is_load   <= 1'b0;
        ex_is_store  <= 1'b0;
        ex_is_branch <= 1'b0;
        ex_is_jump   <= 2'b00;
        ex_illegal   <= 1'b0;
        ex_wb_sel    <= 2'b00;
        ex_alu_a_sel <= 1'b0;
        ex_alu_b_sel <= 2'b00;
        ex_funct3    <= 3'b000;
        ex_alu_ctrl  <= 4'b0000;
        
        end else if (id_en) begin
            ex_pc <= id_pc;
            ex_imm <= imm;
            
            ex_is_store <= is_store;
            ex_alu_ctrl <= alu_ctrl;
            ex_r_we <= r_we; 
            ex_is_load <= is_load;
            ex_illegal <= illegal;
            ex_alu_a_sel <= alu_a_sel;
            ex_is_branch <= is_branch;
            ex_funct3 <= funct3;
            ex_alu_b_sel <= alu_b_sel;
            ex_is_jump <= is_jump;
            ex_wb_sel <= wb_sel;
            
            ex_rs1_addr <=rs1_addr;
            ex_rs2_addr <= rs2_addr;
            ex_rd_addr <= rd_addr;
            ex_rs1_val <= rs1_val & {32{|rs1_addr[4:0]}};
            ex_rs2_val <= rs2_val & {32{|rs2_addr[4:0]}};
            ex_inst30 <= id_inst[30];
        end
    end
   
    ////////////////////////////////////
    
    
    /////////////////////////////////////
    //ex register file
    logic [W-1:0] usable_a, usable_b, usable_result, target;
    logic branch_taken;
    logic cmp;
    assign cmp = ex_funct3[2] ? usable_result[0] : ~|usable_result;
    assign branch_taken = ex_is_branch && (cmp ^ ex_funct3[0]);
    assign if_pc_sig = ex_is_jump[1] || branch_taken;
    assign if_pc_alt = ex_is_jump[0] ? (target & ~32'd1) : target;
    alu #(W) alu_d (.a(usable_a), .b(usable_b), .op(ex_alu_ctrl), .result(usable_result));
    assign target = (ex_is_jump[0]? ex_rs1_val : ex_pc)+ ex_imm;
    
    always_comb begin
        case (ex_alu_a_sel) 
            1'b0: usable_a = ex_rs1_val;
            1'b1: usable_a = ex_pc;
        endcase
        
        case (ex_alu_b_sel)
            2'b00: usable_b = ex_rs2_val;
            2'b01: usable_b = ex_imm;
            2'b10: usable_b = 32'd4;
            2'b11: usable_b = '0;
        endcase
    end
    
    logic [W-1:0]mem_result;
    always_ff @(posedge clk) begin
        if (rst) begin
        mem_r_we     <= 1'b0;
        mem_is_load  <= 1'b0;
        mem_is_store <= 1'b0;
        mem_illegal  <= 1'b0;
        mem_wb_sel   <= 2'b00;
        mem_funct3   <= 3'b000;
        
        
       end else if (ex_en) begin
            mem_result <= usable_result;
            mem_rs2_val <=ex_rs2_val;
            mem_funct3 <= ex_funct3;
            mem_is_load <= ex_is_load;
            mem_is_store <= ex_is_store;
            mem_rd_addr <= ex_rd_addr;
            mem_r_we <= ex_r_we;
            mem_wb_sel <= ex_wb_sel;
            mem_illegal <= ex_illegal;
            mem_imm <= ex_imm;
        end
    end
    /////////////////////////////////////////
    
    
    ///////////////////////////////////////
    //MEM Register Files
    logic [W-1:0] usable_memory, wb_memory, wb_result;
    logic  mem_misaligned; //tx;
    load_store #(.W(W), .D(DEEP)) lsu_d (   .addr(mem_result), .funct3(mem_funct3), 
                                            .is_store(mem_is_store), .rst(rst), .mem_valid(mem_mem_valid),
                                            .clk(clk), .d_in(mem_rs2_val), .d_out(usable_memory),
                                            .mem_ready(mem_mem_ready), .mem_misaligned(mem_misaligned), .tx(tx));
    
    
    assign mem_mem_valid = mem_en && (mem_is_load || mem_is_store);
    assign mem_stall = mem_mem_valid && ~mem_mem_ready;
    logic illegal_seen;
    always_ff @(posedge clk) begin
        if (rst) begin
            
            wb_r_we    <= 1'b0;
            wb_illegal <= 1'b0;
            wb_wb_sel  <= 2'b00;
            
        
        end else if (mem_en) begin
            wb_memory <= usable_memory;
            wb_imm <= mem_imm;
            wb_result <= mem_result;
            wb_rd_addr <= mem_rd_addr;
            wb_wb_sel <= mem_wb_sel;
            wb_r_we <= mem_r_we;
            wb_illegal <= mem_illegal;
        end
    end
    ///////////////////////////////////////
    
    
    /////////////////////////////////////////
    //WB Register Files
    
    always_comb begin
        case (wb_wb_sel)
            2'b01: wb_rd_in = wb_memory;
            2'b10: wb_rd_in = wb_imm;
            default: wb_rd_in = wb_result;
        endcase
    end
    
    
    always_ff @(posedge clk) begin
        if (rst)illegal_seen <= 1'b0;
        else if (wb_en && wb_illegal) illegal_seen <=1'b1;
    end
        
    assign illegal_out = illegal_seen; 
endmodule
