// Adder/subtractor with signed and unsigned less-than flags.
module addsub #(
    parameter int W = 32
) (
    input  logic [W-1:0] a,
    input  logic [W-1:0] b,
    input  logic         sub,
    output logic [W-1:0] sum,
    output logic         lt,
    output logic         ltu
);

    logic [W-1:0] b_in;
    logic         cout, v;

    assign b_in        = b ^ {W{sub}};
    assign {cout, sum} = {1'b0, a} + {1'b0, b_in} + {{W{1'b0}}, sub};

    assign ltu = ~cout;
    assign v   = (a[W-1] ^ sum[W-1]) & ~(a[W-1] ^ b[W-1] ^ sub);
    assign lt  = sum[W-1] ^ v;

endmodule
