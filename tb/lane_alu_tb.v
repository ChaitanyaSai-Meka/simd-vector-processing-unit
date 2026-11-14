// lane_alu_tb.v
// Self-checking testbench for lane_alu.v
// Tests: every opcode, edge cases (0, 1, -1, INT_MAX, INT_MIN),
//        overflow wraparound, shift by 0 and 31, compares of equal/negative values.
// Prints PASS or FAIL with expected vs actual.
// Owner: Rakshita (Role 4, Verification)

`timescale 1ns/1ps

module lane_alu_tb;

    parameter DW = 32;

    reg  [DW-1:0]  a, b;
    reg  [3:0]     alu_op;
    wire [DW-1:0]  result;

    lane_alu #(.DW(DW)) dut (.a(a), .b(b), .alu_op(alu_op), .result(result));

    integer pass_count = 0;
    integer fail_count = 0;

    task chk;
        input [DW-1:0] got;
        input [DW-1:0] exp;
        input [8*32-1:0] label;
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

    task test;
        input [DW-1:0] ta, tb;
        input [3:0]    op;
        input [DW-1:0] expected;
        input [8*32-1:0] label;
        begin
            a = ta; b = tb; alu_op = op; #1;
            chk(result, expected, label);
        end
    endtask

    initial begin
        $display("=== lane_alu_tb ===");

        // ---- VADD (4'h0) ----
        $display("-- VADD --");
        test(32'h00000001, 32'h00000002, 4'h0, 32'h00000003, "VADD basic 1+2");
        test(32'h00000000, 32'h00000000, 4'h0, 32'h00000000, "VADD 0+0");
        test(32'hFFFFFFFF, 32'h00000001, 4'h0, 32'h00000000, "VADD overflow wrap");
        test(32'h7FFFFFFF, 32'h00000001, 4'h0, 32'h80000000, "VADD INT_MAX+1");
        test(32'h80000000, 32'h80000000, 4'h0, 32'h00000000, "VADD INT_MIN+INT_MIN");

        // ---- VSUB (4'h1) ----
        $display("-- VSUB --");
        test(32'h00000005, 32'h00000003, 4'h1, 32'h00000002, "VSUB basic 5-3");
        test(32'h00000000, 32'h00000001, 4'h1, 32'hFFFFFFFF, "VSUB underflow 0-1");
        test(32'hFFFFFFFF, 32'hFFFFFFFF, 4'h1, 32'h00000000, "VSUB -1 - -1");
        test(32'h80000000, 32'h00000001, 4'h1, 32'h7FFFFFFF, "VSUB INT_MIN - 1");

        // ---- VAND (4'h2) ----
        $display("-- VAND --");
        test(32'hFF00FF00, 32'h0F0F0F0F, 4'h2, 32'h0F000F00, "VAND pattern");
        test(32'hFFFFFFFF, 32'h00000000, 4'h2, 32'h00000000, "VAND all with 0");
        test(32'hFFFFFFFF, 32'hFFFFFFFF, 4'h2, 32'hFFFFFFFF, "VAND all with all");

        // ---- VOR (4'h3) ----
        $display("-- VOR --");
        test(32'hF0F0F0F0, 32'h0F0F0F0F, 4'h3, 32'hFFFFFFFF, "VOR complement");
        test(32'h00000000, 32'h00000000, 4'h3, 32'h00000000, "VOR 0|0");

        // ---- VXOR (4'h4) ----
        $display("-- VXOR --");
        test(32'hAAAAAAAA, 32'h55555555, 4'h4, 32'hFFFFFFFF, "VXOR complement");
        test(32'hDEADBEEF, 32'hDEADBEEF, 4'h4, 32'h00000000, "VXOR self=0");

        // ---- VSLT signed (4'h5) ----
        $display("-- VSLT --");
        test(32'h00000001, 32'h00000002, 4'h5, 32'h00000001, "VSLT 1<2 → 1");
        test(32'h00000002, 32'h00000001, 4'h5, 32'h00000000, "VSLT 2<1 → 0");
        test(32'h00000005, 32'h00000005, 4'h5, 32'h00000000, "VSLT equal → 0");
        test(32'h80000000, 32'h00000001, 4'h5, 32'h00000001, "VSLT INT_MIN<1 → 1");
        test(32'h00000001, 32'h80000000, 4'h5, 32'h00000000, "VSLT 1<INT_MIN → 0");
        test(32'hFFFFFFFF, 32'h00000001, 4'h5, 32'h00000001, "VSLT -1<1 → 1");
        test(32'h80000000, 32'hFFFFFFFF, 4'h5, 32'h00000001, "VSLT INT_MIN<-1 → 1");

        // ---- VEQ (4'h6) ----
        $display("-- VEQ --");
        test(32'hDEADBEEF, 32'hDEADBEEF, 4'h6, 32'h00000001, "VEQ equal → 1");
        test(32'h00000001, 32'h00000002, 4'h6, 32'h00000000, "VEQ not equal → 0");
        test(32'h00000000, 32'h00000000, 4'h6, 32'h00000001, "VEQ 0==0 → 1");
        test(32'h80000000, 32'h80000000, 4'h6, 32'h00000001, "VEQ INT_MIN==INT_MIN → 1");

        // ---- VSLL (4'h7) ----
        $display("-- VSLL --");
        test(32'h00000001, 32'h00000000, 4'h7, 32'h00000001, "VSLL by 0");
        test(32'h00000001, 32'h00000001, 4'h7, 32'h00000002, "VSLL by 1");
        test(32'h00000001, 32'h0000001F, 4'h7, 32'h80000000, "VSLL by 31");
        test(32'h80000000, 32'h00000001, 4'h7, 32'h00000000, "VSLL INT_MIN << 1 wraps");
        // shift amount uses low 5 bits only
        test(32'h00000001, 32'h00000020, 4'h7, 32'h00000001, "VSLL shift=32 → low5=0 → no shift");

        // ---- VSRL (4'h8) ----
        $display("-- VSRL --");
        test(32'h80000000, 32'h00000000, 4'h8, 32'h80000000, "VSRL by 0");
        test(32'h80000000, 32'h0000001F, 4'h8, 32'h00000001, "VSRL INT_MIN >> 31 = 1");
        test(32'hFFFFFFFF, 32'h00000001, 4'h8, 32'h7FFFFFFF, "VSRL -1 >> 1 (logical, not arithmetic)");
        test(32'hFFFFFFFF, 32'h00000000, 4'h8, 32'hFFFFFFFF, "VSRL by 0");

        // ---- Default / unknown op ----
        $display("-- Default op --");
        test(32'hDEADBEEF, 32'hCAFEBABE, 4'hF, 32'h00000000, "unknown op → 0");

        // ---- Summary ----
        $display("");
        if (fail_count == 0)
            $display("PASS  lane_alu_tb: all %0d checks passed", pass_count);
        else begin
            $display("FAIL  lane_alu_tb: %0d passed, %0d FAILED", pass_count, fail_count);
            $finish_and_return(1);
        end

        $finish;
    end

endmodule
