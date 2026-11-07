// Second MMCM for the DDR3 controller (Tai page, Clocking).
//
//   clk_in   100 MHz board clock. Drive it from a BUFG when the core clock
//            MMCM shares the same pin (two MMCMs in different clock regions
//            cannot both take the IBUF output on dedicated routing).
//   clk_sys  166.67 MHz, MIG sys_clk_i ("No Buffer")
//   clk_ref  200 MHz,    MIG clk_ref_i ("No Buffer", IDELAYCTRL reference)
//
// VCO = 100 MHz x 10 = 1000 MHz; /6 = 166.67 MHz, /5 = 200 MHz.
/* verilator lint_off PINCONNECTEMPTY */  // unused MMCM outputs
module ddr_clk (
  input  logic clk_in,
  input  logic rst,       // active high, asynchronous MMCM reset
  output logic clk_sys,
  output logic clk_ref,
  output logic locked
);
  logic fb, sys_unbuf, ref_unbuf;

  MMCME2_BASE #(
    .BANDWIDTH        ("OPTIMIZED"),
    .CLKIN1_PERIOD    (10.0),
    .DIVCLK_DIVIDE    (1),
    .CLKFBOUT_MULT_F  (10.0),
    .CLKFBOUT_PHASE   (0.0),
    .CLKOUT0_DIVIDE_F (6.0),
    .CLKOUT1_DIVIDE   (5),
    .STARTUP_WAIT     ("FALSE")
  ) u_mmcm (
    .CLKIN1   (clk_in),
    .CLKFBIN  (fb),
    .CLKFBOUT (fb),
    .CLKFBOUTB(),
    .CLKOUT0  (sys_unbuf),
    .CLKOUT0B (),
    .CLKOUT1  (ref_unbuf),
    .CLKOUT1B (),
    .CLKOUT2  (),
    .CLKOUT2B (),
    .CLKOUT3  (),
    .CLKOUT3B (),
    .CLKOUT4  (),
    .CLKOUT5  (),
    .CLKOUT6  (),
    .LOCKED   (locked),
    .PWRDWN   (1'b0),
    .RST      (rst)
  );

  BUFG u_bufg_sys (.I(sys_unbuf), .O(clk_sys));
  BUFG u_bufg_ref (.I(ref_unbuf), .O(clk_ref));
endmodule
