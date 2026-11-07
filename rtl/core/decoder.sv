`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02.09.2026 00:33:35
// Design Name: 
// Module Name: decoder
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


module decoder#(parameter W = 32) (
input logic [W-1:0] inst,
output logic [3:0] alu_ctrl,
output logic r_we, is_load, is_store, illegal, alu_a_sel, is_branch,  
output logic [2:0] imm_sig,  funct3,
output logic [1:0] alu_b_sel, is_jump, wb_sel

    );
    alu_decoder #(.W(32), .ALU_ADD(4'b0000)) alu_d (.inst(inst), .alu_ctrl(alu_ctrl));
    always_comb begin
        imm_sig = 3'b000; //default
        wb_sel = 2'b00; // alu_result, mem_data, imm
        alu_a_sel = 1'b0; // rs1, pc
        alu_b_sel = 2'b01; //rs2, imm, 4
        
        r_we = 1'b0;
        is_load = 1'b0;
        is_store = 1'b0;
        illegal = 1'b0;
        is_branch = 1'b0;
        is_jump = 2'b00; //00 no jump, 10 jal, 11 jalr
        funct3 = inst[14:12];
    
    case(inst[6:0])
        
        7'b0110111: begin // LUI  
            wb_sel = 2'b10;
            r_we = 1'b1;
        
        end
        7'b0010111: begin // AUIPC
            alu_a_sel = 1'b1;
            r_we = 1'b1;
            
            
        end
        7'b1101111: begin // JAL
            alu_a_sel = 1'b1;
            alu_b_sel = 2'b10;
            r_we = 1'b1;
            is_jump = 2'b10;
            imm_sig = 3'b111;
            
        end
        7'b1100111: begin // JALR
            alu_a_sel = 1'b1;
            alu_b_sel = 2'b10;
            r_we = 1'b1;
            is_jump = 2'b11;
            imm_sig = 3'b100;
            
        end
        7'b1100011: begin // Branch
            alu_b_sel = 2'b00;
            is_branch = 1'b1;
            imm_sig = 3'b110;
            
        end
        7'b0000011: begin // LOAD
            wb_sel = 2'b01;
            r_we = 1'b1;
            is_load = 1'b1;
            imm_sig = 3'b100;
        end
        7'b0100011: begin // STORE
            is_store = 1'b1;
            imm_sig = 3'b101;
        end
        7'b0010011: begin // opp-imm
            r_we = 1'b1;
            imm_sig = 3'b100;
            
        end
        7'b0110011: begin // op
            r_we = 1'b1;
            alu_b_sel = 2'b00;
        end
        7'b0001111: begin // FENCE
        
        
        end
        7'b1110011: begin // SYSTEM
        
        end
                
        default: illegal = 1'b1;
    endcase
    
    end
    
    
endmodule

module alu_decoder #(parameter W =32, ALU_ADD = 4'b0000) (
    input logic [31:0]inst,
    output logic [3:0] alu_ctrl
    );
    logic is_op, is_opimm, is_shift, use_bit30;
   
    assign is_op     = (inst[6:2] == 5'b01100);
    assign is_opimm  = (inst[6:2] == 5'b00100);
    assign is_shift  = (inst[13:12] == 2'b01);
    assign use_bit30 = is_op | (is_opimm & is_shift);
      
    always_comb begin
        //
        alu_ctrl = ALU_ADD;
        //alu_ctrl[3]=inst[30];
        //op or opimm opcodes
        if (is_op | is_opimm) begin
        alu_ctrl={inst[30] & use_bit30, inst[14:12]};
        end
        //mul goes into its own dedicated unit that isnt the ALU
        
        //branch ops. If beq or bne, hardcode to xor. if any other, shift right to get slt or sltu
        //leaving this for the writeback mux, but bne gets inverted, and alu_ctrl = 1 means to invert its pair.
        else if (inst[6:2] ==5'b11000) begin
            alu_ctrl[3]=inst[30];
            alu_ctrl[2]= ~(|inst[14:13]);
            alu_ctrl[1:0] = inst[14:13];
        end 
        
        
    end


endmodule    