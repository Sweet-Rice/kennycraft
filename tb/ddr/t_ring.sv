// t_ring: the 4 x 4-chunk window as a ring buffer (D14, Kenny page Chunk API).
// A chunk manager model moves the window corner around DDR3 like
// world_update(): chunk (cx, cz) always goes in slot (cx mod 4, cz mod 4), only
// slots holding the wrong chunk are reloaded (STORE first if dirty), loaded
// slots become valid when their ticket is done, then WIN_ORIGIN moves. After
// each move every window-relative read through world_remap must equal the
// absolute world (procedural world plus every edit the core made), so edits
// survive leaving the window and coming back. Runs under random VTRACE and
// core interference.
module t_ring;
`include "ddr_harness.svh"

  logic [3:0] edits [int];       // absolute block edits, key {az, y, ax}
  bit         in_ddr [int];      // chunk index -> DDR3 initialized
  int         slot_chunk [16];   // chunk index held by each slot, -1 none
  bit         slot_dirty [16];
  int         ccx, ccz;          // window corner chunk
  logic [15:0] valid;
  int         n_loads = 0, n_stores = 0, n_moves = 0;

  function automatic int ekey(input int ax, input int y, input int az);
    return (az << 17) | (y << 12) | ax;
  endfunction

  function automatic logic [3:0] world_abs(input int ax, input int y, input int az);
    int k;
    k = ekey(ax, y, az);
    return (edits.exists(k) != 0) ? edits[k] : world_f(ax, y, az);
  endfunction

  task automatic move_to(input int ncx, input int ncz);
    int unsigned tickets [16];
    int unsigned t;
    int s;
    bit loading [16];
    for (int i = 0; i < 16; i++) loading[i] = 0;
    // 1. invalidate slots that will change
    for (int sz = 0; sz < 4; sz++)
      for (int sx = 0; sx < 4; sx++) begin
        int slot, cx, cz;
        slot = sz * 4 + sx;
        cx = ncx + ((sx - ncx % 4) + 4) % 4;
        cz = ncz + ((sz - ncz % 4) + 4) % 4;
        if (slot_chunk[slot] != cz * 256 + cx) begin
          loading[slot] = 1;
          valid[slot]   = 1'b0;
        end
      end
    mmio_w(OFF_VALID, {16'd0, valid});
    // 2. queue STORE (if dirty) and LOAD per changing slot
    for (int sz = 0; sz < 4; sz++)
      for (int sx = 0; sx < 4; sx++) begin
        int slot, cx, cz;
        slot = sz * 4 + sx;
        if (!loading[slot]) continue;
        cx = ncx + ((sx - ncx % 4) + 4) % 4;
        cz = ncz + ((sz - ncz % 4) + 4) % 4;
        if (slot_chunk[slot] >= 0 && slot_dirty[slot]) begin
          chunk_cmd(1, slot_chunk[slot] % 256, slot_chunk[slot] / 256, t, s);
          n_stores++;
        end
        if (in_ddr.exists(cz * 256 + cx) == 0) begin
          ddr_put_world_chunk(cx, cz);
          in_ddr[cz * 256 + cx] = 1;
        end
        chunk_cmd(0, cx, cz, tickets[slot], s);
        n_loads++;
        slot_chunk[slot] = cz * 256 + cx;
        slot_dirty[slot] = 0;
      end
    // 3. each slot becomes valid once its LOAD is done
    for (int slot = 0; slot < 16; slot++)
      if (loading[slot]) begin
        chunk_wait(tickets[slot]);
        valid[slot] = 1'b1;
        mmio_w(OFF_VALID, {16'd0, valid});
      end
    // 4. move the window
    ccx = ncx;
    ccz = ncz;
    mmio_w(OFF_ORIGIN, {18'd0, 6'((ccz * 16) % 64), 2'b00, 6'((ccx * 16) % 64)});
    n_moves++;
  endtask

  task automatic check_window(input int n, input string what);
    for (int k = 0; k < n; k++) begin
      int rx, y, rz;
      logic [3:0] d, e;
      rx = $urandom % 64; y = $urandom % 32; rz = $urandom % 64;
      if (k < 16) begin rx = (k % 4) * 16 + k % 16; rz = (k / 4) * 16 + 15 - k % 16; end
      core_rd(rel_addr(rx, y, rz), d);
      e = world_abs(ccx * 16 + rx, y, ccz * 16 + rz);
      if (d !== e) begin
        int ax, az;
        ax = ccx * 16 + rx; az = ccz * 16 + rz;
        $display("  slot_chunk=%0d valid=%h phys copy0=%h ddr=%h", 
                 slot_chunk[((az / 16) % 4) * 4 + (ax / 16) % 4], valid,
                 wmem[0][phys(ax / 16, az / 16, ax % 16, y, az % 16)],
                 ddr_block(ax / 16, az / 16, (y * 16 + az % 16) * 16 + ax % 16));
        $fatal(1, "%s: corner (%0d,%0d) rel (%0d,%0d,%0d) = %h, want %h",
               what, ccx, ccz, rx, y, rz, d, e);
      end
    end
  endtask

  task automatic edit_some(input int n);
    for (int k = 0; k < n; k++) begin
      int rx, y, rz, ax, az, slot;
      logic [3:0] v;
      rx = $urandom % 64; y = $urandom % 32; rz = $urandom % 64;
      v  = 4'($urandom);
      ax = ccx * 16 + rx; az = ccz * 16 + rz;
      core_wr(rel_addr(rx, y, rz), v);
      edits[ekey(ax, y, az)] = v;
      slot = ((az / 16) % 4) * 4 + (ax / 16) % 4;
      slot_dirty[slot] = 1;
    end
  endtask

  initial begin
    int path [12][2] = '{'{3, 3}, '{4, 3}, '{4, 4}, '{3, 4}, '{3, 3}, '{2, 3},
                       '{2, 2}, '{5, 2}, '{5, 5}, '{10, 9}, '{9, 9}, '{2, 3}};
    do_reset();
    wait_calib();
    for (int i = 0; i < 16; i++) begin slot_chunk[i] = -1; slot_dirty[i] = 0; end
    valid = '0;

    move_to(2, 3);
    check_window(131072 / 8, "initial window");
    edit_some(64);
    check_window(2048, "after edits");

    interfere = 1;
    foreach (path[p]) begin
      move_to(path[p][0], path[p][1]);
      check_window(4096, $sformatf("move %0d", p));
      edit_some(32);
    end
    for (int k = 0; k < 16; k++) begin
      int ncx, ncz;
      ncx = ccx; ncz = ccz;
      case ($urandom % 4)
        0: ncx = (ccx < 250) ? ccx + 1 : ccx - 1;
        1: ncx = (ccx > 0)   ? ccx - 1 : ccx + 1;
        2: ncz = (ccz < 250) ? ccz + 1 : ccz - 1;
        default: ncz = (ccz > 0) ? ccz - 1 : ccz + 1;
      endcase
      move_to(ncx, ncz);
      check_window(2048, $sformatf("random move %0d", k));
      edit_some(16);
    end
    interfere = 0;
    // back to the start: every edit made anywhere along the way is visible
    move_to(2, 3);
    check_window(131072, "return to start (full window)");
    for (int i = 0; i < 64; i++) begin
      // and every edit inside the window reads back exactly
      int ax, y, az;
      logic [3:0] d;
      ax = 2 * 16 + $urandom % 64; y = $urandom % 32; az = 3 * 16 + $urandom % 64;
      core_rd(rel_addr(ax - 32, y, az - 48), d);
      if (d !== world_abs(ax, y, az)) $fatal(1, "final spot check (%0d,%0d,%0d)", ax, y, az);
    end
    $display("t_ring: PASS (%0d moves, %0d LOADs, %0d STOREs, %0d edits)",
             n_moves, n_loads, n_stores, edits.num());
    $finish;
  end
endmodule
