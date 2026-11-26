// pc_imem_tb.v - self-checking test of PC reset, increment, hold, branch and instruction fetch.
// Owner: Jagruthi Pulumati (Role 3, Control and Memory)

`timescale 1ns/1ps

module pc_imem_tb;

    parameter IMEM_DEPTH = 16;
    parameter ADDR_W     = 4;

    reg              clk;
    reg              rst;
    reg              pc_en;
    reg              branch_en;
    reg  [31:0]      branch_target;
    wire [31:0]      pc;
    wire [31:0]      instr;

    pc_imem #(
        .IMEM_DEPTH (IMEM_DEPTH),
        .ADDR_W     (ADDR_W)
    ) dut (
        .clk           (clk),
        .rst           (rst),
        .pc_en         (pc_en),
        .branch_en     (branch_en),
        .branch_target (branch_target),
        .pc            (pc),
        .instr         (instr)
    );

    // Clock
    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;

    task check32;
        input [31:0] got;
        input [31:0] exp;
        input [127:0] label;
        begin
            if (got === exp) begin
                $display("  PASS: %s", label);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: %s  expected=%h  actual=%h", label, exp, got);
                fail_count = fail_count + 1;
            end
        end
    endtask

    integer k;

    initial begin
        $display("=== pc_imem_tb ===");

        // Distinct word per address: imem[k] = 4k + 1.
        for (k = 0; k < IMEM_DEPTH; k = k + 1)
            dut.imem[k] = k * 32'h00000004 + 32'h00000001;

        $display("-- T1: reset sets pc=0 --");
        rst = 1; pc_en = 0; branch_en = 0; branch_target = 0;
        @(posedge clk); #1;
        rst = 0;
        check32(pc, 32'd0, "pc==0 after reset");

        $display("-- T2: instr at pc=0 --");
        #1;
        check32(instr, 32'h00000001, "instr[0] = 1");

        $display("-- T3: sequential PC advance --");
        pc_en = 1; branch_en = 0;
        @(posedge clk); #1;
        check32(pc, 32'd1, "pc==1 after 1 advance");
        check32(instr, 32'h00000005, "instr[1] = 5");

        @(posedge clk); #1;
        check32(pc, 32'd2, "pc==2 after 2 advances");
        check32(instr, 32'h00000009, "instr[2] = 9");

        @(posedge clk); #1;
        check32(pc, 32'd3, "pc==3 after 3 advances");

        $display("-- T4: pc holds when pc_en=0 --");
        pc_en = 0; branch_en = 1; branch_target = 32'd10;
        @(posedge clk); #1;
        check32(pc, 32'd3, "pc holds with branch_en=1 and pc_en=0");

        $display("-- T5: branch taken --");
        pc_en = 1; branch_en = 1; branch_target = 32'd10;
        @(posedge clk); #1;
        branch_en = 0;
        check32(pc, 32'd10, "pc==10 after branch");
        check32(instr, 10*32'h00000004 + 32'h00000001, "instr at pc=10");

        $display("-- T6: sequential increment after branch --");
        pc_en = 1; branch_en = 0;
        @(posedge clk); #1;
        check32(pc, 32'd11, "pc==11 after branch+1");

        $display("-- T7: reset from pc=11 --");
        rst = 1;
        @(posedge clk); #1;
        rst = 0;
        check32(pc, 32'd0, "pc reset to 0 from mid-exec");

        $display("");
        if (fail_count == 0)
            $display("PASS  pc_imem_tb: all %0d checks passed", pass_count);
        else begin
            $display("FAIL  pc_imem_tb: %0d passed, %0d FAILED", pass_count, fail_count);
            $finish_and_return(1);
        end

        $finish;
    end

endmodule
