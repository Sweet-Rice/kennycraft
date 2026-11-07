`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12.08.2026 22:21:40
// Design Name: 
// Module Name: addsub
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

module addsub #(parameter W = 32) (
    input  logic [W-1:0] a, b,
    input  logic sub,       
    output logic [W-1:0] sum,
    output logic lt,       
    output logic ltu       
);

    logic [W-1:0] b_in;
    logic cout, v;

    assign b_in = b ^ {W{sub}};
    assign {cout, sum} = a + b_in + sub;

    assign ltu = ~cout;
    assign v   = (a[W-1] ^ sum[W-1]) & ~(a[W-1] ^ b[W-1] ^ sub); //HATE.
    assign lt  = sum[W-1] ^ v;


endmodule
