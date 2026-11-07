// Right shifter; sel is the fill bit (a's sign for SRA, 0 for SRL/SLL).
module barrel_shifter #(
    parameter int W = 32
) (
    input  logic [W-1:0]         a,
    input  logic [$clog2(W)-1:0] b,
    input  logic                 sel,
    output logic [W-1:0]         result
);

    logic [2*W-1:0] fill, shifted;

    assign fill    = {{W{sel}}, a};
    assign shifted = fill >> b;
    assign result  = shifted[W-1:0];

    /* verilator lint_off UNUSEDSIGNAL */
    logic [W-1:0] unused_hi;
    /* verilator lint_on UNUSEDSIGNAL */
    assign unused_hi = shifted[2*W-1:W];

endmodule
