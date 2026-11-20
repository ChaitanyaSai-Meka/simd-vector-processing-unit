// Hand-encoded five-instruction Phase II integration smoke test.
`timescale 1ns/1ps

module vpu_top_smoke_tb;
    parameter LANES = 4;
    localparam WIDTH = 32 * LANES;
    localparam LOAD_ADDR = 4;
    localparam STORE_ADDR = 2;
    localparam TOTAL_CYCLES = 3 + 3 + 3 + 2 + 2;
    localparam STORE_CYCLE = 3 + 3 + 3 + 2;

    // Lane 0 is the rightmost word. Expected words use golden.py vadd(word, 3).
    localparam [255:0] INPUT_WORDS =
        256'hfffffffe_1234ab00_00000001_00000000_80000000_7fffffff_ffffffff_12345678;
    localparam [255:0] RESULT_WORDS =
        256'h00000001_1234ab03_00000004_00000003_80000003_80000002_00000002_1234567b;
    localparam [WIDTH-1:0] SENTINEL = {LANES{32'hdeadbeef}};

    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;

    wire halted;
    wire [31:0] pc, cycle_count, instr_count;

    // Non-default depths exercise the top-level memory parameter wiring.
    vpu_top #(.LANES(LANES), .IMEM_DEPTH(5), .DMEM_DEPTH(5)) dut (
        .clk(clk), .rst(rst), .halted(halted), .pc(pc),
        .cycle_count(cycle_count), .instr_count(instr_count)
    );

    task check;
        input [8*32-1:0] label;
        input [WIDTH-1:0] expected;
        input [WIDTH-1:0] actual;
        begin
            if (actual !== expected) begin
                $display("FAIL vpu_top_smoke_tb LANES=%0d cycle=%0d %0s: expected %h, got %h",
                         LANES, cycle_count, label, expected, actual);
                $finish_and_return(1);
            end
        end
    endtask

    task check_reset;
        begin
            check("reset PC", 0, pc);
            check("reset cycle count", 0, cycle_count);
            check("reset instruction count", 0, instr_count);
            check("reset clears HALT", 0, halted);
        end
    endtask

    integer cycle;
    initial begin
        dut.u_imem.imem[0] = 32'h84800003; // SLI    r1, 3
        dut.u_imem.imem[1] = 32'h41100001; // VLD    v2, 1(r1)
        dut.u_imem.imem[2] = 32'h01a30000; // VADD.S v3, v2, r1
        dut.u_imem.imem[3] = 32'h4590ffff; // VST    v3, -1(r1)
        dut.u_imem.imem[4] = 32'hfc000000; // HALT
        dut.u_dmem.mem[LOAD_ADDR] = INPUT_WORDS[WIDTH-1:0];
        dut.u_dmem.mem[STORE_ADDR] = SENTINEL;

        @(posedge clk);
        #1;
        check_reset;
        rst = 1'b0;

        for (cycle = 1; cycle <= TOTAL_CYCLES; cycle = cycle + 1) begin
            @(posedge clk);
            #1;
            check("cycle count", cycle, cycle_count);
            check("HALT timing", cycle == TOTAL_CYCLES, halted);
            if (cycle < STORE_CYCLE)
                check("store destination before VST", SENTINEL, dut.u_dmem.mem[STORE_ADDR]);
            else
                check("store result", RESULT_WORDS[WIDTH-1:0], dut.u_dmem.mem[STORE_ADDR]);
        end
        check("HALT PC", 4, pc);
        check("retired instructions", 5, instr_count);
        check("source memory unchanged", INPUT_WORDS[WIDTH-1:0], dut.u_dmem.mem[LOAD_ADDR]);

        repeat (3) begin
            @(posedge clk);
            #1;
            check("HALT stays high", 1, halted);
            check("HALT holds PC", 4, pc);
            check("HALT holds cycle count", TOTAL_CYCLES, cycle_count);
            check("HALT holds instruction count", 5, instr_count);
            check("HALT holds store result", RESULT_WORDS[WIDTH-1:0], dut.u_dmem.mem[STORE_ADDR]);
        end

        rst = 1'b1;
        @(posedge clk);
        #1;
        check_reset;

        $display("PASS vpu_top_smoke_tb LANES=%0d: 5 instructions in %0d cycles",
                 LANES, TOTAL_CYCLES);
        $finish;
    end
endmodule
