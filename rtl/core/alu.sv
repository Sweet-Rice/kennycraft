`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11.08.2026 23:02:41
// Design Name: 
// Module Name: alu
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


module alu #(parameter W =32)(
input logic [W-1:0]a, b, 
input logic [3:0]op,
output logic [W-1:0]result
    );
    
    
    logic [W-1:0] sh_in, sh_out, rev_a, rev_out, core_result;
    logic [W-1:0] sum; logic ltu, lt; //adder wires
    

    genvar i;
    generate                                // should be cheap. just 64 wires.
        for (i = 0; i < W; i++) begin : rev_gen
        assign rev_a[i]   = a[W-1-i];       //reverses a to be fed into sll
        assign rev_out[i] = sh_out[W-1-i];  //reverses sh_out (of sll) to feed back into result
        end 
    endgenerate
    
    assign sh_in = (op == 4'b0001) ? rev_a : a; // sll ? sra + srld
                                    // v looks funny but thank you risc architects
    
    shifter_op #(W) sh (sh_in, b[4:0], (op[3] & a[W-1]), sh_out);
    addsub #(W) addsub (a, b, op[3] | op[1], sum, lt, ltu);


    
    always_comb begin
        case (op[2:0])
            3'b000: result = sum;                          // add and sub, sub has op[3]
            //3'b000: result = sum;                          // sub
            3'b001: result = rev_out;                      // sll
            3'b010: result = {{W-1{1'b0}}, lt};            // slt
            3'b011: result = {{W-1{1'b0}}, ltu};           // sltu
            3'b100: result = a ^ b;                        // xor
            3'b101: result = sh_out;                       // srl and sra, sra has op[3]
            //3'b101: result = sh_out;                       // sra
            3'b110: result = a | b;                        // or
            3'b111: result = a & b;                        // and
            default: result = '1;
        endcase 
    end
    
    
endmodule

