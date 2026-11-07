`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01.09.2026 21:15:25
// Design Name: 
// Module Name: memory_array
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


module memory_arr #(parameter W=32, D = 4096, INIT_FILE="" )(
input logic clk,
input logic [3:0] byte_we,
input logic [W-1:0] d_wr,
input logic [$clog2(D)-1:0] word_addr,
output logic [W-1:0] raw
);

    logic [W-1:0] mem [D-1:0];
    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
        
        end
    //byte addressed memory 
    (* ram_style = "block" *)
    
    //byte addressed memory needs byte addressed w.e. per byte in word
    always_ff @(posedge clk) begin
    raw <= mem[word_addr];
    for (int i = 0; i < 4; i++)
        if (byte_we[i]) mem[word_addr][i*8 +: 8] <= d_wr[i*8 +: 8];
    end




endmodule
