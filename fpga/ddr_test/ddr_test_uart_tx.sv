// 8N1 transmitter, 1 Mbaud at 50 MHz.
module ddr_test_uart_tx #(
  parameter int CLKS_PER_BIT = 50
) (
  input  logic       clk,
  input  logic       rst,
  input  logic [7:0] data,
  input  logic       start,
  output logic       busy,
  output logic       tx
);
  logic [9:0] shift;
  logic [3:0] nbits;
  logic [$clog2(CLKS_PER_BIT)-1:0] cnt;

  assign tx = busy ? shift[0] : 1'b1;

  always_ff @(posedge clk) begin
    if (rst) begin
      busy  <= 1'b0;
      shift <= '1;
      nbits <= '0;
      cnt   <= '0;
    end else if (!busy) begin
      if (start) begin
        shift <= {1'b1, data, 1'b0};
        nbits <= '0;
        cnt   <= '0;
        busy  <= 1'b1;
      end
    end else if (cnt == ($clog2(CLKS_PER_BIT))'(CLKS_PER_BIT - 1)) begin
      cnt   <= '0;
      shift <= {1'b1, shift[9:1]};
      nbits <= nbits + 4'd1;
      if (nbits == 4'd9) busy <= 1'b0;
    end else begin
      cnt <= cnt + 1'b1;
    end
  end
endmodule
