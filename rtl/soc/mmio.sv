// MMIO register block at 0x5000_0000 (Shared page, Interfaces, MMIO).
//
// Bus. req is held until ready; the access takes effect once, in the cycle
// where req && ready, and read data is valid in rdata the following cycle.
// Every register here accepts at once. DDR_STATUS .. WIN_ORIGIN (0x2C..0x3C)
// belong to the chunk engine (P2b, rtl/ddr/chunk_engine.sv) and go out on the
// ddr_reg_* port: ddr_reg_en marks an access, ddr_reg_rdata is combinational
// and ddr_reg_stall (CHUNK_CMD write with the queue full) holds the core, with
// the access held stable, until the engine takes it. Offsets are decoded from
// addr[7:2]; offsets with no register read 0 and ignore writes.
//
// ERR and ERR_PC are not cleared by rst. The error halt lasts until reset
// (the core leaves HALT and the error LED goes out), but the cause stays
// readable afterwards until software writes 1 to clear it; otherwise the
// write-1-to-clear access could never be observed. They power up as 0.
//
// Register writes use wdata as the LSU drives it (byte and halfword stores are
// replicated across the word), so SB/SH/SW to a register offset all work.
module mmio
    import kc_isa_pkg::*;
(
    input  logic        clk,
    input  logic        rst,

    // Core bus (region 0x5)
    input  logic        req,
    input  logic        we,
    input  logic [7:2]  addr,       // byte offset, word aligned
    input  logic [31:0] wdata,
    output logic        ready,
    output logic [31:0] rdata,

    // Errors from the core: one-cycle set pulses per ERR bit and the PC to latch
    input  logic [ERR_WIDTH-1:0] err_set,
    input  logic [31:0]          err_pc_in,

    // UART
    output logic        uart_tx_start,
    output logic [7:0]  uart_tx_data,
    input  logic        uart_tx_busy,
    output logic        uart_rx_pop,
    input  logic        uart_rx_avail,
    input  logic [7:0]  uart_rx_data,

    // Display (P1 core-side port names)
    output logic        swap_req,
    input  logic        swap_pending,
    input  logic        vblank,
    input  logic [31:0] frame_count,
    output logic        fb_mode,

    // Board LEDs
    output logic [7:0]  leds,

    // Chunk engine registers 0x2C..0x3C (P2b port names)
    output logic        ddr_reg_en,
    output logic        ddr_reg_we,
    output logic [5:0]  ddr_reg_off,
    output logic [31:0] ddr_reg_wdata,
    input  logic [31:0] ddr_reg_rdata,
    input  logic        ddr_reg_stall
);

    logic [7:0]  off;
    logic        is_ddr;
    logic        acc;       // local register access accepted this cycle
    logic [31:0] rdata_q;   // registered read data

    logic [31:0]          cycles;
    logic [ERR_WIDTH-1:0] err    = '0;
    logic [ERR_WIDTH-1:0] err_clr;
    logic [31:0]          err_pc = '0;

    assign off    = {addr, 2'b00};
    assign is_ddr = (off >= MMIO_DDR_STATUS) && (off <= MMIO_WIN_ORIGIN);
    assign acc    = req && !is_ddr;

    assign ddr_reg_en    = req && is_ddr;
    assign ddr_reg_we    = we;
    assign ddr_reg_off   = off[5:0];
    assign ddr_reg_wdata = wdata;

    assign ready = req && !(is_ddr && ddr_reg_stall);
    assign rdata = rdata_q;

    // Write side effects
    assign swap_req      = acc && we && (off == MMIO_FB_SWAP) && wdata[0];
    assign uart_tx_start = acc && we && (off == MMIO_UART_TX);
    assign uart_tx_data  = wdata[7:0];
    assign uart_rx_pop   = acc && !we && (off == MMIO_UART_RX);
    assign err_clr       = (acc && we && (off == MMIO_ERR)) ? wdata[ERR_WIDTH-1:0] : '0;

    always_ff @(posedge clk) begin
        if (rst) begin
            cycles  <= '0;
            leds    <= '0;
            fb_mode <= 1'b0;
        end else begin
            cycles <= cycles + 32'd1;
            if (acc && we) begin
                if (off == MMIO_LEDS)    leds    <= wdata[7:0];
                if (off == MMIO_FB_MODE) fb_mode <= wdata[0];
            end
        end
    end

    // ERR: write 1 to clear; a new error in the same cycle wins.
    always_ff @(posedge clk) begin
        err <= (err & ~err_clr) | err_set;
        if (err_set != '0) err_pc <= err_pc_in;
    end

    // Read data, registered so it is valid the cycle after the access
    always_ff @(posedge clk) begin
        if (rst) begin
            rdata_q <= '0;
        end else if (req && ready) begin
            rdata_q <= '0;
            if (is_ddr) begin
                if (!we) rdata_q <= ddr_reg_rdata;
            end else if (!we) begin
                unique case (off)
                    MMIO_FB_SWAP:     rdata_q <= {31'b0, swap_pending};
                    MMIO_FRAME_COUNT: rdata_q <= frame_count;
                    MMIO_VSYNC:       rdata_q <= {31'b0, vblank};
                    MMIO_CYCLES:      rdata_q <= cycles;
                    MMIO_UART_RX:     rdata_q <= {24'b0, uart_rx_avail ? uart_rx_data : 8'h00};
                    MMIO_UART_STATUS: rdata_q <= {30'b0, uart_tx_busy, uart_rx_avail};
                    MMIO_ERR:         rdata_q <= {{(32-ERR_WIDTH){1'b0}}, err};
                    MMIO_ERR_PC:      rdata_q <= err_pc;
                    MMIO_FB_MODE:     rdata_q <= {31'b0, fb_mode};
                    default:          rdata_q <= '0;  // write-only and unused offsets
                endcase
            end
        end
    end

endmodule
