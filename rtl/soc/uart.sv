`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 24.08.2026 03:16:37
// Design Name: 
// Module Name: uart
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


module uart#(parameter CLK_SPD = 100_000_000, BAUD = 115200)(
input logic clk, rst,
input logic [7:0] data_in,
input logic start,
output logic busy, tx
    );
    localparam rate = CLK_SPD / BAUD;    
    localparam width = $clog2(rate);
    
     logic [width+1:0] baud_cnt;
    logic [9:0] shifter;
    logic [3:0] bit_cnt;
    assign tx = shifter[0];
    
    always_ff @(posedge clk) begin
        if (rst) begin
            busy <=1'b0;
            baud_cnt <='0;
            bit_cnt <= '0;
            shifter <='1;
        
        end else if (~busy) begin
            baud_cnt <= '0;
            bit_cnt <='0;
            
            if (start) begin
            shifter <= {1'b1, data_in, 1'b0};
            busy <= 1'b1;
            end
        end
        
        else  begin 
            if (baud_cnt ==rate - 1) begin
                baud_cnt <='0;
                
                if (bit_cnt == 4'd10) begin
                    busy <=1'b0;
                
                end else begin
                
                    shifter <= {1'b1, shifter[9:1]};
                    bit_cnt <= bit_cnt + 1'b1;
                end
             end else begin
                baud_cnt <= baud_cnt + 1'b1;
             end
          end
       end
endmodule
        
        
        
       