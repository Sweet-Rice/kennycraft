`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// datapath_tb.sv
//
// Runs three programs against the multicycle core:
//   1. arithmetic       -- addi, add, sub, register writeback
//   2. control flow     -- taken branch, not-taken branch, jal link address
//   3. memory + UART    -- sw, lw, sb, lbu, and a store to the UART
//
// Each program runs from a clean reset. The UART receiver samples tx
// independently and reconstructs bytes.
//////////////////////////////////////////////////////////////////////////////////

module datapath_tb;

    localparam RESET_VEC  = 32'h8000_0000;
    localparam BAUD_DIV   = 868;            // 100 MHz / 115200
    localparam IMEM_WORDS = 4096;
    localparam DMEM_WORDS = 4096;

    logic clk = 0;
    logic rst;
    logic tx, illegal_out;
    logic [31:0] if_pc;

    always #5 clk = ~clk;

    datapath #(.RESET_VEC(RESET_VEC)) dut (
        .clk(clk), .rst(rst),
        .tx(tx), .illegal_out(illegal_out), .if_pc(if_pc)
    );

    int errors = 0;
    int trace_limit = 0;   // cycles of trace to print; 0 = silent

    // =====================================================================
    // Helpers
    // =====================================================================
    task automatic clear_all();
        for (int i = 0; i < 64; i++)          dut.reg_d.regs[i]         = '0;
        for (int i = 0; i < IMEM_WORDS; i++)  dut.if_fetch.mem_d.mem[i] = 32'h00000013;
        for (int i = 0; i < DMEM_WORDS; i++)  dut.lsu_d.mem_d.mem[i]    = '0;
    endtask

    task automatic do_reset();
        rst = 1;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 0;
    endtask

    task automatic check(input string name, input logic [31:0] got, input logic [31:0] exp);
        if (got !== exp) begin
            $display("    FAIL  %-22s = %h, expected %h", name, got, exp);
            errors++;
        end else begin
            $display("    ok    %-22s = %h", name, got);
        end
    endtask

    // =====================================================================
    // Trace
    // =====================================================================
    string st;
    always_comb begin
        case (dut.current_state)
            3'b000: st = "IF ";
            3'b001: st = "ID ";
            3'b010: st = "EX ";
            3'b011: st = "MEM";
            3'b100: st = "WB ";
            default: st = "???";
        endcase
    end

    int cyc = 0;
    always @(posedge clk) begin
        if (!rst) begin
            if (cyc < trace_limit)
                $display("    cyc %3d  %s  pc=%h  inst=%h  we=%b  rd=%0d  val=%h",
                         cyc, st, if_pc, dut.id_inst, dut.we,
                         dut.wb_rd_addr, dut.wb_rd_in);
            cyc++;
        end
    end

    // =====================================================================
    // UART receiver
    // =====================================================================
    int         rx_count = 0;
    logic [7:0] rx_byte;

    initial begin
        forever begin
            @(negedge tx);
            #(BAUD_DIV * 10 / 2);
            for (int b = 0; b < 8; b++) begin
                #(BAUD_DIV * 10);
                rx_byte[b] = tx;
            end
            #(BAUD_DIV * 10);
            $display("    RX: %h  '%c'", rx_byte, rx_byte);
            rx_count++;
        end
    end

    // =====================================================================
    // Programs
    // =====================================================================
    initial begin

        // -----------------------------------------------------------------
        // 1. Arithmetic
        //
        //   addi x1, x0, 5
        //   addi x2, x0, 10
        //   add  x3, x1, x2      x3 = 15
        //   sub  x6, x2, x1      x6 = 5
        //   jal  x0, 0
        // -----------------------------------------------------------------
        $display("=== 1. arithmetic ===");
        clear_all();
        dut.if_fetch.mem_d.mem[0] = 32'h00500093;
        dut.if_fetch.mem_d.mem[1] = 32'h00A00113;
        dut.if_fetch.mem_d.mem[2] = 32'h002081B3;
        dut.if_fetch.mem_d.mem[3] = 32'h40110333;
        dut.if_fetch.mem_d.mem[4] = 32'h0000006F;

        cyc = 0;
        do_reset();
        repeat (40) @(posedge clk);
        @(negedge clk);

        check("x1", dut.reg_d.regs[1], 32'd5);
        check("x2", dut.reg_d.regs[2], 32'd10);
        check("x3 (x1+x2)", dut.reg_d.regs[3], 32'd15);
        check("x6 (x2-x1)", dut.reg_d.regs[6], 32'd5);
        check("final pc", if_pc, 32'h8000_0010);
        check("illegal", {31'b0, illegal_out}, 32'd0);

        // -----------------------------------------------------------------
        // 2. Control flow
        //
        //   addi x1, x0, 7
        //   addi x2, x0, 7
        //   beq  x1, x2, +12     taken   -> 0x14
        //   addi x9, x0, 99      skipped
        //   addi x9, x0, 98      skipped
        //   addi x3, x0, 1       x3 = 1
        //   bne  x1, x2, +8      not taken
        //   addi x4, x0, 2       x4 = 2
        //   jal  x5, +8          x5 = 0x8000_0024 -> 0x8000_0028
        //   addi x9, x0, 97      skipped
        //   addi x7, x0, 3       x7 = 3
        //   jal  x0, 0
        // -----------------------------------------------------------------
        $display("=== 2. control flow ===");
        clear_all();
        dut.if_fetch.mem_d.mem[0]  = 32'h00700093;
        dut.if_fetch.mem_d.mem[1]  = 32'h00700113;
        dut.if_fetch.mem_d.mem[2]  = 32'h00208663;
        dut.if_fetch.mem_d.mem[3]  = 32'h06300493;
        dut.if_fetch.mem_d.mem[4]  = 32'h06200493;
        dut.if_fetch.mem_d.mem[5]  = 32'h00100193;
        dut.if_fetch.mem_d.mem[6]  = 32'h00209463;
        dut.if_fetch.mem_d.mem[7]  = 32'h00200213;
        dut.if_fetch.mem_d.mem[8]  = 32'h008002EF;
        dut.if_fetch.mem_d.mem[9]  = 32'h06100493;
        dut.if_fetch.mem_d.mem[10] = 32'h00300393;
        dut.if_fetch.mem_d.mem[11] = 32'h0000006F;

        cyc = 0;
        do_reset();
        repeat (100) @(posedge clk);
        @(negedge clk);

        check("x1", dut.reg_d.regs[1], 32'd7);
        check("x3 (after beq)", dut.reg_d.regs[3], 32'd1);
        check("x4 (bne not taken)", dut.reg_d.regs[4], 32'd2);
        check("x5 (jal link)", dut.reg_d.regs[5], 32'h8000_0024);
        check("x7 (after jal)", dut.reg_d.regs[7], 32'd3);
        check("x9 (never written)", dut.reg_d.regs[9], 32'd0);
        check("final pc", if_pc, 32'h8000_002C);
        check("illegal", {31'b0, illegal_out}, 32'd0);

        // -----------------------------------------------------------------
        // 3. Memory and UART
        //
        // Base must land in the DRAM region (addr[31:28] == 8), so it takes
        // lui + addi to build. addr[13:2] indexes the array, so 0x80000100
        // still lands at word 0x40.
        //
        //   lui  x1, 0x80000     x1 = 0x80000000
        //   addi x1, x1, 256     x1 = 0x80000100
        //   addi x2, x0, 42
        //   sw   x2, 0(x1)
        //   lw   x3, 0(x1)       x3 = 42
        //   addi x4, x0, -1
        //   sb   x4, 4(x1)
        //   lbu  x5, 4(x1)       x5 = 255
        //   lui  x6, 0x10000     UART data
        //   addi x7, x0, 72      'H'
        //   sb   x7, 0(x6)       transmit
        //   jal  x0, 0
        // -----------------------------------------------------------------
        $display("=== 3. memory and uart ===");
        clear_all();
        rx_count = 0;
        dut.if_fetch.mem_d.mem[0]  = 32'h800000B7;  // lui  x1, 0x80000
        dut.if_fetch.mem_d.mem[1]  = 32'h10008093;  // addi x1, x1, 256
        dut.if_fetch.mem_d.mem[2]  = 32'h02A00113;  // addi x2, x0, 42
        dut.if_fetch.mem_d.mem[3]  = 32'h0020A023;  // sw   x2, 0(x1)
        dut.if_fetch.mem_d.mem[4]  = 32'h0000A183;  // lw   x3, 0(x1)
        dut.if_fetch.mem_d.mem[5]  = 32'hFFF00213;  // addi x4, x0, -1
        dut.if_fetch.mem_d.mem[6]  = 32'h00408223;  // sb   x4, 4(x1)
        dut.if_fetch.mem_d.mem[7]  = 32'h0040C283;  // lbu  x5, 4(x1)
        dut.if_fetch.mem_d.mem[8]  = 32'h10000337;  // lui  x6, 0x10000
        dut.if_fetch.mem_d.mem[9]  = 32'h04800393;  // addi x7, x0, 72
        dut.if_fetch.mem_d.mem[10] = 32'h00730023;  // sb   x7, 0(x6)
        dut.if_fetch.mem_d.mem[11] = 32'h0000006F;  // jal  x0, 0

        cyc = 0;
        do_reset();
        #150_000;                                   // one UART frame is ~87us

        check("x1 (base)", dut.reg_d.regs[1], 32'h8000_0100);
        check("x2", dut.reg_d.regs[2], 32'd42);
        check("x3 (lw)", dut.reg_d.regs[3], 32'd42);
        check("x4", dut.reg_d.regs[4], 32'hFFFF_FFFF);
        check("x5 (lbu)", dut.reg_d.regs[5], 32'd255);
        check("x6 (uart base)", dut.reg_d.regs[6], 32'h1000_0000);
        check("dmem[0x40] (sw)", dut.lsu_d.mem_d.mem[32'h40], 32'd42);
        check("dmem[0x41] (sb)", dut.lsu_d.mem_d.mem[32'h41], 32'h0000_00FF);
        check("uart frames", rx_count, 32'd1);
        check("uart byte", {24'b0, rx_byte}, 32'h0000_0048);
        check("final pc", if_pc, 32'h8000_002C);
        check("illegal", {31'b0, illegal_out}, 32'd0);

        // -----------------------------------------------------------------
        $display("");
        if (errors == 0) $display("=== PASS ===");
        else             $fatal(1, "=== %0d FAILURES ===", errors);
        $finish;
    end

endmodule