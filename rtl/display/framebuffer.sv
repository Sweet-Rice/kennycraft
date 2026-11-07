// Two 320x240 byte framebuffers (76,800 B each) in true dual-clock block RAM
// (Tai page, Memory & Display; 38 BRAM36 for the pair).
//
// Port A (clk_a, 50 MHz core side) reads and writes the buffer picked by
// sel_a; the display passes the back buffer there. Port B (clk_b, 25 MHz) is
// the read-only scan-out port on the buffer picked by sel_b, the front buffer.
// Both ports have one cycle of read latency; sel is registered alongside the
// address so the output mux follows the buffer that was actually read.
// Writes at addr_a >= 76,800 are dropped. Reads there return unspecified data.
module framebuffer (
    // Port A, core side
    input  logic        clk_a,
    input  logic        en_a,
    input  logic        we_a,
    input  logic        sel_a,
    input  logic [16:0] addr_a,
    input  logic [7:0]  wdata_a,
    output logic [7:0]  rdata_a,
    // Port B, scan-out side
    input  logic        clk_b,
    input  logic        sel_b,
    input  logic [16:0] addr_b,
    output logic [7:0]  rdata_b
);
    localparam int FB_BYTES = 320 * 240;   // 76,800

    logic       in_range_a;
    logic       sel_a_q;
    logic       sel_b_q;
    logic [7:0] rd_a [2];
    logic [7:0] rd_b [2];

    assign in_range_a = (addr_a < 17'(FB_BYTES));

    for (genvar b = 0; b < 2; b++) begin : g_buf
        (* ram_style = "block" *) logic [7:0] mem [FB_BYTES];

        logic en_a_b;
        assign en_a_b = en_a && (sel_a == 1'(b));

        always_ff @(posedge clk_a) begin
            if (en_a_b) begin
                if (we_a && in_range_a) mem[addr_a] <= wdata_a;
                rd_a[b] <= mem[addr_a];
            end
        end

        always_ff @(posedge clk_b) begin
            rd_b[b] <= mem[addr_b];
        end
    end

    always_ff @(posedge clk_a) if (en_a) sel_a_q <= sel_a;
    always_ff @(posedge clk_b) sel_b_q <= sel_b;

    assign rdata_a = rd_a[sel_a_q];
    assign rdata_b = rd_b[sel_b_q];
endmodule
