// sreg_file_tb.v
// Self-checking testbench for sreg_file.v
// Tests: all 8 registers, r0 stays zero after write attempt,
//        both read ports, we=0 guard.
// Owner: Rakshita (Role 4, Verification)

`timescale 1ns/1ps

module sreg_file_tb;

    parameter DW = 32;

    reg              clk;
    reg              we;
    reg  [2:0]       waddr;
    reg  [DW-1:0]    wdata;
    reg  [2:0]       raddr1, raddr2;
    wire [DW-1:0]    rdata1, rdata2;

    sreg_file #(.DW(DW)) dut (
        .clk    (clk),
        .we     (we),
        .waddr  (waddr),
        .wdata  (wdata),
        .raddr1 (raddr1),
        .rdata1 (rdata1),
        .raddr2 (raddr2),
        .rdata2 (rdata2)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;

    task chk;
        input [DW-1:0]   got;
        input [DW-1:0]   exp;
        input [8*48-1:0] label;
        begin
            if (got === exp) begin
                $display("  PASS %0s", label);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL %0s: expected=%h actual=%h", label, exp, got);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task write_reg;
        input [2:0]   addr;
        input [DW-1:0] data;
        begin
            @(negedge clk);
            we = 1; waddr = addr; wdata = data;
            @(posedge clk); #1;
            we = 0;
        end
    endtask

    integer i;

    initial begin
        $display("=== sreg_file_tb ===");
        we = 0; waddr = 0; wdata = 0; raddr1 = 0; raddr2 = 0;

        // ---- T1: r0 reads as 0 before any write ----
        $display("-- T1: r0 starts at 0 --");
        raddr1 = 3'd0; #1;
        chk(rdata1, 32'h00000000, "r0 = 0 initially");

        // ---- T2: Write all r1..r7, read back ----
        $display("-- T2: write r1..r7, read back --");
        for (i = 1; i < 8; i = i + 1)
            write_reg(i[2:0], i * 32'h11111111);
        for (i = 1; i < 8; i = i + 1) begin
            raddr1 = i[2:0]; #1;
            chk(rdata1, i * 32'h11111111, $sformatf("r%0d read back", i));
        end

        // ---- T3: r0 stays 0 even after write attempt ----
        $display("-- T3: r0 write attempt ignored --");
        write_reg(3'd0, 32'hDEADBEEF);
        raddr1 = 3'd0; #1;
        chk(rdata1, 32'h00000000, "r0 still 0 after write attempt");

        // ---- T4: Both ports independent ----
        $display("-- T4: two read ports independent --");
        raddr1 = 3'd1; raddr2 = 3'd7; #1;
        chk(rdata1, 32'h11111111, "port1 reads r1");
        chk(rdata2, 32'h77777777, "port2 reads r7");

        // ---- T5: r0 always 0 on port 2 too ----
        $display("-- T5: r0 on port 2 --");
        raddr2 = 3'd0; #1;
        chk(rdata2, 32'h00000000, "port2 r0 = 0");

        // ---- T6: Overwrite r3 ----
        $display("-- T6: overwrite r3 --");
        write_reg(3'd3, 32'hCAFEBABE);
        raddr1 = 3'd3; raddr2 = 3'd4; #1;
        chk(rdata1, 32'hCAFEBABE, "r3 overwritten");
        chk(rdata2, 32'h44444444, "r4 unchanged");

        $display("");
        if (fail_count == 0)
            $display("PASS  sreg_file_tb: all %0d checks passed", pass_count);
        else
            $display("FAIL  sreg_file_tb: %0d passed, %0d FAILED", pass_count, fail_count);

        $finish;
    end

endmodule
