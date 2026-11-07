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


module load_store #(parameter W = 32, D = 4096)(
input logic [W-1:0] addr,
input logic [2:0] funct3,
input logic is_store, 
input logic rst, mem_valid, clk,
input logic [W-1:0] d_in,
output logic [W-1:0] d_out, 
output logic mem_ready, mem_misaligned,
output logic tx
    );
    //if we separate the actions for store and load, we can get single cycle store
    //and double cycle load. load needs to stall, and we design an outstanding state system
    // that should help with maintaining state and may assist in a future pipelining endeavor.

    
    localparam AW = $clog2(D);
    
    logic [AW-1:0] word_addr;
    logic [W-1:0] raw;
    assign word_addr = addr[AW+1:2]; //byte addressed
    logic load_pending;
    assign mem_ready = (mem_valid && is_store) || load_pending;

    logic [2:0] funct3_q;
    logic [1:0] offset_q;   
    
    logic sel_uart, sel_dram, sel_q;
    logic uart_data, uart_stat;
    assign sel_uart = (addr[31:28] == 4'h1);
    assign uart_data = sel_uart && ~addr[2];
    assign uart_stat = sel_uart && addr[2];
    assign sel_dram = (addr[31:28] == 4'h8);
    
    logic start, busy;
    assign start = (mem_valid && is_store && uart_data);
   uart uart_d(.clk(clk), .rst(rst), .data_in(d_in[7:0]), .start(start), .busy(busy), .tx(tx));
   
   logic [3:0] byte_we;
   logic [W-1:0] d_wr;
   logic do_write;
   memory_arr #(.W(W), .D(D)) mem_d (
    .clk(clk), .word_addr(word_addr),
    .byte_we(byte_we), .d_wr(d_wr), .raw(raw));
    
   assign do_write = mem_valid && is_store && ~mem_misaligned && sel_dram;
       always_ff @(posedge clk) begin
       
        if (rst) begin
            load_pending <= 1'b0;
           
        end else begin
               
                 
            if (mem_valid && !is_store && !load_pending) begin
                //here lives logic for the load state
                
                funct3_q <=funct3;
                offset_q <= addr[1:0];
                load_pending <=1'b1;
                sel_q <= sel_uart;
            end 
            else if (load_pending) begin
                load_pending <= 1'b0;
            end
        end
       end
    always_comb begin
    byte_we = 4'b0000;
    d_wr = d_in;
    case (funct3)
    3'b000: begin
        byte_we = 4'b0001 << addr[1:0];
        d_wr = {4{d_in[7:0]}};
    end   
    3'b001: begin
    byte_we = addr[1] ? 4'b1100 : 4'b0011;
    d_wr = {2{d_in[15:0]}};
    end
    3'b010: begin
    byte_we = 4'b1111;
    d_wr = d_in;
    end
    endcase
    if (!do_write) byte_we = 4'b0000;
    end
    always_comb begin
     mem_misaligned = 1'b0;
        
        if (mem_valid) begin
            case (funct3)
                3'b000, 3'b100: mem_misaligned = 1'b0; //SB. LB, LBU
                3'b001, 3'b101: mem_misaligned = addr[0]; //SH, LH, LHU
                3'b010: mem_misaligned = |addr[1:0]; //LW
                
            endcase
        end
    
    end
    always_comb begin
        d_out = '0;
        if (~sel_q) begin
        case (funct3_q)
            3'b000:begin // LB
                case (offset_q)
                    2'b00: d_out = {{24{raw[7]}}, raw[7:0]};
                    2'b01: d_out = {{24{raw[15]}}, raw[15:8]};
                    2'b10: d_out = {{24{raw[23]}}, raw[23:16]};
                    2'b11: d_out = {{24{raw[31]}}, raw[31:24]};
                endcase
                
                end
            3'b001: begin // LH
                    case (offset_q)
                        2'b00: d_out = {{16{raw[15]}}, raw[15:0]};
                        2'b10: d_out = {{16{raw[31]}}, raw[31:16]};
                        default: begin
                        d_out = '0; // misaligned
                        
                        end
                    endcase
                end
        
                3'b010: begin // LW
                    d_out = raw;
                end
        
                3'b100: begin // LBU
                    case (offset_q)
                        2'b00: d_out = {24'b0, raw[7:0]};
                        2'b01: d_out = {24'b0, raw[15:8]};
                        2'b10: d_out = {24'b0, raw[23:16]};
                        2'b11: d_out = {24'b0, raw[31:24]};
                    endcase
                    
                end
        
                3'b101: begin // LHU
                    case (offset_q)
                        2'b00: d_out = {16'b0, raw[15:0]};
                        2'b10: d_out = {16'b0, raw[31:16]};
                        default: begin
                        
                        d_out = '0; 
                        end
                    endcase
                end
            endcase
            end else if (sel_q) d_out = {31'b0, busy};
                       
            end 
        
endmodule