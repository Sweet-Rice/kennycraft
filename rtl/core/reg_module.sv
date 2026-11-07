`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 14.08.2026 15:34:43
// Design Name: 
// Module Name: reg_module
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: This is designed to be variable depth in preparation for 
// physical threads. {ctx_addr, $clog2(R)} = $clog2(D) is the pattern.

//intentionally left out x0 needing to be zero. having that inside could mess up inference
// 
//////////////////////////////////////////////////////////////////////////////////


module reg_module#(parameter W = 32, D = 64, R = 32)(
input logic clk, we, 
input logic [$clog2(D)-1:0] wr, rd1, rd2, //rd3,
input logic [W-1:0] d_in, output logic [W-1:0] d_out1, d_out2//, d_out3

    );
    
   logic [W-1:0] regs [D-1:0]; 
   always_ff@(posedge clk) begin
   if (we) regs[wr]<=d_in;
   end
   assign d_out1=regs[rd1];
   assign d_out2=regs[rd2];
   //assign d_out3=regs[rd3]; 
    
    
endmodule


