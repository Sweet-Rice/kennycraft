// Register file: D entries of W bits, one write port, two asynchronous read
// ports (LUT RAM). x0 is not forced to zero here, so inference stays plain;
// the core masks reads of x0 and never writes it. D is a parameter so later
// stages can stack per-context register sets ({ctx, reg} addressing).
module reg_module #(
    parameter int W = 32,
    parameter int D = 32
) (
    input  logic                 clk,
    input  logic                 we,
    input  logic [$clog2(D)-1:0] wr,
    input  logic [$clog2(D)-1:0] rd1,
    input  logic [$clog2(D)-1:0] rd2,
    input  logic [W-1:0]         d_in,
    output logic [W-1:0]         d_out1,
    output logic [W-1:0]         d_out2
);

    // Without the attribute Vivado folds the core's ID->EX operand registers
    // into a BRAM read, whose clock-to-out lands on the branch/ALU path.
    (* ram_style = "distributed" *) logic [W-1:0] regs [D];

    always_ff @(posedge clk) begin
        if (we) regs[wr] <= d_in;
    end

    assign d_out1 = regs[rd1];
    assign d_out2 = regs[rd2];

endmodule
