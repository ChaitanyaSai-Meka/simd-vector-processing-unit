// lane_mux_tb.v
// Self-checking testbench for lane_mux.v
// Tests: opb_sel=0 passes vs2_lane, opb_sel=1 passes scalar, all edge values.
// Owner: Rakshita (Role 4, Verification)

`timescale 1ns/1ps

module lane_mux_tb;

    parameter DW = 32;

    reg  [DW-1:0]  vs2_lane;
    reg  [DW-1:0]  scalar;
    reg            opb_sel;
    wire [DW-1:0]  operand_b;

    lane_mux #(.DW(DW)) dut (
        .vs2_lane  (vs2_lane),
        .scalar    (scalar),
        .opb_sel   (opb_sel),
        .operand_b (operand_b)
    );

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

    initial begin
        $display("=== lane_mux_tb ===");

        // opb_sel=0: should output vs2_lane
        $display("-- opb_sel=0: vector path --");
        vs2_lane = 32'hDEADBEEF; scalar = 32'hCAFEBABE; opb_sel = 0; #1;
        chk(operand_b, 32'hDEADBEEF, "sel=0 → vs2_lane");

        vs2_lane = 32'h00000000; scalar = 32'hFFFFFFFF; opb_sel = 0; #1;
        chk(operand_b, 32'h00000000, "sel=0 → vs2_lane=0");

        vs2_lane = 32'h7FFFFFFF; scalar = 32'h80000000; opb_sel = 0; #1;
        chk(operand_b, 32'h7FFFFFFF, "sel=0 → INT_MAX");

        // opb_sel=1: should output scalar
        $display("-- opb_sel=1: scalar broadcast --");
        vs2_lane = 32'hDEADBEEF; scalar = 32'h000000FF; opb_sel = 1; #1;
        chk(operand_b, 32'h000000FF, "sel=1 → scalar");

        vs2_lane = 32'hFFFFFFFF; scalar = 32'h00000000; opb_sel = 1; #1;
        chk(operand_b, 32'h00000000, "sel=1 → scalar=0 (not vs2)");

        vs2_lane = 32'h12345678; scalar = 32'h80000000; opb_sel = 1; #1;
        chk(operand_b, 32'h80000000, "sel=1 → INT_MIN scalar");

        // Switch back
        $display("-- dynamic switch --");
        vs2_lane = 32'hAAAAAAAA; scalar = 32'h55555555;
        opb_sel = 0; #1; chk(operand_b, 32'hAAAAAAAA, "dynamic sel=0");
        opb_sel = 1; #1; chk(operand_b, 32'h55555555, "dynamic sel=1");
        opb_sel = 0; #1; chk(operand_b, 32'hAAAAAAAA, "dynamic back sel=0");

        $display("");
        if (fail_count == 0)
            $display("PASS  lane_mux_tb: all %0d checks passed", pass_count);
        else
            $display("FAIL  lane_mux_tb: %0d passed, %0d FAILED", pass_count, fail_count);

        $finish;
    end

endmodule
