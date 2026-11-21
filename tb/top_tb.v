// Phase II system tests. Select +BENCH=b1|b2|b3|independence|coverage.
// Use +DUMP=<file> for a data-memory dump and +VCD=<file> for a waveform.
`timescale 1ns/1ps

module top_tb;
    parameter LANES = 4;
    localparam DW = 32;
    localparam WIDTH = LANES * DW;
    localparam GROUPS = 64 / LANES;
    localparam C_BASE = 2 * GROUPS;
    localparam MAX_CYCLES = 10000;
    localparam [63:0] REQUIRED_OPCODES = 64'h80000007_000301ff;

    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;

    wire halted;
    wire [31:0] pc, cycle_count, instr_count;
    vpu_top #(.LANES(LANES)) dut (
        .clk(clk), .rst(rst), .halted(halted), .pc(pc),
        .cycle_count(cycle_count), .instr_count(instr_count)
    );

    reg [8*16-1:0] benchmark;
    reg [8*1024-1:0] dump_file, vcd_file;
    reg [WIDTH-1:0] expected [0:GROUPS-1];
    reg [31:0] alu_expected [0:8];
    integer dump_words;
    reg dump_requested;
    reg [63:0] opcodes = 0;
    reg [7:0] vreads = 0, vwrites = 0, sreads = 0, swrites = 0;
    reg branch_taken = 0, branch_untaken = 0;
    wire [5:0] opcode = dut.u_control.saved_instr[31:26];

    // Record operand accesses only for ports used by the executed instruction.
    always @(posedge clk) begin
        if (!rst && !halted && benchmark == "coverage") begin
            if (dut.vreg_we)
                vwrites[dut.vd_addr] <= 1'b1;
            if (dut.sreg_we)
                swrites[dut.rd_addr] <= 1'b1;

            if (dut.u_control.state == dut.u_control.DECODE_EX) begin
                opcodes[opcode] <= 1'b1;
                if (opcode <= 6'h08) begin
                    vreads[dut.vs1_addr] <= 1'b1;
                    if (dut.opb_sel)
                        sreads[dut.rs2_addr] <= 1'b1;
                    else
                        vreads[dut.vs2_addr] <= 1'b1;
                end
                case (opcode)
                    6'h10, 6'h20: sreads[dut.rs1_addr] <= 1'b1; // VLD, SADDI
                    6'h11: begin // VST
                        sreads[dut.rs1_addr] <= 1'b1;
                        vreads[dut.vs1_addr] <= 1'b1;
                    end
                    6'h22: begin // BNE
                        sreads[dut.rs1_addr] <= 1'b1;
                        sreads[dut.rs2_addr] <= 1'b1;
                        if (dut.branch_en)
                            branch_taken <= 1'b1;
                        else
                            branch_untaken <= 1'b1;
                    end
                    default: begin end
                endcase
            end
        end
    end

    task load_benchmark;
        input [15:0] name;
        input integer imem_words;
        reg [8*80-1:0] filename;
        begin
            $sformat(filename, "verif/data/%0s_imem_L%0d.hex", name, LANES);
            $readmemh(filename, dut.u_imem.imem, 0, imem_words - 1);
            $sformat(filename, "verif/data/%0s_dmem_L%0d.hex", name, LANES);
            $readmemh(filename, dut.u_dmem.mem, 0, 3*GROUPS - 1);
            $sformat(filename, "verif/data/%0s_C_expected_L%0d.hex", name, LANES);
            $readmemh(filename, expected, 0, GROUPS - 1);
            dump_words = 3 * GROUPS;
        end
    endtask

    task run_program;
        integer elapsed;
        begin
            @(posedge clk);
            #1 rst = 1'b0;
            elapsed = 0;
            while (halted !== 1'b1 && elapsed < MAX_CYCLES) begin
                @(posedge clk);
                #1;
                elapsed = elapsed + 1;
            end
            if (halted !== 1'b1 || cycle_count !== elapsed) begin
                $display("FAIL top_tb BENCH=%0s LANES=%0d PC=%0d: expected halted=1 cycles=%0d, got halted=%b cycles=%0d",
                         benchmark, LANES, pc, elapsed, halted, cycle_count);
                $finish_and_return(1);
            end
        end
    endtask

    task check_group;
        input integer address;
        input [WIDTH-1:0] reference;
        integer lane;
        begin
            for (lane = 0; lane < LANES; lane = lane + 1) begin
                if ((^reference[lane*DW +: DW] === 1'bx) ||
                    (dut.u_dmem.mem[address][lane*DW +: DW] !== reference[lane*DW +: DW])) begin
                    $display("FAIL top_tb BENCH=%0s LANES=%0d addr=%0d lane=%0d: expected %08x, got %08x",
                             benchmark, LANES, address, lane, reference[lane*DW +: DW],
                             dut.u_dmem.mem[address][lane*DW +: DW]);
                    $finish_and_return(1);
                end
            end
        end
    endtask

    task check_benchmark_output;
        integer group;
        begin
            for (group = 0; group < GROUPS; group = group + 1)
                check_group(C_BASE + group, expected[group]);
        end
    endtask

    function [31:0] encode;
        input [5:0] op;
        input [2:0] dest, first, second;
        input scalar_form;
        input [15:0] imm;
        begin
            encode = {op, dest, first, second, scalar_form, imm};
        end
    endfunction

    task load_coverage_program;
        integer slot, index;
        begin
            slot = 0;
            for (index = 0; index < 8; index = index + 1) begin
                dut.u_imem.imem[slot]   = encode(6'h21, index[2:0], 0, 0, 0, 1); // SLI rI, 1
                dut.u_imem.imem[slot+1] = encode(6'h20, index[2:0], index[2:0], 0, 0, 0); // SADDI rI,rI,0
                dut.u_imem.imem[slot+2] = encode(6'h10, index[2:0], 0, 0, 0, 0); // VLD vI,0(r0)
                dut.u_imem.imem[slot+3] = encode(6'h00, index[2:0], index[2:0], 0, 1, 0); // VADD.S vI,vI,r0
                slot = slot + 4;
            end
            dut.u_imem.imem[slot]   = encode(6'h10, 1, 0, 0, 0, 1); // VLD v1,1(r0)
            dut.u_imem.imem[slot+1] = encode(6'h22, 0, 0, 1, 0, 2); // BNE r0,r1,+2, taken
            dut.u_imem.imem[slot+2] = 32'hfc000000; // Early HALT if the first branch fails
            dut.u_imem.imem[slot+3] = encode(6'h22, 0, 0, 0, 0, 2); // BNE r0,r0,+2, untaken
            slot = slot + 4;
            for (index = 0; index < 9; index = index + 1) begin
                dut.u_imem.imem[slot]   = encode(index[5:0], 2, 0, 1, 0, 0); // v2 = ALU(v0,v1)
                dut.u_imem.imem[slot+1] = encode(6'h11, 2, 0, 0, 0, 16'd2 + index[15:0]);
                dut.u_dmem.mem[2 + index] = {WIDTH{1'b0}};
                slot = slot + 2;
            end
            dut.u_imem.imem[slot] = 32'hfc000000;
            dut.u_dmem.mem[0] = {LANES{32'h80000001}};
            dut.u_dmem.mem[1] = {LANES{32'h00000001}};
            dump_words = 11;

            // golden.py ALU_OPS results with inputs 0x80000001 and 1.
            alu_expected[0] = 32'h80000002;
            alu_expected[1] = 32'h80000000;
            alu_expected[2] = 32'h00000001;
            alu_expected[3] = 32'h80000001;
            alu_expected[4] = 32'h80000000;
            alu_expected[5] = 32'h00000001;
            alu_expected[6] = 32'h00000000;
            alu_expected[7] = 32'h00000002;
            alu_expected[8] = 32'h40000000;
        end
    endtask

    task check_coverage;
        integer index;
        begin
            if ({vreads, vwrites, sreads, swrites, branch_taken, branch_untaken} !== {32'hffffffff, 2'b11} ||
                (opcodes & REQUIRED_OPCODES) !== REQUIRED_OPCODES) begin
                $display("FAIL top_tb coverage LANES=%0d: expected opcode mask %h, register masks ff, both branches",
                         LANES, REQUIRED_OPCODES);
                $display("  got opcodes=%h vread=%h vwrite=%h sread=%h swrite=%h branches=%b%b",
                         opcodes, vreads, vwrites, sreads, swrites, branch_taken, branch_untaken);
                $finish_and_return(1);
            end
            for (index = 0; index < 9; index = index + 1)
                check_group(2 + index, {LANES{alu_expected[index]}});
        end
    endtask

    task dump_memory;
        integer fd, address;
        begin
            fd = $fopen(dump_file, "w");
            if (fd == 0) begin
                $display("FAIL top_tb could not write %0s", dump_file);
                $finish_and_return(1);
            end
            for (address = 0; address < dump_words; address = address + 1)
                $fdisplay(fd, "%h", dut.u_dmem.mem[address]);
            $fclose(fd);
        end
    endtask

    localparam CHANGED_GROUP = GROUPS / 2;
    localparam CHANGED_BIT = (LANES - 1) * DW;
    // A packed alias lets the VCD show the destination register after write-back.
    wire [WIDTH-1:0] wave_v2 = dut.u_vreg.mem[2];
    initial begin
        if (!$value$plusargs("BENCH=%s", benchmark))
            benchmark = "b1";
        dump_requested = $value$plusargs("DUMP=%s", dump_file);
        if ($value$plusargs("VCD=%s", vcd_file)) begin
            $dumpfile(vcd_file);
            $dumpvars(0, dut);
            $dumpvars(0, wave_v2);
        end

        case (benchmark)
            "b1", "independence": load_benchmark("b1", 9);
            "b2": load_benchmark("b2", 16);
            "b3": load_benchmark("b3", 18);
            "coverage": load_coverage_program;
            default: begin
                $display("FAIL top_tb unknown BENCH=%0s", benchmark);
                $finish_and_return(1);
            end
        endcase

        run_program;
        if (dump_requested && benchmark != "independence")
            dump_memory;
        if (benchmark == "coverage")
            check_coverage;
        else
            check_benchmark_output;

        if (benchmark == "independence") begin
            @(negedge clk);
            rst = 1'b1;
            load_benchmark("b1", 9);
            dut.u_dmem.mem[CHANGED_GROUP][CHANGED_BIT +: DW] =
                dut.u_dmem.mem[CHANGED_GROUP][CHANGED_BIT +: DW] + 32'd1;
            expected[CHANGED_GROUP][CHANGED_BIT +: DW] =
                expected[CHANGED_GROUP][CHANGED_BIT +: DW] + 32'd1;
            run_program;
            if (dump_requested)
                dump_memory;
            check_benchmark_output;
        end

        $display("PASS top_tb BENCH=%0s LANES=%0d cycle_count=%0d instr_count=%0d",
                 benchmark, LANES, cycle_count, instr_count);
        $finish;
    end
endmodule
