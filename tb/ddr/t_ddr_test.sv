// t_ddr_test: the standalone board test (fpga/ddr_test/ddr_test_top.sv) with
// the MIG replaced by ddr_model (tb/ddr/unisim_sim.sv). Decodes the 1 Mbaud
// UART report, requires a full pass with err=0 and the pass LED, then corrupts
// one stored beat in DDR3 and requires the next pass to report it on UART and
// the fail LED.
module t_ddr_test;
  logic clk = 1'b0;
  always #5 clk = ~clk;          // 100 MHz board clock

  logic       tx;
  logic [3:0] led;
  wire  [15:0] dq;
  wire  [1:0]  dqs_n, dqs_p;

  ddr_test_top #(.REPORT_BITS(16)) u_dut (
    .clk, .ck_rst(1'b1), .uart_rxd_out(tx), .led,
    .ddr3_addr(), .ddr3_ba(), .ddr3_cas_n(), .ddr3_ck_n(), .ddr3_ck_p(), .ddr3_cke(),
    .ddr3_ras_n(), .ddr3_reset_n(), .ddr3_we_n(), .ddr3_dq(dq), .ddr3_dqs_n(dqs_n),
    .ddr3_dqs_p(dqs_p), .ddr3_cs_n(), .ddr3_dm(), .ddr3_odt()
  );

  // ---- UART receiver, 1 us per bit ----
  string line = "";
  string last = "";
  int    nlines = 0;
  initial forever begin
    logic [7:0] b;
    @(negedge tx);
    #500;
    if (tx !== 1'b0) continue;
    for (int i = 0; i < 8; i++) begin #1000; b[i] = tx; end
    #1000;
    if (tx !== 1'b1) $fatal(1, "UART framing error");
    if (b == 8'h0A) begin
      last = line;
      line = "";
      nlines++;
      $display("[%0t] uart: %s", $time, last);
    end else if (b != 8'h0D) line = {line, string'(b)};
  end

  function automatic bit field(input string s, input string name, output longint unsigned v);
    for (int p = 0; p + name.len() < s.len(); p++)
      if (s.substr(p, p + name.len() - 1) == name) begin
        string h;
        int e;
        e = p + name.len();
        while (e < s.len() && s[e] != " ") e++;
        h = s.substr(p + name.len(), e - 1);
        v = 64'(unsigned'(h.atohex()));
        return 1;
      end
    return 0;
  endfunction

  task automatic wait_report(input int min_pass, output longint unsigned pass, output longint unsigned err,
                             output longint unsigned load);
    longint unsigned cal;
    forever begin
      @(nlines);
      if (!field(last, "cal=", cal) || !field(last, "pass=", pass) || !field(last, "err=", err) ||
          !field(last, "load=", load))
        $fatal(1, "malformed report '%s'", last);
      if (pass >= longint'(min_pass)) break;
    end
    if (cal != 1) $fatal(1, "report with cal=%0d after a pass", cal);
  endtask

  initial begin
    longint unsigned pass, err, load;
    wait_report(1, pass, err, load);
    if (err != 0) $fatal(1, "clean DDR3 reported err=%0d", err);
    if (led[0] !== 1'b1 || led[2] !== 1'b1 || led[3] !== 1'b0)
      $fatal(1, "LEDs %b after a clean pass, want cal + pass", led);
    $display("t_ddr_test: clean pass reported, one LOAD = %0d cycles", load);

    // corrupt chunk k = 20 between its STORE and its LOAD
    wait (u_dut.wphase == 1'b0 && u_dut.k == 6'd10);
    begin
      logic [23:0] beat;
      logic [127:0] d;
      beat = {8'((20 << 2) | (20 & 3)), 8'(20 * 73 + 11), 8'd5};
      d = u_dut.u_mig.u_model.peek(beat);
      u_dut.u_mig.u_model.poke(beat, ~d);
    end
    wait_report(int'(pass) + 1, pass, err, load);
    if (err != 32) $fatal(1, "one corrupted beat (32 blocks) reported err=%0d", err);
    if (led[3] !== 1'b1 || led[2] !== 1'b0) $fatal(1, "LEDs %b after a failing pass", led);
    $display("t_ddr_test: PASS (corrupted beat detected, err=%0d)", err);
    $finish;
  end

  initial begin
    #300_000_000;   // 300 ms with the 10-unit (10 ns) board clock period
    $fatal(1, "t_ddr_test timed out");
  end
endmodule
