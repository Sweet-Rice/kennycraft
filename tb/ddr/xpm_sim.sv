// Behavioral Verilator models of the two XPM macros rtl/ddr uses.
// Vivado's own xpm_fifo.sv / xpm_cdc.sv contain SVA sequences and deassign
// that Verilator 5.020 cannot parse, so the DDR testbenches and lint-ddr
// compile these instead; synthesis uses the real XPM library. Only the
// features rtl/ddr needs are modeled: equal widths, READ_MODE "fwft",
// USE_ADV_FEATURES "0000". Gray-coded pointers cross through
// CDC_SYNC_STAGES flops, so full/empty lag like the real macro. Writing a
// full FIFO or reading an empty one is a testbench failure.

/* verilator lint_off DECLFILENAME */
/* verilator lint_off UNUSEDPARAM */
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off UNDRIVEN */
module xpm_fifo_async #(
  parameter string FIFO_MEMORY_TYPE  = "auto",
  parameter int    FIFO_WRITE_DEPTH  = 2048,
  parameter int    WRITE_DATA_WIDTH  = 32,
  parameter int    READ_DATA_WIDTH   = 32,
  parameter string READ_MODE         = "std",
  parameter int    FIFO_READ_LATENCY = 1,
  parameter int    CDC_SYNC_STAGES   = 2,
  parameter string USE_ADV_FEATURES  = "0707"
) (
  input  logic                        sleep,
  input  logic                        rst,
  input  logic                        wr_clk,
  input  logic                        wr_en,
  input  logic [WRITE_DATA_WIDTH-1:0] din,
  output logic                        full,
  output logic                        prog_full,
  output logic                        wr_data_count,
  output logic                        overflow,
  output logic                        wr_rst_busy,
  output logic                        almost_full,
  output logic                        wr_ack,
  input  logic                        rd_clk,
  input  logic                        rd_en,
  output logic [READ_DATA_WIDTH-1:0]  dout,
  output logic                        empty,
  output logic                        prog_empty,
  output logic                        rd_data_count,
  output logic                        underflow,
  output logic                        rd_rst_busy,
  output logic                        almost_empty,
  output logic                        data_valid,
  input  logic                        injectsbiterr,
  input  logic                        injectdbiterr,
  output logic                        sbiterr,
  output logic                        dbiterr
);
  localparam int AW = $clog2(FIFO_WRITE_DEPTH);

  initial begin
    if (READ_MODE != "fwft" || WRITE_DATA_WIDTH != READ_DATA_WIDTH)
      $fatal(1, "xpm_fifo_async sim model: only fwft with equal widths");
  end

  function automatic logic [AW:0] b2g(input logic [AW:0] b);
    return b ^ (b >> 1);
  endfunction
  function automatic logic [AW:0] g2b(input logic [AW:0] g);
    logic [AW:0] b;
    b[AW] = g[AW];
    for (int i = AW - 1; i >= 0; i--) b[i] = b[i+1] ^ g[i];
    return b;
  endfunction

  logic [WRITE_DATA_WIDTH-1:0] mem [FIFO_WRITE_DEPTH];

  // write domain
  logic [AW:0] wptr, wgray, rgray_w;
  logic [AW:0] rptr, rgray, wgray_r;
  logic [AW:0] rsync [CDC_SYNC_STAGES];
  logic [2:0]  wrst_cnt;
  assign wr_rst_busy = rst | (wrst_cnt != 0);
  assign rgray_w     = rsync[CDC_SYNC_STAGES-1];
  assign full        = wr_rst_busy | ((wptr - g2b(rgray_w)) == (AW+1)'(FIFO_WRITE_DEPTH));

  always_ff @(posedge wr_clk) begin
    for (int i = 0; i < CDC_SYNC_STAGES; i++) rsync[i] <= (i == 0) ? rgray : rsync[i-1];
    if (rst) begin
      wptr     <= '0;
      wgray    <= '0;
      wrst_cnt <= 3'd5;
    end else begin
      if (wrst_cnt != 0) wrst_cnt <= wrst_cnt - 3'd1;
      if (wr_en) begin
        if (full) $fatal(1, "xpm_fifo_async sim model %m: write while full");
        mem[wptr[AW-1:0]] <= din;
        wptr  <= wptr + 1'b1;
        wgray <= b2g(wptr + 1'b1);
      end
    end
  end

  // read domain
  // (rptr, rgray, wgray_r declared with the write-domain pointers)
  logic [AW:0] wsync [CDC_SYNC_STAGES];
  logic [CDC_SYNC_STAGES:0] rrst_sync;
  assign rd_rst_busy = |rrst_sync;
  assign wgray_r     = wsync[CDC_SYNC_STAGES-1];
  assign empty       = rd_rst_busy | (rgray == wgray_r);
  assign dout        = mem[rptr[AW-1:0]];

  always_ff @(posedge rd_clk) begin
    for (int i = 0; i < CDC_SYNC_STAGES; i++) wsync[i] <= (i == 0) ? wgray : wsync[i-1];
    rrst_sync <= {rrst_sync[CDC_SYNC_STAGES-1:0], wr_rst_busy};
    if (rd_rst_busy) begin
      rptr  <= '0;
      rgray <= '0;
    end else if (rd_en) begin
      if (empty) $fatal(1, "xpm_fifo_async sim model %m: read while empty");
      rptr  <= rptr + 1'b1;
      rgray <= b2g(rptr + 1'b1);
    end
  end

  assign prog_full     = 1'b0;
  assign wr_data_count = 1'b0;
  assign overflow      = 1'b0;
  assign almost_full   = 1'b0;
  assign wr_ack        = 1'b0;
  assign prog_empty    = 1'b0;
  assign rd_data_count = 1'b0;
  assign underflow     = 1'b0;
  assign almost_empty  = 1'b0;
  assign data_valid    = 1'b0;
  assign sbiterr       = 1'b0;
  assign dbiterr       = 1'b0;
endmodule

module xpm_cdc_single #(
  parameter int DEST_SYNC_FF   = 4,
  parameter int INIT_SYNC_FF   = 0,
  parameter int SIM_ASSERT_CHK = 0,
  parameter int SRC_INPUT_REG  = 1
) (
  input  logic src_clk,
  input  logic src_in,
  input  logic dest_clk,
  output logic dest_out
);
  logic [DEST_SYNC_FF-1:0] sync = '0;
  always_ff @(posedge dest_clk) sync <= {sync[DEST_SYNC_FF-2:0], src_in};
  assign dest_out = sync[DEST_SYNC_FF-1];
endmodule
/* verilator lint_on UNDRIVEN */
/* verilator lint_on UNUSEDSIGNAL */
/* verilator lint_on UNUSEDPARAM */
