`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: top
//
// Board wrapper for the multicycle core on the Digilent Arty A7-100T.
//
// Exists so that datapath's if_pc[31:0] debug output does not become 32 pins,
// and so the board's active-low reset button becomes the core's active-high rst.
//
// led is driven by illegal_out on purpose: if it lights immediately after
// configuration, the instruction memory did not initialize and the core is
// fetching zeros (opcode 0000000 -> decoder default -> illegal).
//////////////////////////////////////////////////////////////////////////////////


module top (
    input  logic clk,            // E3,  100 MHz
    input  logic ck_rst,         // C2,  active low
    output logic uart_rxd_out,   // D10, FPGA -> USB-UART bridge
    output logic led             // H5,  illegal_out
);

    // ck_rst is an asynchronous button. Two-flop it before it reaches any logic.
    logic [1:0] rst_sync = '0;

    // FPGA registers configure to 0, so the core would otherwise start in ST_IF
    // with if_pc = 0 rather than RESET_VEC. Hold reset for 16 cycles after
    // configuration so the FSM, fetch_pending and load_pending come up clean.
    logic [3:0] por_cnt = '0;

    logic rst;

    always_ff @(posedge clk) begin
        rst_sync <= {rst_sync[0], ck_rst};
        if (por_cnt != 4'hF) por_cnt <= por_cnt + 1'b1;
    end

    assign rst = (por_cnt != 4'hF) || ~rst_sync[1];

    logic [31:0] if_pc_nc;

    datapath dp (
        .clk         (clk),
        .rst         (rst),
        .tx          (uart_rxd_out),
        .illegal_out (led),
        .if_pc       (if_pc_nc)
    );

endmodule
