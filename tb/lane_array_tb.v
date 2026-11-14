// lane_array_tb.v
// Self-checking testbench for lane_array.v
// Tests: VADD across LANES=1, 4, 8 (compile-time parameter),
//        golden-hex comparison, lane independence test, opb_sel scalar broadcast.
// Prints PASS or FAIL per test.
// Owner: Rakshita (Role 4, Verification)
//
// Run for different lane counts:
//   iverilog -DLANES=1 -o la_tb_L1.vvp tb/lane_array_tb.v rtl/lane_array.v rtl/lane_alu.v rtl/lane_mux.v && vvp la_tb_L1.vvp
//   iverilog -DLANES=4 -o la_tb_L4.vvp tb/lane_array_tb.v rtl/lane_array.v rtl/lane_alu.v rtl/lane_mux.v && vvp la_tb_L4.vvp
//   iverilog -DLANES=8 -o la_tb_L8.vvp tb/lane_array_tb.v rtl/lane_array.v rtl/lane_alu.v rtl/lane_mux.v && vvp la_tb_L8.vvp

`timescale 1ns/1ps

`ifndef LANES
  `define LANES 4
`endif

module lane_array_tb;

    parameter LANES = `LANES;
    parameter DW    = 32;
    parameter W     = LANES * DW;

    reg  [W-1:0]  vs1;
    reg  [W-1:0]  vs2;
    reg  [DW-1:0] scalar;
    reg            opb_sel;
    reg  [3:0]     alu_op;
    wire [W-1:0]  result;

    lane_array #(.LANES(LANES), .DW(DW)) dut (
        .vs1      (vs1),
        .vs2      (vs2),
        .scalar   (scalar),
        .opb_sel  (opb_sel),
        .alu_op   (alu_op),
        .result   (result)
    );

    integer pass_count = 0;
    integer fail_count = 0;

    task chk_lane;
        input integer    lane_i;
        input [DW-1:0]  got;
        input [DW-1:0]  exp;
        input [8*32-1:0] label;
        begin
            if (got === exp) begin
                $display("  PASS lane[%0d] %0s", lane_i, label);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL lane[%0d] %0s: exp=%h got=%h", lane_i, label, exp, got);
                fail_count = fail_count + 1;
            end
        end
    endtask

    integer i;
    reg [DW-1:0] a_i, b_i, exp_i;

    initial begin
        $display("=== lane_array_tb LANES=%0d ===", LANES);
        opb_sel = 0;

        // ---- T1: VADD (lane-wise) ----
        $display("-- T1: VADD all lanes --");
        // Set vs1[i] = i+1, vs2[i] = i+10, expected = i+11
        for (i = 0; i < LANES; i = i + 1) begin
            vs1[i*DW +: DW] = i + 1;
            vs2[i*DW +: DW] = i + 10;
        end
        alu_op = 4'h0; #1;
        for (i = 0; i < LANES; i = i + 1)
            chk_lane(i, result[i*DW +: DW], (i+1 + i+10) & 32'hFFFFFFFF, "VADD");

        // ---- T2: VSUB ----
        $display("-- T2: VSUB all lanes --");
        for (i = 0; i < LANES; i = i + 1) begin
            vs1[i*DW +: DW] = (i + 20);
            vs2[i*DW +: DW] = (i + 1);
        end
        alu_op = 4'h1; #1;
        for (i = 0; i < LANES; i = i + 1)
            chk_lane(i, result[i*DW +: DW], ((i+20) - (i+1)) & 32'hFFFFFFFF, "VSUB");

        // ---- T3: VSLT signed ----
        $display("-- T3: VSLT (lane 0: -1<1=1, lane 1: 1<-1=0, rest basic) --");
        vs1[0*DW +: DW] = 32'hFFFFFFFF;  // -1
        vs2[0*DW +: DW] = 32'h00000001;  // 1
        if (LANES > 1) begin
            vs1[1*DW +: DW] = 32'h00000001;  // 1
            vs2[1*DW +: DW] = 32'hFFFFFFFF;  // -1
        end
        for (i = 2; i < LANES; i = i + 1) begin
            vs1[i*DW +: DW] = i;
            vs2[i*DW +: DW] = i;
        end
        alu_op = 4'h5; #1;
        chk_lane(0, result[0*DW +: DW], 32'h00000001, "VSLT -1<1");
        if (LANES > 1)
            chk_lane(1, result[1*DW +: DW], 32'h00000000, "VSLT 1<-1");

        // ---- T4: Scalar broadcast (opb_sel=1) ----
        $display("-- T4: VADD.S scalar broadcast (opb_sel=1) --");
        for (i = 0; i < LANES; i = i + 1)
            vs1[i*DW +: DW] = i * 32'h00000010;
        scalar = 32'h00000005;
        opb_sel = 1; alu_op = 4'h0; #1;
        for (i = 0; i < LANES; i = i + 1)
            chk_lane(i, result[i*DW +: DW], (i*16 + 5) & 32'hFFFFFFFF, "VADD.S +5");
        opb_sel = 0;

        // ---- T5: Lane independence ----
        $display("-- T5: lane independence (change lane 0, others unchanged) --");
        for (i = 0; i < LANES; i = i + 1) begin
            vs1[i*DW +: DW] = 32'h00000001;
            vs2[i*DW +: DW] = 32'h00000001;
        end
        alu_op = 4'h0; #1;
        // All lanes should be 2
        for (i = 0; i < LANES; i = i + 1)
            chk_lane(i, result[i*DW +: DW], 32'h00000002, "baseline all=2");
        // Now change only lane 0
        vs1[0*DW +: DW] = 32'h000000FF; #1;
        chk_lane(0, result[0*DW +: DW], 32'h00000100, "lane0 changed to 0x100");
        for (i = 1; i < LANES; i = i + 1)
            chk_lane(i, result[i*DW +: DW], 32'h00000002, "other lanes still 2");

        // ---- T6: Overflow wraparound all lanes ----
        $display("-- T6: overflow all lanes --");
        for (i = 0; i < LANES; i = i + 1) begin
            vs1[i*DW +: DW] = 32'hFFFFFFFF;
            vs2[i*DW +: DW] = 32'h00000001;
        end
        alu_op = 4'h0; #1;
        for (i = 0; i < LANES; i = i + 1)
            chk_lane(i, result[i*DW +: DW], 32'h00000000, "VADD overflow all lanes");

        // ---- Summary ----
        $display("");
        if (fail_count == 0)
            $display("PASS  lane_array_tb LANES=%0d: all %0d checks passed", LANES, pass_count);
        else begin
            $display("FAIL  lane_array_tb LANES=%0d: %0d passed, %0d FAILED", LANES, pass_count, fail_count);
            $finish_and_return(1);
        end

        $finish;
    end

endmodule
