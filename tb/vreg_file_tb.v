// vreg_file_tb.v
// Self-checking testbench for vreg_file.v
// Tests: write then read both ports, all 8 registers, same-cycle read/write,
//        independence of read ports. LANES=4, DW=32.
// Owner: Rakshita (Role 4, Verification)

`timescale 1ns/1ps

module vreg_file_tb;

    parameter LANES = 4;
    parameter DW    = 32;
    parameter W     = LANES * DW;  // 128 bits

    reg              clk;
    reg              we;
    reg  [2:0]       waddr;
    reg  [W-1:0]     wdata;
    reg  [2:0]       raddr1, raddr2;
    wire [W-1:0]     rdata1, rdata2;

    vreg_file #(.LANES(LANES), .DW(DW)) dut (
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
        input [W-1:0]    got;
        input [W-1:0]    exp;
        input [8*48-1:0] label;
        begin
            if (got === exp) begin
                $display("  PASS %0s", label);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL %0s\n    exp=%h\n    got=%h", label, exp, got);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task chk_reg;
        input integer    reg_num;
        input [W-1:0]    got;
        input [W-1:0]    exp;
        begin
            if (got === exp) begin
                $display("  PASS v%0d read port1", reg_num);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL v%0d read port1\n    exp=%h\n    got=%h", reg_num, exp, got);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Write a register (synchronous)
    task write_reg;
        input [2:0]  addr;
        input [W-1:0] data;
        begin
            @(negedge clk);
            we = 1; waddr = addr; wdata = data;
            @(posedge clk); #1;
            we = 0;
        end
    endtask

    integer i;
    reg [W-1:0] pat;

    initial begin
        $display("=== vreg_file_tb ===");
        we = 0; waddr = 0; wdata = 0; raddr1 = 0; raddr2 = 0;

        // ---- T1: Write to all 8 registers, read back on port 1 ----
        $display("-- T1: write all 8 registers, read port 1 --");
        for (i = 0; i < 8; i = i + 1) begin
            pat = {4{i[7:0], 8'hAB, 8'hCD, 8'hEF}};  // distinct per register
            write_reg(i[2:0], pat);
        end
        for (i = 0; i < 8; i = i + 1) begin
            raddr1 = i[2:0]; #1;
            pat = {4{i[7:0], 8'hAB, 8'hCD, 8'hEF}};
            chk_reg(i, rdata1, pat);
        end

        // ---- T2: Both ports read independently ----
        $display("-- T2: two independent read ports --");
        raddr1 = 3'd0; raddr2 = 3'd7; #1;
        chk(rdata1, {4{8'h00, 8'hAB, 8'hCD, 8'hEF}}, "port1 reads v0");
        chk(rdata2, {4{8'h07, 8'hAB, 8'hCD, 8'hEF}}, "port2 reads v7");

        raddr1 = 3'd3; raddr2 = 3'd5; #1;
        chk(rdata1, {4{8'h03, 8'hAB, 8'hCD, 8'hEF}}, "port1 reads v3");
        chk(rdata2, {4{8'h05, 8'hAB, 8'hCD, 8'hEF}}, "port2 reads v5");

        // ---- T3: Overwrite and verify ----
        $display("-- T3: overwrite v3, verify v3 changed, v4 unchanged --");
        write_reg(3'd3, 128'hDEADBEEF_CAFEBABE_12345678_ABCDABCD);
        raddr1 = 3'd3; raddr2 = 3'd4; #1;
        chk(rdata1, 128'hDEADBEEF_CAFEBABE_12345678_ABCDABCD, "v3 overwritten");
        chk(rdata2, {4{8'h04, 8'hAB, 8'hCD, 8'hEF}}, "v4 unchanged");

        // ---- T4: Same-cycle read during write (async read sees OLD value) ----
        // vreg_file uses sync write, so during the same cycle as we=1,
        // async read still returns the old value.
        $display("-- T4: same-cycle read sees old value (async read, sync write) --");
        @(negedge clk);
        we = 1; waddr = 3'd2; wdata = 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
        raddr1 = 3'd2; #1;  // read v2 while write is pending
        // The write hasn't clocked yet, so old value is read
        chk(rdata1, {4{8'h02, 8'hAB, 8'hCD, 8'hEF}}, "same-cycle read shows old v2");
        @(posedge clk); #1;
        we = 0;
        raddr1 = 3'd2; #1;
        chk(rdata1, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, "after clock v2 updated");

        // ---- T5: we=0 does not write ----
        $display("-- T5: we=0 does not modify register --");
        @(negedge clk);
        we = 0; waddr = 3'd1; wdata = 128'h00000000_00000000_00000000_00000000;
        @(posedge clk); #1;
        raddr1 = 3'd1; #1;
        chk(rdata1, {4{8'h01, 8'hAB, 8'hCD, 8'hEF}}, "v1 unchanged with we=0");

        $display("");
        if (fail_count == 0)
            $display("PASS  vreg_file_tb: all %0d checks passed", pass_count);
        else
            $display("FAIL  vreg_file_tb: %0d passed, %0d FAILED", pass_count, fail_count);

        $finish;
    end

endmodule
