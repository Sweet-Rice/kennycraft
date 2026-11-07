// 640x480 at 60 Hz, 25 MHz pixel clock (Tai page, VGA timing table).
//
//              Visible  Front porch  Sync  Back porch  Total
//   Horizontal   640        16        96       48       800 pixels
//   Vertical     480        10         2       33       525 lines
//
// hx/vy count from 0 at the first visible pixel. Every output describes the
// current (hx, vy) and is combinational from the counter registers, so all of
// them share the same latency. Sync pulses are active low.
module vga_timing (
    input  logic       clk_pix,
    input  logic       rst,           // synchronous, active high
    output logic [9:0] hx,
    output logic [9:0] vy,
    output logic       hsync_n,
    output logic       vsync_n,
    output logic       active,        // inside the 640x480 visible area
    output logic       vblank,        // vy >= 480
    output logic       vblank_start   // first pixel clock of vblank: hx = 0, vy = 480
);
    localparam int H_VISIBLE = 640;
    localparam int H_FRONT   = 16;
    localparam int H_SYNC    = 96;
    localparam int H_BACK    = 48;
    localparam int H_TOTAL   = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;   // 800

    localparam int V_VISIBLE = 480;
    localparam int V_FRONT   = 10;
    localparam int V_SYNC    = 2;
    localparam int V_BACK    = 33;
    localparam int V_TOTAL   = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;   // 525

    localparam logic [9:0] H_LAST       = 10'(H_TOTAL - 1);
    localparam logic [9:0] V_LAST       = 10'(V_TOTAL - 1);
    localparam logic [9:0] H_SYNC_START = 10'(H_VISIBLE + H_FRONT);
    localparam logic [9:0] H_SYNC_END   = 10'(H_VISIBLE + H_FRONT + H_SYNC);
    localparam logic [9:0] V_SYNC_START = 10'(V_VISIBLE + V_FRONT);
    localparam logic [9:0] V_SYNC_END   = 10'(V_VISIBLE + V_FRONT + V_SYNC);

    always_ff @(posedge clk_pix) begin
        if (rst) begin
            hx <= '0;
            vy <= '0;
        end else if (hx == H_LAST) begin
            hx <= '0;
            vy <= (vy == V_LAST) ? '0 : vy + 10'd1;
        end else begin
            hx <= hx + 10'd1;
        end
    end

    assign hsync_n      = !(hx >= H_SYNC_START && hx < H_SYNC_END);
    assign vsync_n      = !(vy >= V_SYNC_START && vy < V_SYNC_END);
    assign active       = (hx < 10'(H_VISIBLE)) && (vy < 10'(V_VISIBLE));
    assign vblank       = (vy >= 10'(V_VISIBLE));
    assign vblank_start = (hx == '0) && (vy == 10'(V_VISIBLE));
endmodule
