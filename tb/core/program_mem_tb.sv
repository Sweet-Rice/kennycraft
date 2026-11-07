`timescale 1ns / 1ps

// Verifies the program loaded by datapath -> fetch -> memory_arr via
// $readmemh("program.mem", mem).  This testbench intentionally never writes
// the DUT's instruction memory through hierarchy.
module program_mem_tb;

    localparam integer CLK_PERIOD_NS = 10;
    localparam integer BAUD_DIV      = 868;
    localparam integer UART_BIT_NS   = BAUD_DIV * CLK_PERIOD_NS;
    localparam integer BYTE_COUNT    = 15;

    logic        clk = 1'b0;
    logic        rst = 1'b1;
    logic        tx;
    logic        illegal_out;
    logic [31:0] if_pc;
    logic [7:0]  rx_byte = 8'h00;
    integer      rx_count = 0;
    integer      start_count = 0;
    integer      bit_index;
    logic [31:0] previous_pc = 32'h8000_0000;
    logic        saw_loop_jump = 1'b0;

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    datapath dut (
        .clk         (clk),
        .rst         (rst),
        .tx          (tx),
        .illegal_out (illegal_out),
        .if_pc       (if_pc)
    );

    function automatic logic [7:0] expected_byte(input integer index);
        case (index)
            0:  expected_byte = 8'h48; // H
            1:  expected_byte = 8'h65; // e
            2:  expected_byte = 8'h6c; // l
            3:  expected_byte = 8'h6c; // l
            4:  expected_byte = 8'h6f; // o
            5:  expected_byte = 8'h2c; // ,
            6:  expected_byte = 8'h20; // space
            7:  expected_byte = 8'h77; // w
            8:  expected_byte = 8'h6f; // o
            9:  expected_byte = 8'h72; // r
            10: expected_byte = 8'h6c; // l
            11: expected_byte = 8'h64; // d
            12: expected_byte = 8'h21; // !
            13: expected_byte = 8'h0d; // carriage return
            14: expected_byte = 8'h0a; // line feed
            default: expected_byte = 8'hxx;
        endcase
    endfunction

    task automatic fail(input string reason);
        begin
            $fatal(1, "FAIL: %s", reason);
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
    end

    // Check the UART request contract and retain the loop-back transition for
    // both automated checking and waveform inspection.
    always @(posedge clk) begin
        if (rst) begin
            start_count  <= 0;
            previous_pc  <= 32'h8000_0000;
            saw_loop_jump <= 1'b0;
        end else begin
            if (illegal_out !== 1'b0)
                fail("illegal_out asserted or became unknown");

            if (dut.lsu_d.start) begin
                if (dut.lsu_d.busy !== 1'b0)
                    fail("UART start occurred while busy was not low");
                if (start_count >= BYTE_COUNT)
                    fail("more than 15 UART starts were observed");
                start_count <= start_count + 1;
            end

            if ((previous_pc == 32'h8000_00f4) &&
                (if_pc == 32'h8000_0004))
                saw_loop_jump <= 1'b1;

            previous_pc <= if_pc;
        end
    end

    // Decode each 8-N-1 frame at the center of its bits.  The displayed
    // characters are the exact bytes observed on tx.
    initial begin
        wait (rst === 1'b0);
        forever begin
            @(negedge tx);
            #(UART_BIT_NS / 2);
            if (tx !== 1'b0)
                fail("invalid UART start bit");

            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                #(UART_BIT_NS);
                rx_byte[bit_index] = tx;
            end

            #(UART_BIT_NS);
            if (tx !== 1'b1)
                fail("invalid UART stop bit");
            if (rx_count >= BYTE_COUNT)
                fail("more than 15 UART bytes were received");
            if (rx_byte !== expected_byte(rx_count))
                $fatal(1, "FAIL: UART byte %0d was 0x%02h, expected 0x%02h",
                       rx_count, rx_byte, expected_byte(rx_count));

            // XSim on Windows renders both a literal CR and LF as separate
            // console newlines.  Suppress the CR display and let LF emit the
            // single CRLF used in the transcript; both bytes were still
            // sampled and checked above.
            if (rx_byte == 8'h0d) begin
                // Defer the visible line ending until the following LF.
            end else if (rx_byte == 8'h0a) begin
                $display("");
            end else begin
                $write("%c", rx_byte);
            end
            rx_count = rx_count + 1;

            if (rx_count == BYTE_COUNT) begin
                if (start_count != BYTE_COUNT)
                    $fatal(1, "FAIL: observed %0d UART starts, expected 15",
                           start_count);
                if (!saw_loop_jump)
                    fail("PC did not jump from 0x800000f4 to 0x80000004");
                if (illegal_out !== 1'b0)
                    fail("illegal_out was not low at completion");
                $display("PASS: program.mem transmitted 15 correct bytes");
                $finish;
            end
        end
    end

    initial begin
        #2_000_000;
        $fatal(1,
               "FAIL: timeout after 2 ms (starts=%0d, received=%0d, pc=0x%08h)",
               start_count, rx_count, if_pc);
    end

endmodule
