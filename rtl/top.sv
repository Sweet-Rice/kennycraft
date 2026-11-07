// Board wrapper for the Stage 0 SoC on the Digilent Arty A7-100T.
//
// Interim until P3 builds the real top (clk_gen, display, DDR3): kc_soc runs
// straight off the 100 MHz board clock with the UART divider set for that
// clock (100 clocks per bit, still 1 Mbaud), the display and chunk-engine
// ports tied off, and the hello-world program from tb/core/program.mem.
//
// led is the error LED: it lights when the core halts on an illegal
// instruction, a misaligned access or a fetch outside instruction memory.
module top (
    input  logic clk,            // E3,  100 MHz
    input  logic ck_rst,         // C2,  active low
    output logic uart_rxd_out,   // D10, FPGA -> USB-UART bridge
    output logic led             // H5,  error LED
);

    // ck_rst is an asynchronous button. Two-flop it before it reaches any logic.
    logic [1:0] rst_sync = '0;

    // Hold reset for 16 cycles after configuration so the FSM comes up clean.
    logic [3:0] por_cnt = '0;

    logic rst;

    always_ff @(posedge clk) begin
        rst_sync <= {rst_sync[0], ck_rst};
        if (por_cnt != 4'hF) por_cnt <= por_cnt + 1'b1;
    end

    assign rst = (por_cnt != 4'hF) || ~rst_sync[1];

    // Tied-off outputs are left open on purpose until P3 connects them.
    /* verilator lint_off PINCONNECTEMPTY */
    kc_soc #(
        .CLK_HZ   (100_000_000),
        .BAUD     (1_000_000),
        .IMEM_HEX ("program.mem"),
        .DMEM_HEX ("")
    ) u_soc (
        .clk, .rst,
        .uart_tx(uart_rxd_out), .uart_rx(1'b1),
        .leds(), .err_led(led),
        .fb_we(), .fb_re(), .fb_addr(), .fb_wdata(), .fb_rdata(8'h00),
        .pal_we(), .pal_addr(), .pal_wdata(),
        .swap_req(), .swap_pending(1'b0), .vblank(1'b0), .frame_count(32'h0), .fb_mode(),
        .ddr_reg_en(), .ddr_reg_we(), .ddr_reg_off(), .ddr_reg_wdata(),
        .ddr_reg_rdata(32'h0), .ddr_reg_stall(1'b0),
        .world_req(), .world_we(), .world_addr(), .world_wdata(),
        .world_ready(1'b0), .world_rdata(8'h00)
    );
    /* verilator lint_on PINCONNECTEMPTY */

endmodule
