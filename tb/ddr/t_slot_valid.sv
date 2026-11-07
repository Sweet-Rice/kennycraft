// t_slot_valid: world_remap + chunk_engine registers.
//  - SLOT_VALID and WIN_ORIGIN read back what was written (16 bits; x 5:0,
//    z 13:8).
//  - With a 4 x 4 window loaded at corner chunk (5, 10) (WIN_ORIGIN x 16,
//    z 32), reads through world_remap return the block only when the slot
//    holding it is valid, for the core port and all 8 VTRACE lanes; each
//    single slot, no slot, all slots and random masks.
//  - Core writes into an invalid slot still land and read back once valid.
module t_slot_valid;
`include "ddr_harness.svh"

  localparam int CCX = 5, CCZ = 10;

  function automatic int slot_of(input logic [16:0] rel);
    int px, pz;
    px = (int'(rel[5:0]) + CCX * 16) % 64;
    pz = (int'(rel[11:6]) + CCZ * 16) % 64;
    return (pz / 16) * 4 + px / 16;
  endfunction

  function automatic logic [3:0] expect_rd(input logic [16:0] rel, input logic [15:0] valid);
    if (!valid[slot_of(rel)]) return 4'd0;
    return world_f(CCX * 16 + int'(rel[5:0]), int'(rel[16:12]), CCZ * 16 + int'(rel[11:6]));
  endfunction

  task automatic check_core(input logic [15:0] valid, input int n);
    for (int k = 0; k < n; k++) begin
      logic [16:0] rel;
      logic [3:0]  d;
      rel = (k < 64) ? rel_addr((k % 4) * 16 + (k / 16) % 4 * 5, k % 32, ((k / 4) % 4) * 16 + 15)
                     : 17'($urandom);
      core_rd(rel, d);
      if (d !== expect_rd(rel, valid))
        $fatal(1, "core read rel %h (slot %0d) valid %h = %h, want %h",
               rel, slot_of(rel), valid, d, expect_rd(rel, valid));
    end
  endtask

  task automatic check_vtrace(input logic [15:0] valid, input int n);
    logic [16:0] prev [LANES];
    @(negedge clk) vtrace_busy = 1'b1;
    for (int k = 0; k <= n; k++) begin
      for (int l = 0; l < LANES; l++) begin
        prev[l]    = vt_addr[l];
        vt_addr[l] = 17'($urandom);
      end
      @(posedge clk); #1;
      if (k > 0)
        for (int l = 0; l < LANES; l++)
          if (vt_rdata[l] !== expect_rd(prev[l], valid))
            $fatal(1, "VTRACE lane %0d rel %h valid %h = %h, want %h",
                   l, prev[l], valid, vt_rdata[l], expect_rd(prev[l], valid));
      @(negedge clk);
    end
    vtrace_busy = 1'b0;
  endtask

  task automatic set_valid(input logic [15:0] v);
    logic [31:0] d;
    mmio_w(OFF_VALID, {16'hFFFF, v});
    mmio_rd(OFF_VALID, d);
    if (d !== {16'd0, v}) $fatal(1, "SLOT_VALID reads %h after writing %h", d, v);
  endtask

  initial begin
    logic [31:0] d;
    logic [3:0]  r;

    do_reset();
    wait_calib();

    // register read-back
    mmio_rd(OFF_VALID, d);
    if (d !== 32'd0) $fatal(1, "SLOT_VALID after reset = %h", d);
    mmio_w(OFF_ORIGIN, 32'hFFFF_FFFF);
    mmio_rd(OFF_ORIGIN, d);
    if (d !== 32'h0000_3F3F) $fatal(1, "WIN_ORIGIN reads %h after writing all ones", d);
    mmio_rd(OFF_CMD, d);
    if (d !== 32'd0) $fatal(1, "CHUNK_CMD reads %h, want 0", d);

    // load the 4 x 4 window around corner chunk (CCX, CCZ)
    for (int cz = CCZ; cz < CCZ + 4; cz++)
      for (int cx = CCX; cx < CCX + 4; cx++) begin
        ddr_put_world_chunk(cx, cz);
        chunk_sync(0, cx, cz);
      end
    mmio_w(OFF_ORIGIN, {18'd0, 6'((CCZ * 16) % 64), 2'b00, 6'((CCX * 16) % 64)});

    set_valid(16'h0000);
    check_core(16'h0000, 512);
    check_vtrace(16'h0000, 256);
    for (int s = 0; s < 16; s++) begin
      set_valid(16'(1 << s));
      check_core(16'(1 << s), 256);
      check_vtrace(16'(1 << s), 64);
    end
    for (int k = 0; k < 8; k++) begin
      logic [15:0] v;
      v = 16'($urandom);
      set_valid(v);
      check_core(v, 256);
      check_vtrace(v, 128);
    end
    set_valid(16'hFFFF);
    check_core(16'hFFFF, 1024);
    check_vtrace(16'hFFFF, 256);

    // writes into an invalid slot go through
    set_valid(16'h0000);
    core_wr(rel_addr(3, 7, 50), 4'hA);
    core_rd(rel_addr(3, 7, 50), r);
    if (r !== 4'h0) $fatal(1, "read of invalid slot after write = %h, want 0", r);
    set_valid(16'hFFFF);
    core_rd(rel_addr(3, 7, 50), r);
    if (r !== 4'hA) $fatal(1, "write into invalid slot lost: read %h, want A", r);

    $display("t_slot_valid: PASS");
    $finish;
  end
endmodule
