// 8N1 UART. 1 Mbaud at the 50 MHz core clock: exactly CLK_HZ / BAUD = 50
// clocks per bit (Tai page, Stage 0 additions).
//
// TX. tx_start loads one byte when tx_busy is low (it is ignored while busy).
// tx_busy stays high for the whole 10-bit frame.
//
// RX. The line is synchronized with two flops, a falling edge starts a frame,
// bits are sampled in the middle of each bit time, and a byte with a valid
// stop bit is pushed into a RX_DEPTH-entry FIFO. A byte that arrives while the
// FIFO is full is dropped. rx_data shows the FIFO head while rx_avail is high;
// rx_pop removes it.
module uart #(
    parameter int CLK_HZ   = 50_000_000,
    parameter int BAUD     = 1_000_000,
    parameter int RX_DEPTH = 16
) (
    input  logic       clk,
    input  logic       rst,
    // TX
    input  logic [7:0] tx_data,
    input  logic       tx_start,
    output logic       tx_busy,
    output logic       tx,
    // RX
    input  logic       rx,
    input  logic       rx_pop,
    output logic       rx_avail,
    output logic [7:0] rx_data
);

    localparam int DIV = CLK_HZ / BAUD;
    localparam int CW  = $clog2(DIV);
    localparam int PW  = $clog2(RX_DEPTH);

    if (CLK_HZ % BAUD != 0) begin : g_div_check
        $error("uart: CLK_HZ must be an exact multiple of BAUD");
    end

    // ------------------------------------------------------------------
    // TX
    // ------------------------------------------------------------------
    logic [CW-1:0] tx_cnt;
    logic [3:0]    tx_bits;   // bits left in the frame
    logic [9:0]    tx_shift;  // {stop, data[7:0], start}, LSB first

    assign tx      = tx_shift[0];
    assign tx_busy = (tx_bits != 4'd0);

    always_ff @(posedge clk) begin
        if (rst) begin
            tx_cnt   <= '0;
            tx_bits  <= 4'd0;
            tx_shift <= '1;
        end else if (!tx_busy) begin
            if (tx_start) begin
                tx_shift <= {1'b1, tx_data, 1'b0};
                tx_bits  <= 4'd10;
                tx_cnt   <= '0;
            end
        end else if (tx_cnt == CW'(DIV - 1)) begin
            tx_cnt   <= '0;
            tx_shift <= {1'b1, tx_shift[9:1]};
            tx_bits  <= tx_bits - 4'd1;
        end else begin
            tx_cnt <= tx_cnt + 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // RX
    // ------------------------------------------------------------------
    logic [1:0]    rx_sync;
    logic          rx_s;
    logic          rx_active;
    logic [CW-1:0] rx_cnt;
    logic [3:0]    rx_bits;   // 0 start, 1..8 data, 9 stop
    logic [7:0]    rx_shift;
    logic          rx_push;

    assign rx_s = rx_sync[1];

    always_ff @(posedge clk) begin
        if (rst) rx_sync <= 2'b11;
        else     rx_sync <= {rx_sync[0], rx};
    end

    always_ff @(posedge clk) begin
        rx_push <= 1'b0;
        if (rst) begin
            rx_active <= 1'b0;
            rx_cnt    <= '0;
            rx_bits   <= 4'd0;
            rx_shift  <= '0;
        end else if (!rx_active) begin
            if (!rx_s) begin
                // Falling edge: wait half a bit to land in the middle of start.
                rx_active <= 1'b1;
                rx_cnt    <= CW'(DIV / 2 - 1);
                rx_bits   <= 4'd0;
            end
        end else if (rx_cnt != '0) begin
            rx_cnt <= rx_cnt - 1'b1;
        end else begin
            rx_cnt <= CW'(DIV - 1);
            if (rx_bits == 4'd0) begin
                if (rx_s) rx_active <= 1'b0;  // glitch, not a start bit
            end else if (rx_bits == 4'd9) begin
                rx_active <= 1'b0;
                rx_push   <= rx_s;             // drop frames without a stop bit
            end else begin
                rx_shift <= {rx_s, rx_shift[7:1]};
            end
            rx_bits <= rx_bits + 4'd1;
        end
    end

    // ------------------------------------------------------------------
    // RX FIFO
    // ------------------------------------------------------------------
    logic [7:0]  fifo [RX_DEPTH];
    logic [PW:0] wptr, rptr;
    logic        full;

    assign rx_avail = (wptr != rptr);
    assign full     = (wptr[PW] != rptr[PW]) && (wptr[PW-1:0] == rptr[PW-1:0]);
    assign rx_data  = fifo[rptr[PW-1:0]];

    always_ff @(posedge clk) begin
        if (rx_push && !full) fifo[wptr[PW-1:0]] <= rx_shift;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            wptr <= '0;
            rptr <= '0;
        end else begin
            if (rx_push && !full)    wptr <= wptr + 1'b1;
            if (rx_pop && rx_avail)  rptr <= rptr + 1'b1;
        end
    end

endmodule
