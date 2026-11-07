// Shared harness for the tb/core program tests, `included inside a testbench
// module that declares string parameters IMEM_HEX and DMEM_HEX (set with -G
// by tb/core/tb.mk). Provides a 50 MHz clock, kc_soc with the display, DDR
// and world ports tied off, a 1 Mbaud UART receiver on uart_tx and sender on
// uart_rx, a retirement trace (+trace), and memory and register peek helpers.

localparam int CLK_NS   = 20;    // 50 MHz core clock
localparam int BIT_CLKS = 50;    // 1 Mbaud: 50 clocks per bit

logic        clk = 1'b0;
logic        rst = 1'b1;
logic        uart_tx;
logic        uart_rx = 1'b1;
logic [7:0]  leds;
logic        err_led;

always #(CLK_NS / 2) clk = ~clk;

/* verilator lint_off PINCONNECTEMPTY */
kc_soc #(
    .IMEM_HEX(IMEM_HEX),
    .DMEM_HEX(DMEM_HEX)
) dut (
    .clk, .rst,
    .uart_tx, .uart_rx,
    .leds, .err_led,
    .fb_we(), .fb_re(), .fb_addr(), .fb_wdata(), .fb_rdata(8'h00),
    .pal_we(), .pal_addr(), .pal_wdata(),
    .swap_req(), .swap_pending(1'b0), .vblank(1'b0), .frame_count(32'h0), .fb_mode(),
    .ddr_reg_req(), .ddr_reg_we(), .ddr_reg_addr(), .ddr_reg_wdata(),
    .ddr_reg_ready(1'b1), .ddr_reg_rdata(32'h0),
    .world_req(), .world_we(), .world_addr(), .world_wdata(),
    .world_ready(1'b0), .world_rdata(8'h00)
);
/* verilator lint_on PINCONNECTEMPTY */

int unsigned cycle = 0;
always @(posedge clk) cycle <= cycle + 1;

// ---------------------------------------------------------------------
// Peek / poke
// ---------------------------------------------------------------------
function automatic logic [31:0] dmem_rd(input logic [31:0] addr);
    return dut.u_dmem.mem[addr[14:2]];
endfunction

task automatic dmem_wr(input logic [31:0] addr, input logic [31:0] value);
    dut.u_dmem.mem[addr[14:2]] = value;
endtask

function automatic logic [31:0] xreg(input int n);
    return (n == 0) ? 32'd0 : dut.u_core.u_rf.regs[n];
endfunction

task automatic do_reset();
    rst = 1'b1;
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
endtask

// Run until the program writes TB_DONE (0x1000_00FC) or the core halts.
task automatic run_until_done(input int max_cycles);
    for (int i = 0; i < max_cycles; i++) begin
        @(posedge clk);
        if (dmem_rd(32'h1000_00FC) != 0 || err_led) return;
    end
    $fatal(1, "FAIL: timeout after %0d cycles at pc=%08h", max_cycles, dut.u_core.pc);
endtask

// ---------------------------------------------------------------------
// Retirement trace: +trace prints one line per retired instruction.
// ---------------------------------------------------------------------
bit          trace_on = 1'b0;
logic [31:0] tr_inst;
initial trace_on = $test$plusargs("trace");

always @(posedge clk) begin
    if (trace_on && !rst) begin
        if (dut.u_core.state == dut.u_core.S_ID) tr_inst <= dut.u_core.imem_rdata;
        if (dut.u_core.rf_we)
            $display("trace pc=%08h inst=%08h x%0d=%08h", dut.u_core.pc, tr_inst,
                     dut.u_core.ex_rd, dut.u_core.rf_wdata);
        else if ((dut.u_core.state == dut.u_core.S_WB) ||
                 (dut.u_core.state == dut.u_core.S_MEM && dut.u_core.bus_ready && dut.u_core.ex_is_store))
            $display("trace pc=%08h inst=%08h", dut.u_core.pc, tr_inst);
        if (dut.u_core.err_set != 0)
            $display("trace pc=%08h halt err=%b", dut.u_core.err_pc, dut.u_core.err_set);
    end
end

// ---------------------------------------------------------------------
// UART: receiver on uart_tx (checks start and stop bits, samples mid-bit)
// and sender on uart_rx, both at exactly 50 clocks per bit.
// ---------------------------------------------------------------------
logic [7:0] uart_rx_q [$];

initial begin
    logic [7:0] b;
    forever begin
        @(negedge uart_tx);
        repeat (BIT_CLKS / 2) @(posedge clk);
        if (uart_tx !== 1'b0) $fatal(1, "FAIL: UART start bit glitch");
        for (int i = 0; i < 8; i++) begin
            repeat (BIT_CLKS) @(posedge clk);
            b[i] = uart_tx;
        end
        repeat (BIT_CLKS) @(posedge clk);
        if (uart_tx !== 1'b1) $fatal(1, "FAIL: UART stop bit missing");
        uart_rx_q.push_back(b);
    end
end

task automatic uart_send(input logic [7:0] b);
    @(posedge clk);
    uart_rx = 1'b0;
    repeat (BIT_CLKS) @(posedge clk);
    for (int i = 0; i < 8; i++) begin
        uart_rx = b[i];
        repeat (BIT_CLKS) @(posedge clk);
    end
    uart_rx = 1'b1;
    repeat (BIT_CLKS - 1) @(posedge clk);
endtask
