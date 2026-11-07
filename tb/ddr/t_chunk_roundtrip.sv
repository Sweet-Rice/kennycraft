// t_chunk_roundtrip: chunk_engine + ddr_bridge + ddr_model.
//  1. LOAD chunks at the corners and middle of DDR3 into their slots, check
//     all four world copies against DDR3, measure one LOAD.
//  2. STORE a slot (copy 0 only), check DDR3, wipe the slot, LOAD it back.
//  3. VTRACE busy pauses the engine; it resumes when busy drops.
//  4. 12 back-to-back commands under random VTRACE/core interference: the
//     9th+ CHUNK_CMD write stalls (queue depth 8), DDR_STATUS shows full and
//     busy, CHUNK_DONE counts every command, data stays correct.
module t_chunk_roundtrip;
`include "ddr_harness.svh"

  task automatic ddr_random_chunk(input int cx, input int cz);
    for (int b = 0; b < 256; b++)
      u_ddr.poke(beat_idx(cx, cz, b), {$urandom, $urandom, $urandom, $urandom});
  endtask

  initial begin
    int cx_list [5] = '{0, 5, 255, 128, 77};
    int cz_list [5] = '{0, 7, 255, 3, 200};
    logic [31:0] st, d;
    int unsigned t, t0, load_cycles;
    int s, max_stall;
    logic [3:0] img [8192];

    do_reset();
    wait_calib();
    mmio_rd(OFF_STATUS, st);
    if (st != 32'h1) $fatal(1, "DDR_STATUS after calib = %h, want 1", st);

    // ---- 1. LOADs ----
    for (int k = 0; k < 5; k++) ddr_random_chunk(cx_list[k], cz_list[k]);
    for (int k = 0; k < 5; k++) begin
      chunk_cmd(0, cx_list[k], cz_list[k], t, s);
      t0 = cyc;
      chunk_wait(t);
      if (k == 0) load_cycles = cyc - t0;
      check_slot_vs_ddr(cx_list[k], cz_list[k], "LOAD");
    end
    $display("t_chunk_roundtrip: one LOAD = %0d core cycles = %0d.%02d us at 50 MHz",
             load_cycles, load_cycles / 50, (load_cycles % 50) * 2);

    // ---- 2. STORE then LOAD back ----
    for (int i = 0; i < 8192; i++) begin
      logic [16:0] pa;
      pa = phys(5, 7, i % 16, i / 256, (i / 16) % 16);
      img[i] = 4'($urandom);
      wmem[0][pa] = img[i];
      for (int c = 1; c < 4; c++) wmem[c][pa] = ~img[i];  // STORE must read copy 0
    end
    chunk_sync(1, 5, 7);
    for (int i = 0; i < 8192; i++)
      if (ddr_block(5, 7, i) !== img[i])
        $fatal(1, "STORE: block %0d in DDR3 = %h, slot had %h", i, ddr_block(5, 7, i), img[i]);
    for (int i = 0; i < 8192; i++)
      for (int c = 0; c < 4; c++) wmem[c][phys(5, 7, i % 16, i / 256, (i / 16) % 16)] = 4'd0;
    chunk_sync(0, 5, 7);
    check_slot_vs_ddr(5, 7, "STORE/LOAD roundtrip");
    // neighbours untouched by DDR traffic of (5,7)
    for (int b = 0; b < 256; b++)
      if (u_ddr.peek(beat_idx(6, 7, b)) != '0 || u_ddr.peek(beat_idx(5, 8, b)) != '0)
        $fatal(1, "STORE of (5,7) leaked into a neighbouring chunk");

    // ---- 3. VTRACE busy pauses the engine ----
    vtrace_busy = 1'b1;
    ddr_random_chunk(9, 9);
    chunk_cmd(0, 9, 9, t, s);
    repeat (20000) @(posedge clk);
    mmio_rd(OFF_DONE, d);
    if (d >= t) $fatal(1, "LOAD finished while VTRACE was busy");
    mmio_rd(OFF_STATUS, st);
    if (st[1] != 1'b1) $fatal(1, "DDR_STATUS.busy = 0 with a paused command");
    vtrace_busy = 1'b0;
    chunk_wait(t);
    check_slot_vs_ddr(9, 9, "LOAD after VTRACE pause");

    // ---- 4. queue full, interference ----
    for (int k = 0; k < 6; k++) ddr_random_chunk(20 + k, 40 + k);
    interfere = 1;
    vtrace_busy = 1'b1;          // hold the engine so the queue fills up
    max_stall = 0;
    for (int k = 0; k < 12; k++) begin
      if (k == 9) begin
        // one command popped into the (paused) engine, eight queued
        mmio_rd(OFF_STATUS, st);
        if (st[2:1] != 2'b11) $fatal(1, "DDR_STATUS with 8 queued = %h, want full+busy", st);
        vt_release = 5000;        // then interference takes over
      end
      // 6 LOADs, then 6 STOREs of the same chunks (slots 0 and 1 are reused,
      // so only chunks 22..25 are compared against DDR3 afterwards)
      if (k < 6) chunk_cmd(0, 20 + k, 40 + k, t, s);
      else       chunk_cmd(1, 20 + (k - 6), 40 + (k - 6), t, s);
      if (s > max_stall) max_stall = s;
    end
    if (max_stall == 0) $fatal(1, "CHUNK_CMD write never stalled with a full queue");
    chunk_wait(t);
    interfere = 0;
    @(negedge clk) vtrace_busy = 1'b0;
    mmio_rd(OFF_DONE, d);
    if (d != issued) $fatal(1, "CHUNK_DONE = %0d, issued %0d", d, issued);
    for (int k = 2; k < 6; k++) check_slot_vs_ddr(20 + k, 40 + k, "LOAD under interference");
    repeat (50) @(posedge clk);
    mmio_rd(OFF_STATUS, st);
    if (st != 32'h1) $fatal(1, "DDR_STATUS idle = %h, want 1", st);

    $display("t_chunk_roundtrip: PASS (%0d commands, longest CHUNK_CMD stall %0d cycles)",
             issued, max_stall);
    $finish;
  end
endmodule
