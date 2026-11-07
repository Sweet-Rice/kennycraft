// Clock-domain bridge between the chunk engine (50 MHz core clock) and the
// MIG native user interface (ui_clk, about 83 MHz).
//
// Three XPM async FIFOs cross the domains (Tai page, DDR3 Chunk Store):
//   cmd   core -> ui   {store, chunk[15:0]}, one entry per chunk command
//   wdata core -> ui   128-bit beats of a STORE, 512 deep (block RAM)
//   rdata ui -> core   128-bit beats of a LOAD, 512 deep (block RAM)
// A ui-side FSM expands one chunk command into 256 MIG commands. Chunk c lives
// at DDR3 byte address c * 4096 (c = cz * 256 + cx); MIG app_addr counts 16-bit
// words, so beat b of chunk c is app_addr = {c, b, 3'b000}.
//
// The chunk engine runs one command at a time to completion, so the rdata
// FIFO never holds more than 256 beats and needs no back-pressure to MIG.
/* verilator lint_off PINCONNECTEMPTY */  // unused XPM FIFO outputs
module ddr_bridge (
  // core clock domain
  input  logic         clk,
  input  logic         rst,
  output logic         calib,        // init_calib_complete, synchronized to clk
  input  logic         cmd_valid,
  output logic         cmd_ready,
  input  logic         cmd_store,    // 0 = LOAD (DDR3 -> engine), 1 = STORE
  input  logic [15:0]  cmd_chunk,
  input  logic         wr_valid,
  output logic         wr_ready,
  input  logic [127:0] wr_data,
  output logic         rd_valid,
  input  logic         rd_ready,
  output logic [127:0] rd_data,
  // MIG user interface (ui_clk domain)
  input  logic         ui_clk,
  input  logic         ui_rst,
  input  logic         init_calib_complete,
  output logic [27:0]  app_addr,
  output logic [2:0]   app_cmd,
  output logic         app_en,
  input  logic         app_rdy,
  output logic [127:0] app_wdf_data,
  output logic         app_wdf_end,
  output logic         app_wdf_wren,
  output logic [15:0]  app_wdf_mask,
  input  logic         app_wdf_rdy,
  input  logic [127:0] app_rd_data,
  input  logic         app_rd_data_valid
);
  localparam logic [2:0] CMD_WRITE = 3'b000;
  localparam logic [2:0] CMD_READ  = 3'b001;

  // ---- calibration status into the core domain ----
  xpm_cdc_single #(
    .DEST_SYNC_FF  (3),
    .INIT_SYNC_FF  (0),
    .SIM_ASSERT_CHK(0),
    .SRC_INPUT_REG (0)
  ) u_calib_sync (
    .src_clk (1'b0),
    .src_in  (init_calib_complete),
    .dest_clk(clk),
    .dest_out(calib)
  );

  // Core-side FIFOs stay in reset until calibration is done, so the ui clock
  // is running whenever XPM resets them.
  logic core_fifo_rst;
  assign core_fifo_rst = rst | ~calib;

  // ---- command FIFO ----
  logic        cmd_full, cmd_wr_busy, cmd_empty, cmd_rd_busy, cmd_pop;
  logic [16:0] cmd_dout;

  xpm_fifo_async #(
    .FIFO_MEMORY_TYPE ("distributed"),
    .FIFO_WRITE_DEPTH (16),
    .WRITE_DATA_WIDTH (17),
    .READ_DATA_WIDTH  (17),
    .READ_MODE        ("fwft"),
    .FIFO_READ_LATENCY(0),
    .CDC_SYNC_STAGES  (2),
    .USE_ADV_FEATURES ("0000")
  ) u_cmd_fifo (
    .sleep(1'b0), .rst(core_fifo_rst),
    .wr_clk(clk), .wr_en(cmd_valid & cmd_ready), .din({cmd_store, cmd_chunk}),
    .full(cmd_full), .prog_full(), .wr_data_count(), .overflow(), .wr_rst_busy(cmd_wr_busy),
    .almost_full(), .wr_ack(),
    .rd_clk(ui_clk), .rd_en(cmd_pop), .dout(cmd_dout), .empty(cmd_empty), .prog_empty(),
    .rd_data_count(), .underflow(), .rd_rst_busy(cmd_rd_busy), .almost_empty(), .data_valid(),
    .injectsbiterr(1'b0), .injectdbiterr(1'b0), .sbiterr(), .dbiterr()
  );
  assign cmd_ready = ~cmd_full & ~cmd_wr_busy & ~core_fifo_rst;

  // ---- write data FIFO ----
  logic         wf_full, wf_wr_busy, wf_empty, wf_rd_busy, wf_pop;
  logic [127:0] wf_dout;

  xpm_fifo_async #(
    .FIFO_MEMORY_TYPE ("block"),
    .FIFO_WRITE_DEPTH (512),
    .WRITE_DATA_WIDTH (128),
    .READ_DATA_WIDTH  (128),
    .READ_MODE        ("fwft"),
    .FIFO_READ_LATENCY(0),
    .CDC_SYNC_STAGES  (2),
    .USE_ADV_FEATURES ("0000")
  ) u_wdata_fifo (
    .sleep(1'b0), .rst(core_fifo_rst),
    .wr_clk(clk), .wr_en(wr_valid & wr_ready), .din(wr_data),
    .full(wf_full), .prog_full(), .wr_data_count(), .overflow(), .wr_rst_busy(wf_wr_busy),
    .almost_full(), .wr_ack(),
    .rd_clk(ui_clk), .rd_en(wf_pop), .dout(wf_dout), .empty(wf_empty), .prog_empty(),
    .rd_data_count(), .underflow(), .rd_rst_busy(wf_rd_busy), .almost_empty(), .data_valid(),
    .injectsbiterr(1'b0), .injectdbiterr(1'b0), .sbiterr(), .dbiterr()
  );
  assign wr_ready = ~wf_full & ~wf_wr_busy & ~core_fifo_rst;

  // ---- read data FIFO ----
  logic rf_full, rf_wr_busy, rf_empty, rf_rd_busy;

  xpm_fifo_async #(
    .FIFO_MEMORY_TYPE ("block"),
    .FIFO_WRITE_DEPTH (512),
    .WRITE_DATA_WIDTH (128),
    .READ_DATA_WIDTH  (128),
    .READ_MODE        ("fwft"),
    .FIFO_READ_LATENCY(0),
    .CDC_SYNC_STAGES  (2),
    .USE_ADV_FEATURES ("0000")
  ) u_rdata_fifo (
    .sleep(1'b0), .rst(ui_rst),
    .wr_clk(ui_clk), .wr_en(app_rd_data_valid & ~rf_wr_busy), .din(app_rd_data),
    .full(rf_full), .prog_full(), .wr_data_count(), .overflow(), .wr_rst_busy(rf_wr_busy),
    .almost_full(), .wr_ack(),
    .rd_clk(clk), .rd_en(rd_valid & rd_ready), .dout(rd_data), .empty(rf_empty), .prog_empty(),
    .rd_data_count(), .underflow(), .rd_rst_busy(rf_rd_busy), .almost_empty(), .data_valid(),
    .injectsbiterr(1'b0), .injectdbiterr(1'b0), .sbiterr(), .dbiterr()
  );
  assign rd_valid = ~rf_empty & ~rf_rd_busy;

  // ---- ui-side command FSM ----
  typedef enum logic [1:0] {U_IDLE, U_READ, U_WRITE} ustate_t;
  ustate_t     ust;
  logic [15:0] u_chunk;
  logic [7:0]  u_beat;
  logic        w_cmd_done, w_dat_done;   // this beat's command / data already taken by MIG

  logic cmd_have, wf_have, cmd_take, dat_take, beat_done;
  assign cmd_have  = ~cmd_empty & ~cmd_rd_busy;
  assign wf_have   = ~wf_empty & ~wf_rd_busy;
  assign cmd_pop   = (ust == U_IDLE) & cmd_have & init_calib_complete;

  assign app_addr     = {1'b0, u_chunk, u_beat, 3'b000};
  assign app_cmd      = (ust == U_WRITE) ? CMD_WRITE : CMD_READ;
  assign app_en       = (ust == U_READ) | ((ust == U_WRITE) & wf_have & ~w_cmd_done);
  assign app_wdf_wren = (ust == U_WRITE) & wf_have & ~w_dat_done;
  assign app_wdf_end  = app_wdf_wren;
  assign app_wdf_data = wf_dout;
  assign app_wdf_mask = '0;

  assign cmd_take  = app_en & app_rdy;
  assign dat_take  = app_wdf_wren & app_wdf_rdy;
  assign beat_done = (ust == U_READ) ? cmd_take
                   : (w_cmd_done | cmd_take) & (w_dat_done | dat_take) & (ust == U_WRITE);
  assign wf_pop    = (ust == U_WRITE) & beat_done;

  always_ff @(posedge ui_clk) begin
    if (ui_rst) begin
      ust        <= U_IDLE;
      u_chunk    <= '0;
      u_beat     <= '0;
      w_cmd_done <= 1'b0;
      w_dat_done <= 1'b0;
    end else begin
      case (ust)
        U_IDLE: if (cmd_pop) begin
          ust     <= cmd_dout[16] ? U_WRITE : U_READ;
          u_chunk <= cmd_dout[15:0];
          u_beat  <= '0;
        end
        default: begin
          if (beat_done) begin
            w_cmd_done <= 1'b0;
            w_dat_done <= 1'b0;
            u_beat     <= u_beat + 8'd1;
            if (u_beat == 8'hFF) ust <= U_IDLE;
          end else begin
            if (cmd_take) w_cmd_done <= 1'b1;
            if (dat_take) w_dat_done <= 1'b1;
          end
        end
      endcase
    end
  end

  // rf_full can only rise if the engine contract (one command at a time) is broken.
  logic unused;
  assign unused = rf_full;
endmodule
