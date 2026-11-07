// Two-flop synchronizer for single-bit level signals crossing into clk.
// Multi-bit values never go through here; they cross as toggles or
// handshakes built from single synchronized bits.
module sync2 #(
    parameter logic RESET_VALUE = 1'b0
) (
    input  logic clk,
    input  logic rst,   // synchronous, active high, in the clk domain
    input  logic d,     // driven from another clock domain
    output logic q
);
    (* ASYNC_REG = "TRUE" *) logic meta;
    (* ASYNC_REG = "TRUE" *) logic sync;

    always_ff @(posedge clk) begin
        if (rst) begin
            meta <= RESET_VALUE;
            sync <= RESET_VALUE;
        end else begin
            meta <= d;
            sync <= meta;
        end
    end

    assign q = sync;
endmodule
