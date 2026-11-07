`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 23.08.2026 23:15:01
// Design Name: 
// Module Name: load_store
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


module fetch #(parameter W = 32, D = 4096, INIT_FILE="")(
input logic fetch_sig,
input logic [W-1:0] addr,
input logic rst, clk,
output logic [W-1:0] d_out, 
output logic mem_ready
    );


    localparam AW = $clog2(D);

    logic [AW-1:0] word_addr;
    logic [W-1:0] raw;
    assign word_addr = addr[AW+1:2]; //byte addressed
    logic fetch_pending;
    assign mem_ready = fetch_pending;

    logic [3:0] byte_we;
    assign byte_we = 4'b0000;
    logic [W-1:0] d_wr;
    assign d_wr = '0;


    memory_arr #(.W(W), .D(D), .INIT_FILE(INIT_FILE)) mem_d (
        .clk(clk), .word_addr(word_addr),
        .byte_we(byte_we), .d_wr(d_wr), .raw(raw));
    always_ff @(posedge clk) begin

        if (rst) begin
            fetch_pending <= 1'b0;

        end else begin
            if (fetch_sig && !fetch_pending) begin
            //here lives logic for the load state
                fetch_pending <=1'b1;
            end 
            else if (fetch_pending) begin
                fetch_pending <= 1'b0;
            end
        end
    end
    always_comb begin
        d_out = raw;
    end

endmodule