// Single-port block RAM with per-lane write enables and a registered read.
//
// W bits wide, D words deep, split into NBE write lanes of W/NBE bits each.
// Reads return mem[addr] one cycle after addr is presented (BRAM output
// latch). INIT_FILE, when not empty, is loaded with $readmemh; Vivado picks the
// file up through read_mem, Verilator from the working directory.
module memory_arr #(
    parameter int    W         = 32,
    parameter int    D         = 8192,
    parameter int    NBE       = W / 8,
    parameter string INIT_FILE = ""
) (
    input  logic                 clk,
    input  logic [NBE-1:0]       we,
    input  logic [$clog2(D)-1:0] addr,
    input  logic [W-1:0]         wdata,
    output logic [W-1:0]         rdata
);

    localparam int LW = W / NBE;

    (* ram_style = "block" *) logic [W-1:0] mem [D];

    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    always_ff @(posedge clk) begin
        rdata <= mem[addr];
        for (int i = 0; i < NBE; i++)
            if (we[i]) mem[addr][i*LW +: LW] <= wdata[i*LW +: LW];
    end

endmodule
