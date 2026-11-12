// dmem_tb.v
// Self-checking testbench for dmem.v
// Tests: write-then-read-back, wide port correctness, boundary addresses,
//        all LANES words verified independently.
// Prints PASS or FAIL with expected vs actual.
// Part of: SIMD Vector Processing Unit, LANE BREAKERS
// Owner: Jagruthi Pulumati (Role 3, Control and Memory)

`timescale 1ns/1ps

module dmem_tb;

    // Parameters under test
    parameter LANES  = 4;
    parameter DW     = 32;
    parameter DEPTH  = 16;
    parameter ADDR_W = 4;

    // DUT signals
    reg                   clk;
    reg                   we;
    reg  [31:0]           addr;
    reg  [LANES*DW-1:0]   wdata;
    wire [LANES*DW-1:0]   rdata;

    // Instantiate DUT
    dmem #(
        .LANES  (LANES),
        .DW     (DW),
        .DEPTH  (DEPTH),
        .ADDR_W (ADDR_W)
    ) dut (
        .clk   (clk),
        .we    (we),
        .addr  (addr),
        .wdata (wdata),
        .rdata (rdata)
    );

    // Clock: 10 ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // Test infrastructure
    integer pass_count = 0;
    integer fail_count = 0;

    task check;
        input [LANES*DW-1:0] got;
        input [LANES*DW-1:0] exp;
        input [127:0]        label;
        begin
            if (got === exp) begin
                $display("  PASS: %s", label);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: %s", label);
                $display("        expected = %h", exp);
                $display("        actual   = %h", got);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Helper: write one lane-group and read it back
    task write_read;
        input [31:0]         a;
        input [LANES*DW-1:0] d;
        input [127:0]        label;
        begin
            // Write on rising edge
            @(negedge clk);
            we = 1; addr = a; wdata = d;
            @(posedge clk); #1;
            we = 0;
            // Read combinationally (async)
            addr = a;
            #1;
            check(rdata, d, label);
        end
    endtask

    integer i;
    reg [LANES*DW-1:0] expected;

    initial begin
        $display("=== dmem_tb ===");
        we = 0; addr = 0; wdata = 0;

        // ---- Test 1: basic write then read ----
        $display("-- T1: basic write/read (addr=0) --");
        write_read(32'd0, 128'hDEADBEEF_CAFEBABE_12345678_ABCDABCD, "addr=0 write/read");

        // ---- Test 2: different address ----
        $display("-- T2: addr=5 write/read --");
        write_read(32'd5, 128'hAABBCCDD_11223344_55667788_99AABBCC, "addr=5 write/read");

        // ---- Test 3: address 0 not clobbered by addr=5 write ----
        $display("-- T3: addr=0 not clobbered --");
        @(negedge clk); we = 0; addr = 32'd0; #1;
        check(rdata, 128'hDEADBEEF_CAFEBABE_12345678_ABCDABCD, "addr=0 still intact");

        // ---- Test 4: boundary address (DEPTH-1) ----
        $display("-- T4: boundary address (DEPTH-1 = %0d) --", DEPTH-1);
        write_read(DEPTH-1, {LANES*DW{1'b1}}, "boundary addr all-ones data");

        // ---- Test 5: all lanes verified individually ----
        $display("-- T5: individual lane verification at addr=3 --");
        @(negedge clk);
        we = 1; addr = 32'd3;
        // Lane 0=0x11, Lane 1=0x22, Lane 2=0x33, Lane 3=0x44
        wdata = {32'h00000044, 32'h00000033, 32'h00000022, 32'h00000011};
        @(posedge clk); #1;
        we = 0; addr = 32'd3; #1;
        check(rdata[1*DW-1 -: DW], 32'h00000011, "lane 0 = 0x11");
        check(rdata[2*DW-1 -: DW], 32'h00000022, "lane 1 = 0x22");
        check(rdata[3*DW-1 -: DW], 32'h00000033, "lane 2 = 0x33");
        check(rdata[4*DW-1 -: DW], 32'h00000044, "lane 3 = 0x44");

        // ---- Test 6: write-enable gating (we=0 must not write) ----
        $display("-- T6: we=0 does not overwrite --");
        @(negedge clk);
        we = 0; addr = 32'd0; wdata = {LANES*DW{1'b0}};
        @(posedge clk); #1;
        addr = 32'd0; #1;
        check(rdata, 128'hDEADBEEF_CAFEBABE_12345678_ABCDABCD, "addr=0 unchanged after we=0");

        // ---- Summary ----
        $display("");
        if (fail_count == 0)
            $display("PASS  dmem_tb: all %0d checks passed", pass_count);
        else
            $display("FAIL  dmem_tb: %0d passed, %0d FAILED", pass_count, fail_count);

        $finish;
    end

endmodule
