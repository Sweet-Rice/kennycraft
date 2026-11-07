// t_zmmul: runs sw/t_zmmul.S and checks every MUL family result against an
// independent 64-bit computation, plus known products, aliasing, rd = x0 and
// back-to-back dependence.
module t_zmmul_tb;
    parameter string IMEM_HEX = "";
    parameter string DMEM_HEX = "";
    `include "soc_harness.svh"

    localparam int          NPAIRS   = 14;
    localparam logic [31:0] OPERANDS = 32'h1000_0100;
    localparam logic [31:0] RESULTS  = OPERANDS + 8 * NPAIRS;

    int errors = 0;

    task automatic expect32(input string what, input logic [31:0] got, input logic [31:0] exp);
        if (got !== exp) begin
            $display("  FAIL %-28s got %08h expected %08h", what, got, exp);
            errors++;
        end
    endtask

    initial begin
        logic [31:0] a, b, r;
        logic [63:0] ss, su, uu;
        do_reset();
        run_until_done(20000);
        if (err_led) $fatal(1, "FAIL: core halted, ERR_PC=%08h", dut.u_mmio.err_pc);

        for (int i = 0; i < NPAIRS; i++) begin
            a  = dmem_rd(OPERANDS + 8 * i);
            b  = dmem_rd(OPERANDS + 8 * i + 4);
            ss = 64'($signed(a)) * 64'($signed(b));
            su = 64'($signed(a)) * {32'b0, b};
            uu = {32'b0, a} * {32'b0, b};
            r  = RESULTS + 16 * i;
            expect32($sformatf("mul    %08h,%08h", a, b), dmem_rd(r),      uu[31:0]);
            expect32($sformatf("mulh   %08h,%08h", a, b), dmem_rd(r + 4),  ss[63:32]);
            expect32($sformatf("mulhsu %08h,%08h", a, b), dmem_rd(r + 8),  su[63:32]);
            expect32($sformatf("mulhu  %08h,%08h", a, b), dmem_rd(r + 12), uu[63:32]);
            $display("  %08h x %08h: mul %08h mulh %08h mulhsu %08h mulhu %08h", a, b,
                     dmem_rd(r), dmem_rd(r + 4), dmem_rd(r + 8), dmem_rd(r + 12));
        end

        // Known products, independent of the formulas above
        expect32("mulh   8000_0000^2", dmem_rd(RESULTS + 16 * 3 + 4),  32'h4000_0000);
        expect32("mulhsu 8000_0000^2", dmem_rd(RESULTS + 16 * 3 + 8),  32'hC000_0000);
        expect32("mulhu  8000_0000^2", dmem_rd(RESULTS + 16 * 3 + 12), 32'h4000_0000);
        expect32("mulh   -1 x -1",     dmem_rd(RESULTS + 16 * 2 + 4),  32'h0000_0000);
        expect32("mulhu  -1 x -1",     dmem_rd(RESULTS + 16 * 2 + 12), 32'hFFFF_FFFE);
        expect32("mul    3 x -7",      dmem_rd(RESULTS + 16 * 10),     32'hFFFF_FFEB);

        r = RESULTS + 16 * NPAIRS;
        expect32("mul a0,a0,a0 (-3)",   dmem_rd(r),      32'd9);
        expect32("mulhu a1,a1,a1",      dmem_rd(r + 4),  32'h3FFF_FFFF);
        expect32("mul x0 stays 0",      dmem_rd(r + 8),  32'd0);
        expect32("mul then addi",       dmem_rd(r + 12), 32'hFFF0_BDC1);  // -999999

        if (errors != 0) $fatal(1, "FAIL: t_zmmul, %0d mismatches", errors);
        $display("PASS: t_zmmul (%0d operand pairs x 4 ops + 4 extra checks)", NPAIRS);
        $finish;
    end
endmodule
