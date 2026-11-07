// Standalone DDR3 chunk store test (P2b, KC_TARGET=ddr_test).
//
// Real path: tester ("core", 50 MHz) -> chunk_engine -> ddr_bridge (XPM async
// FIFOs) -> mig_ddr3 -> DDR3L. One world copy (copy 0) stands in for
// world_mem. Every pass, after calibration:
//   write phase  for each of 64 chunks spread over all 256 MB (cz = 4k + k%4
//                covers every 4 MB region, cx scrambled): fill its slot with
//                pattern P(key, i), STORE it.
//   read phase   for each chunk: fill the slot with ~P, LOAD it, time the
//                LOAD (core cycles from CHUNK_CMD to CHUNK_DONE), read all
//                8,192 blocks back and compare with P.
// key = k + 13 * pass, so every pass writes new data everywhere.
//
// LEDs: LD4 calibrated, LD5 heartbeat, LD6 pass (>= 1 pass, no error),
// LD7 fail (any mismatch). UART 1 Mbaud 8N1, about 4 times a second:
//   "DDR3 cal=H pass=HHHHHHHH err=HHHHHHHH load=HHHHHHHH fk=HH fi=HHHH\r\n"
// cal = calibrated, pass = completed passes, err = mismatching blocks,
// load = longest LOAD in 50 MHz cycles, fk/fi = chunk and block of the first
// mismatch.
/* verilator lint_off PINCONNECTEMPTY */  // unused vendor-primitive / MIG outputs
module ddr_test_top #(
  parameter int REPORT_BITS = 22    // a report line every 2^REPORT_BITS core cycles
) (
  input  logic        clk,          // 100 MHz, E3
  input  logic        ck_rst,       // RESET button, active low
  output logic        uart_rxd_out, // FPGA TX
  output logic [3:0]  led,
  output logic [13:0] ddr3_addr,
  output logic [2:0]  ddr3_ba,
  output logic        ddr3_cas_n,
  output logic [0:0]  ddr3_ck_n,
  output logic [0:0]  ddr3_ck_p,
  output logic [0:0]  ddr3_cke,
  output logic        ddr3_ras_n,
  output logic        ddr3_reset_n,
  output logic        ddr3_we_n,
  inout  wire  [15:0] ddr3_dq,
  inout  wire  [1:0]  ddr3_dqs_n,
  inout  wire  [1:0]  ddr3_dqs_p,
  output logic [0:0]  ddr3_cs_n,
  output logic [1:0]  ddr3_dm,
  output logic [0:0]  ddr3_odt
);
  // ---------------- clocks and resets ----------------
  logic clk100, clk_sys, clk_ref, ddr_locked;
  logic clk50, fb50, clk50_unbuf, locked50;

  BUFG u_bufg_in (.I(clk), .O(clk100));

  ddr_clk u_ddr_clk (
    .clk_in(clk100), .rst(1'b0), .clk_sys, .clk_ref, .locked(ddr_locked)
  );

  MMCME2_BASE #(
    .CLKIN1_PERIOD   (10.0),
    .DIVCLK_DIVIDE   (1),
    .CLKFBOUT_MULT_F (10.0),
    .CLKOUT0_DIVIDE_F(20.0)
  ) u_mmcm50 (
    .CLKIN1(clk100), .CLKFBIN(fb50), .CLKFBOUT(fb50), .CLKFBOUTB(),
    .CLKOUT0(clk50_unbuf), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
    .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
    .LOCKED(locked50), .PWRDWN(1'b0), .RST(1'b0)
  );
  BUFG u_bufg50 (.I(clk50_unbuf), .O(clk50));

  logic [3:0] rst_sync = '1;
  logic       rst;
  always_ff @(posedge clk50) rst_sync <= {rst_sync[2:0], ~(locked50 & ck_rst)};
  assign rst = rst_sync[3];

  // ---------------- MIG ----------------
  logic         ui_clk, ui_rst, init_calib_complete;
  logic [27:0]  app_addr;
  logic [2:0]   app_cmd;
  logic         app_en, app_rdy, app_wdf_end, app_wdf_wren, app_wdf_rdy;
  logic         app_rd_data_valid, app_rd_data_end;
  logic [127:0] app_wdf_data, app_rd_data;
  logic [15:0]  app_wdf_mask;

  mig_ddr3 u_mig (
    .ddr3_addr, .ddr3_ba, .ddr3_cas_n, .ddr3_ck_n, .ddr3_ck_p, .ddr3_cke,
    .ddr3_ras_n, .ddr3_reset_n, .ddr3_we_n, .ddr3_dq, .ddr3_dqs_n, .ddr3_dqs_p,
    .init_calib_complete, .ddr3_cs_n, .ddr3_dm, .ddr3_odt,
    .app_addr, .app_cmd, .app_en, .app_wdf_data, .app_wdf_end, .app_wdf_wren,
    .app_rd_data, .app_rd_data_end, .app_rd_data_valid, .app_rdy, .app_wdf_rdy,
    .app_sr_req(1'b0), .app_ref_req(1'b0), .app_zq_req(1'b0),
    .app_sr_active(), .app_ref_ack(), .app_zq_ack(),
    .ui_clk, .ui_clk_sync_rst(ui_rst), .app_wdf_mask,
    .sys_clk_i(clk_sys), .clk_ref_i(clk_ref), .sys_rst(ddr_locked & ck_rst)
  );

  // ---------------- bridge + engine ----------------
  logic         calib, cmd_valid, cmd_ready, cmd_store;
  logic [15:0]  cmd_chunk;
  logic         wr_valid, wr_ready, rd_valid, rd_ready;
  logic [127:0] wr_data, rd_data;

  ddr_bridge u_bridge (
    .clk(clk50), .rst, .calib, .cmd_valid, .cmd_ready, .cmd_store, .cmd_chunk,
    .wr_valid, .wr_ready, .wr_data, .rd_valid, .rd_ready, .rd_data,
    .ui_clk, .ui_rst, .init_calib_complete, .app_addr, .app_cmd, .app_en, .app_rdy,
    .app_wdf_data, .app_wdf_end, .app_wdf_wren, .app_wdf_mask, .app_wdf_rdy,
    .app_rd_data, .app_rd_data_valid
  );

  logic        reg_en, reg_we, reg_stall;
  logic [5:0]  reg_off;
  logic [31:0] reg_wdata, reg_rdata;
  logic        t_req, t_we;          // tester world access (the "core")
  logic [16:0] t_addr;
  logic [3:0]  t_wdata;
  logic        eng_we, eng_re;
  logic [16:0] eng_addr;
  logic [3:0]  eng_wdata, w_rdata;

  chunk_engine u_eng (
    .clk(clk50), .rst, .reg_en, .reg_we, .reg_off, .reg_wdata, .reg_rdata, .reg_stall,
    .slot_valid(), .win_x(), .win_z(), .vtrace_busy(1'b0), .core_world_req(t_req),
    .eng_we, .eng_re, .eng_addr, .eng_wdata, .eng_rdata(w_rdata),
    .calib, .cmd_valid, .cmd_ready, .cmd_store, .cmd_chunk,
    .wr_valid, .wr_ready, .wr_data, .rd_valid, .rd_ready, .rd_data
  );

  // world copy 0: 4 bits x 131,072, one port, 1-cycle read
  (* ram_style = "block" *) logic [3:0] wmem [131072];
  logic [16:0] w_addr;
  logic        w_we;
  logic [3:0]  w_wdata;
  assign w_addr  = t_req ? t_addr  : eng_addr;
  assign w_we    = t_req ? t_we    : eng_we;
  assign w_wdata = t_req ? t_wdata : eng_wdata;
  always_ff @(posedge clk50) begin
    if (w_we) wmem[w_addr] <= w_wdata;
    w_rdata <= wmem[w_addr];
  end

  // ---------------- tester ----------------
  typedef enum logic [2:0] {T_CALIB, T_FILL, T_CMD, T_WAIT, T_VERIFY, T_NEXT} tstate_t;
  tstate_t     ts;
  logic        wphase;          // 1 = write phase (STORE), 0 = read phase (LOAD)
  logic [5:0]  k;
  logic [13:0] i;               // 0 .. 8192
  logic [31:0] pass_cnt, err_cnt, load_max, done_exp, cyc, t0;
  logic [7:0]  fk;
  logic [15:0] fi;
  logic        have_err;
  logic        v_d;             // verify read issued last cycle
  logic [12:0] v_i;

  logic [7:0]  cx, cz;
  logic [6:0]  key;
  assign cx  = 8'(k * 73 + 11);
  assign cz  = {k, k[1:0]};
  assign key = {1'b0, k} + pass_cnt[6:0] * 7'd13;

  function automatic logic [3:0] pat(input logic [6:0] kk, input logic [12:0] ii);
    return ii[3:0] + ii[7:4] * 4'd3 + ii[11:8] * 4'd5 + {ii[12], 3'b000}
         + kk[3:0] * 4'd7 + {1'b0, kk[6:4]};
  endfunction

  // physical world address of block ii in the slot of chunk (x2, z2) mod 4
  function automatic logic [16:0] slot_addr(input logic [1:0] x2, input logic [1:0] z2,
                                            input logic [12:0] ii);
    return {ii[12:8], z2, ii[7:4], x2, ii[3:0]};
  endfunction

  assign t_req   = (ts == T_FILL) | (ts == T_VERIFY && !i[13]);
  assign t_we    = (ts == T_FILL);
  assign t_addr  = slot_addr(cx[1:0], cz[1:0], i[12:0]);
  assign t_wdata = wphase ? pat(key, i[12:0]) : ~pat(key, i[12:0]);

  assign reg_en    = (ts == T_CALIB) | (ts == T_CMD) | (ts == T_WAIT);
  assign reg_we    = (ts == T_CMD);
  assign reg_off   = (ts == T_CALIB) ? 6'h2C : (ts == T_CMD) ? 6'h30 : 6'h34;
  assign reg_wdata = {wphase, 15'd0, cz, cx};

  always_ff @(posedge clk50) begin
    if (rst) begin
      ts       <= T_CALIB;
      wphase   <= 1'b1;
      k        <= '0;
      i        <= '0;
      pass_cnt <= '0;
      err_cnt  <= '0;
      load_max <= '0;
      done_exp <= '0;
      cyc      <= '0;
      t0       <= '0;
      fk       <= '0;
      fi       <= '0;
      have_err <= 1'b0;
      v_d      <= 1'b0;
      v_i      <= '0;
    end else begin
      cyc <= cyc + 32'd1;
      v_d <= 1'b0;
      case (ts)
        T_CALIB: if (reg_rdata[0]) ts <= T_FILL;
        T_FILL: begin
          i <= i + 14'd1;
          if (i == 14'd8191) begin
            i  <= '0;
            ts <= T_CMD;
          end
        end
        T_CMD: if (!reg_stall) begin
          done_exp <= done_exp + 32'd1;
          t0       <= cyc;
          ts       <= T_WAIT;
        end
        T_WAIT: if (reg_rdata == done_exp) begin
          if (!wphase && (cyc - t0) > load_max) load_max <= cyc - t0;
          ts <= wphase ? T_NEXT : T_VERIFY;
        end
        T_VERIFY: begin
          if (!i[13]) begin
            v_d <= 1'b1;
            v_i <= i[12:0];
            i   <= i + 14'd1;
          end
          if (v_d && w_rdata != pat(key, v_i)) begin
            if (err_cnt != 32'hFFFF_FFFF) err_cnt <= err_cnt + 32'd1;
            if (!have_err) begin
              have_err <= 1'b1;
              fk       <= {2'b00, k};
              fi       <= {3'b000, v_i};
            end
          end
          if (!v_d && i[13]) begin
            i  <= '0;
            ts <= T_NEXT;
          end
        end
        T_NEXT: begin
          k  <= k + 6'd1;
          ts <= T_FILL;
          if (k == 6'd63) begin
            wphase <= ~wphase;
            if (!wphase) pass_cnt <= pass_cnt + 32'd1;
          end
        end
        default: ts <= T_CALIB;
      endcase
    end
  end

  // ---------------- report ----------------
  logic [25:0] hb;
  always_ff @(posedge clk50) hb <= hb + 26'd1;

  assign led[0] = calib;
  assign led[1] = hb[25];
  assign led[2] = (pass_cnt != 0) & ~have_err;
  assign led[3] = have_err;

  // Message template: each '#' is the next hex digit of `fields`, MSB first.
  localparam int MLEN = 67;
  localparam logic [8*MLEN-1:0] MSG =
    {"DDR3 cal=# pass=######## err=######## load=######## fk=## fi=####", 8'h0D, 8'h0A};
  localparam int NNIB = 31;
  logic [4*NNIB-1:0] fields, snap;
  assign fields = {3'b000, calib, pass_cnt, err_cnt, load_max, fk, fi};

  logic [6:0]  mpos;
  logic        sending;
  logic [REPORT_BITS-1:0] rep_timer;
  logic        tx_start, tx_busy;
  logic [7:0]  tx_byte, tmpl;
  logic [3:0]  nib;

  assign tmpl     = MSG[8 * (MLEN - 1 - int'(mpos)) +: 8];
  assign nib      = snap[4*NNIB-1 -: 4];
  assign tx_byte  = (tmpl != "#") ? tmpl
                  : (nib < 4'd10) ? 8'h30 + 8'(nib) : 8'h37 + 8'(nib);
  assign tx_start = sending & ~tx_busy;

  always_ff @(posedge clk50) begin
    if (rst) begin
      mpos      <= '0;
      sending   <= 1'b0;
      rep_timer <= '0;
      snap      <= '0;
    end else begin
      rep_timer <= rep_timer + 1'b1;
      if (!sending && rep_timer == '1) begin
        snap    <= fields;
        sending <= 1'b1;
        mpos    <= '0;
      end
      if (tx_start) begin
        if (tmpl == "#") snap <= snap << 4;
        if (mpos == 7'(MLEN - 1)) sending <= 1'b0;
        else mpos <= mpos + 7'd1;
      end
    end
  end

  ddr_test_uart_tx #(.CLKS_PER_BIT(50)) u_tx (
    .clk(clk50), .rst, .data(tx_byte), .start(tx_start), .busy(tx_busy), .tx(uart_rxd_out)
  );

  logic unused;
  assign unused = ^{eng_re, app_rd_data_end};
endmodule
