`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12.08.2026 00:18:42
// Design Name: 
// Module Name: barrel_shifter
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


//my version but the operator won :(


/*
module shifter#(parameter W = 32)(
input logic [W-1:0]a,
input logic [4:0]b, 
input logic sel, // sel is sign bit
output logic [W-1:0]result
    );
    
    logic [W-1:0] stage [0:5];
    assign stage[0]=a;
    
    genvar i;
    generate
        for (i = 0; i < 5; i++) begin : shift_stage
            assign stage[i+1] = b[i] ? {{2**i{sel}},{stage[i][W-1:2**i]}}:stage[i]; //wonderfully elegant generate
            end
            endgenerate
            
            assign result = stage[5];
   
endmodule
*/

module shifter_op #(parameter W = 32) (
    input  logic [W-1:0] a,
    input  logic [((W > 1) ? $clog2(W) : 1)-1:0] b,
    input  logic sel,     
    output logic [W-1:0] result
);
    logic [2*W-1:0] fill;

    assign fill  = {{W{sel}}, a};   //truncation is your best friend
    assign result = fill >> b;      //truncation is your best frie  

endmodule
