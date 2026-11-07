// Window remap between the world requesters (core, VTRACE) and world_mem (D14).
//
// Addresses are {y[4:0], z[5:0], x[5:0]}. Requesters use window-relative x, z;
// physical x = (x + WIN_ORIGIN.x) mod 64, same for z, y unchanged. The slot of
// a physical address is s = sz * 4 + sx with sx = x[5:4], sz = z[5:4]. Reads
// in a slot whose SLOT_VALID bit is 0 return 0 (air). Writes always go
// through, so the chunk manager can generate a chunk into an invalid slot.
//
// world_mem reads have one cycle of latency, so the slot-valid bit is
// registered with the address and applied to the data the next cycle. The
// core samples it when core_en is high (its memory access cycle); every VTRACE
// lane samples it every cycle, like its free-running world read port.
// The chunk engine bypasses this module and uses physical addresses.
module world_remap #(
  parameter int LANES = 8
) (
  input  logic        clk,
  input  logic [5:0]  win_x,
  input  logic [5:0]  win_z,
  input  logic [15:0] slot_valid,
  // core port
  input  logic        core_en,
  input  logic [16:0] core_addr,
  output logic [16:0] core_paddr,
  input  logic [3:0]  core_rdata_phys,
  output logic [3:0]  core_rdata,
  // VTRACE ports, one per lane
  input  logic [16:0] vt_addr       [LANES],
  output logic [16:0] vt_paddr      [LANES],
  input  logic [3:0]  vt_rdata_phys [LANES],
  output logic [3:0]  vt_rdata      [LANES]
);
  function automatic logic [16:0] remap(input logic [16:0] a);
    logic [5:0] z, x;
    z = a[11:6] + win_z;
    x = a[5:0] + win_x;
    return {a[16:12], z, x};
  endfunction

  // slot of a physical address: {z[5:4], x[5:4]}
  function automatic logic slot_ok(input logic [16:0] pa);
    /* verilator lint_off UNUSEDSIGNAL */
    logic [16:0] a;
    /* verilator lint_on UNUSEDSIGNAL */
    a = pa;
    return slot_valid[{a[11:10], a[5:4]}];
  endfunction

  logic core_ok_q;
  logic vt_ok_q [LANES];

  assign core_paddr = remap(core_addr);
  assign core_rdata = core_ok_q ? core_rdata_phys : 4'd0;

  always_ff @(posedge clk) begin
    if (core_en) core_ok_q <= slot_ok(core_paddr);
  end

  for (genvar l = 0; l < LANES; l++) begin : g_lane
    assign vt_paddr[l] = remap(vt_addr[l]);
    assign vt_rdata[l] = vt_ok_q[l] ? vt_rdata_phys[l] : 4'd0;
    always_ff @(posedge clk) vt_ok_q[l] <= slot_ok(vt_paddr[l]);
  end
endmodule
