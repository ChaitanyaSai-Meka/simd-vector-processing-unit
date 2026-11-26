// control_unit_tb.v - checks control words and timing against the ISA using real pc_imem, sreg_file and dmem.
// Owner: Jagruthi Pulumati (Role 3, Control and Memory)
`timescale 1ns/1ps

module control_unit_tb;
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;

    wire [31:0] instr, pc, rs1_data, rs2_data;
    wire [2:0] vs1_addr, vs2_addr, vd_addr, rs1_addr, rs2_addr, rd_addr;
    wire [3:0] alu_op;
    wire opb_sel, res_sel, vreg_we, sreg_we, dmem_we, pc_en, branch_en, halted;
    wire [31:0] sreg_wdata, dmem_addr, branch_target, cycle_count, instr_count;

    localparam [63:0] STORE_DATA = 64'h01234567_89abcdef;
    wire [63:0] load_data;

    // Control word order: ALU, broadcast, load select, vector/scalar/store write, PC/branch.
    wire [10:0] controls = {alu_op, opb_sel, res_sel, vreg_we, sreg_we, dmem_we,
                            pc_en, branch_en};
    localparam [10:0] IDLE         = 11'b0000_0_0_0_0_0_0_0;
    localparam [10:0] ADVANCE     = 11'b0000_0_0_0_0_0_1_0;
    localparam [10:0] TAKE_BRANCH = 11'b0000_0_0_0_0_0_1_1;
    localparam [10:0] STORE       = 11'b0000_0_0_0_0_1_1_0;
    localparam [10:0] LOAD_EX     = 11'b0000_0_1_0_0_0_1_0;
    localparam [10:0] LOAD_WB     = 11'b0000_0_1_1_0_0_0_0;
    localparam [10:0] SCALAR_WB   = 11'b0000_0_0_0_1_0_0_0;

    integer checks = 0;
    integer op;
    integer scalar_form;
    integer slot;
    reg [31:0] expected_pc;
    reg [31:0] expected_cycles;
    reg [31:0] expected_instrs;
    reg expected_halted;

    control_unit dut (
        .clk(clk), .rst(rst), .instr(instr), .pc(pc),
        .rs1_data(rs1_data), .rs2_data(rs2_data),
        .vs1_addr(vs1_addr), .vs2_addr(vs2_addr), .vd_addr(vd_addr),
        .rs1_addr(rs1_addr), .rs2_addr(rs2_addr), .rd_addr(rd_addr),
        .alu_op(alu_op), .opb_sel(opb_sel), .res_sel(res_sel),
        .vreg_we(vreg_we), .sreg_we(sreg_we), .sreg_wdata(sreg_wdata),
        .dmem_we(dmem_we), .dmem_addr(dmem_addr),
        .pc_en(pc_en), .branch_en(branch_en), .branch_target(branch_target),
        .halted(halted), .cycle_count(cycle_count), .instr_count(instr_count)
    );

    pc_imem #(.IMEM_DEPTH(32), .ADDR_W(5)) program_mem (
        .clk(clk), .rst(rst), .pc_en(pc_en), .branch_en(branch_en),
        .branch_target(branch_target), .pc(pc), .instr(instr)
    );

    sreg_file scalar_regs (
        .clk(clk), .we(sreg_we), .waddr(rd_addr), .wdata(sreg_wdata),
        .raddr1(rs1_addr), .rdata1(rs1_data), .raddr2(rs2_addr), .rdata2(rs2_data)
    );

    dmem #(.LANES(2), .DEPTH(16), .ADDR_W(4)) data_mem (
        .clk(clk), .we(dmem_we), .addr(dmem_addr),
        .wdata(STORE_DATA), .rdata(load_data)
    );

    // Pack fields into the 32-bit instruction format from docs/isa.md.
    function [31:0] encode;
        input [5:0] opcode;
        input [2:0] field_25_23;
        input [2:0] field_22_20;
        input [2:0] field_19_17;
        input bit_16;
        input [15:0] imm;
        begin
            encode = {opcode, field_25_23, field_22_20, field_19_17, bit_16, imm};
        end
    endfunction

    task check;
        input [255:0] label;
        input [63:0] expected;
        input [63:0] actual;
        begin
            if (actual !== expected) begin
                $display("FAIL control_unit_tb at %0t (expected PC=%0d, cycle=%0d) %0s: expected 0x%h, got 0x%h",
                         $time, expected_pc, expected_cycles, label, expected, actual);
                $finish_and_return(1);
            end
            checks = checks + 1;
        end
    endtask

    task check_status;
        begin
            check("PC", expected_pc, pc);
            check("cycle_count", expected_cycles, cycle_count);
            check("instr_count", expected_instrs, instr_count);
            check("halted", expected_halted, halted);
        end
    endtask

    // Check controls before the edge and the architectural state after it.
    task step;
        input [10:0] expected_controls;
        input [31:0] next_pc;
        input retires;
        input next_halted;
        begin
            check("control word", expected_controls, controls);
            if (!expected_halted)
                expected_cycles = expected_cycles + 1;
            if (retires)
                expected_instrs = expected_instrs + 1;
            expected_pc = next_pc;
            expected_halted = next_halted;
            @(posedge clk);
            #1;
            check_status;
        end
    endtask

    task fetch;
        begin
            step(IDLE, expected_pc, 1'b0, 1'b0);
        end
    endtask

    task reset_controller;
        begin
            rst = 1'b1;
            #1;
            check("reset inhibits controls", IDLE, controls);
            @(posedge clk);
            #1;
            expected_pc = 0;
            expected_cycles = 0;
            expected_instrs = 0;
            expected_halted = 0;
            check_status;
            rst = 1'b0;
            #1;
        end
    endtask

    initial begin
        // 0-1: SLI setup, 2-19: vector ALU ops in both forms, 20-26: VST, VLD, SADDI/BNE loop, SLI, VMUL (reserved), HALT; 27: spare VST.
        program_mem.imem[0] = encode(6'h21, 3'd3, 3'd0, 3'd0, 1'b0, 16'd10);
        program_mem.imem[1] = encode(6'h21, 3'd5, 3'd0, 3'd0, 1'b0, 16'd12);
        for (op = 0; op < 9; op = op + 1)
            for (scalar_form = 0; scalar_form < 2; scalar_form = scalar_form + 1)
                program_mem.imem[2 + 2*op + scalar_form] =
                    encode(op[5:0], 3'd7, 3'd6, 3'd3, scalar_form[0], 16'd0);

        program_mem.imem[20] = encode(6'h11, 3'd6, 3'd3, 3'd4, 1'b0, 16'hfffe);
        program_mem.imem[21] = encode(6'h10, 3'd7, 3'd3, 3'd0, 1'b0, 16'hfffe);
        program_mem.imem[22] = encode(6'h20, 3'd5, 3'd5, 3'd0, 1'b0, 16'hffff);
        program_mem.imem[23] = encode(6'h22, 3'd0, 3'd5, 3'd3, 1'b0, 16'hffff);
        program_mem.imem[24] = encode(6'h21, 3'd1, 3'd3, 3'd0, 1'b0, 16'h8000);
        program_mem.imem[25] = encode(6'h09, 3'd7, 3'd6, 3'd3, 1'b1, 16'd0);
        program_mem.imem[26] = encode(6'h3f, 3'd0, 3'd0, 3'd0, 1'b0, 16'd0);
        program_mem.imem[27] = encode(6'h11, 3'd6, 3'd3, 3'd0, 1'b0, 16'd0);
        scalar_regs.mem[3] = 32'd99;
        data_mem.mem[8] = 64'd0;
        data_mem.mem[10] = 64'd0;

        // Reset during a pending scalar write.
        reset_controller;
        fetch;
        step(ADVANCE, 1, 0, 0);
        check("SLI control before reset", SCALAR_WB, controls);
        reset_controller;
        check("reset cancels scalar write", 99, scalar_regs.mem[3]);

        fetch;
        step(ADVANCE, 1, 0, 0);
        check("SLI write address", 3, rd_addr);
        check("SLI data", 10, sreg_wdata);
        step(SCALAR_WB, 1, 1, 0);
        check("SLI wrote r3", 10, scalar_regs.mem[3]);

        fetch;
        step(ADVANCE, 2, 0, 0);
        step(SCALAR_WB, 2, 1, 0);
        check("SLI wrote r5", 12, scalar_regs.mem[5]);

        for (op = 0; op < 9; op = op + 1) begin
            for (scalar_form = 0; scalar_form < 2; scalar_form = scalar_form + 1) begin
                slot = 2 + 2*op + scalar_form;
                fetch;
                check("vector source 1", 6, vs1_addr);
                check("vector source 2", 3, vs2_addr);
                check("broadcast scalar register", 3, rs2_addr);
                check("broadcast scalar value", 10, rs2_data);
                step({op[3:0], scalar_form[0], 6'b000010}, slot + 1, 0, 0);
                // PC has advanced; destination, ALU and broadcast still use the saved word.
                check("vector destination in WB", 7, vd_addr);
                step({op[3:0], scalar_form[0], 6'b010000}, slot + 1, 1, 0);
            end
        end

        // Store then load the same lane-group.
        fetch;
        check("VST vector source", 6, vs1_addr);
        check("VST scalar base", 3, rs1_addr);
        check("VST effective group address", 8, dmem_addr);
        check("VST memory before clock", 0, load_data);
        step(STORE, 21, 1, 0);
        check("VST memory after clock", STORE_DATA, data_mem.mem[8]);

        fetch;
        check("VLD effective group address", 8, dmem_addr);
        check("VLD memory word", STORE_DATA, load_data);
        step(LOAD_EX, 22, 0, 0);
        check("VLD destination in WB", 7, vd_addr);
        check("VLD memory in WB", STORE_DATA, load_data);
        step(LOAD_WB, 22, 1, 0);

        fetch;
        step(ADVANCE, 23, 0, 0);
        check("SADDI write address", 5, rd_addr);
        check("SADDI 12 + (-1)", 11, sreg_wdata);
        step(SCALAR_WB, 23, 1, 0);
        // BNE taken once, then falls through.
        fetch;
        check("BNE backward target", 22, branch_target);
        check("BNE second register", 3, rs2_addr);
        step(TAKE_BRANCH, 22, 1, 0);

        fetch;
        step(ADVANCE, 23, 0, 0);
        check("SADDI 11 + (-1)", 10, sreg_wdata);
        step(SCALAR_WB, 23, 1, 0);
        fetch;
        step(ADVANCE, 24, 1, 0);

        fetch;
        step(ADVANCE, 25, 0, 0);
        check("SLI sign extension", 32'hffff8000, sreg_wdata);
        step(SCALAR_WB, 25, 1, 0);
        check("negative SLI wrote r1", 32'hffff8000, scalar_regs.mem[1]);

        fetch;
        step(ADVANCE, 26, 1, 0);
        fetch;
        step(IDLE, 26, 1, 1);
        // 24 three-cycle and five two-cycle instructions, including the loop repeat.
        check("final program cycles", 24*3 + 5*2, cycle_count);
        check("final retired instructions", 29, instr_count);
        repeat (3) step(IDLE, 26, 0, 1);
        check("HALT prevented next store", 0, data_mem.mem[10]);

        // Reset during a pending store.
        reset_controller;
        program_mem.imem[0] = program_mem.imem[27];
        fetch;
        check("store control before reset", STORE, controls);
        reset_controller;
        check("reset cancels store", 0, data_mem.mem[10]);

        $display("PASS control_unit_tb: all %0d checks passed", checks);
        $finish;
    end
endmodule
