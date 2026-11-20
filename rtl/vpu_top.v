// Phase II SIMD core with instruction fetch, execution, and write-back.
`timescale 1ns/1ps

module vpu_top #(
    parameter LANES      = 4,
    parameter DW         = 32,
    parameter IMEM_DEPTH = 256,
    parameter DMEM_DEPTH = 256
) (
    input         clk,
    input         rst,
    output        halted,
    output [31:0] pc,
    output [31:0] cycle_count,
    output [31:0] instr_count
);
    // The memory modules index their arrays with an explicit address width.
    function integer address_width;
        input integer depth;
        integer remaining;
        begin
            address_width = 1;
            for (remaining = (depth - 1) >> 1; remaining > 0; remaining = remaining >> 1)
                address_width = address_width + 1;
        end
    endfunction

    localparam VECTOR_WIDTH = LANES * DW;
    localparam IMEM_ADDR_W = address_width(IMEM_DEPTH);
    localparam DMEM_ADDR_W = address_width(DMEM_DEPTH);

    wire [31:0] instr, branch_target;
    wire pc_en, branch_en;
    wire [2:0] vs1_addr, vs2_addr, vd_addr;
    wire [2:0] rs1_addr, rs2_addr, rd_addr;
    wire [31:0] rs1_data, rs2_data, sreg_wdata;
    wire [3:0] alu_op;
    wire opb_sel, res_sel, vreg_we, sreg_we, dmem_we;
    wire [31:0] dmem_addr;

    wire [VECTOR_WIDTH-1:0] vs1_data, vs2_data;
    wire [VECTOR_WIDTH-1:0] alu_result, mem_rdata, vector_result;
    reg  [VECTOR_WIDTH-1:0] vector_wb_data;

    pc_imem #(.IMEM_DEPTH(IMEM_DEPTH), .ADDR_W(IMEM_ADDR_W)) u_imem (
        .clk(clk), .rst(rst), .pc_en(pc_en), .branch_en(branch_en),
        .branch_target(branch_target), .pc(pc), .instr(instr)
    );

    control_unit u_control (
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

    vreg_file #(.LANES(LANES), .DW(DW)) u_vreg (
        .clk(clk), .we(vreg_we), .waddr(vd_addr), .wdata(vector_wb_data),
        .raddr1(vs1_addr), .rdata1(vs1_data), .raddr2(vs2_addr), .rdata2(vs2_data)
    );

    sreg_file #(.DW(32)) u_sreg (
        .clk(clk), .we(sreg_we), .waddr(rd_addr), .wdata(sreg_wdata),
        .raddr1(rs1_addr), .rdata1(rs1_data), .raddr2(rs2_addr), .rdata2(rs2_data)
    );

    // lane_array contains a lane_mux and lane_alu for each lane.
    lane_array #(.LANES(LANES), .DW(DW)) u_lanes (
        .vs1(vs1_data), .vs2(vs2_data), .scalar(rs2_data),
        .opb_sel(opb_sel), .alu_op(alu_op), .result(alu_result)
    );

    dmem #(.LANES(LANES), .DW(DW), .DEPTH(DMEM_DEPTH), .ADDR_W(DMEM_ADDR_W)) u_dmem (
        .clk(clk), .we(dmem_we), .addr(dmem_addr), .wdata(vs1_data), .rdata(mem_rdata)
    );

    result_combiner #(.LANES(LANES), .DW(DW)) u_combiner (
        .alu_result(alu_result), .mem_rdata(mem_rdata),
        .res_sel(res_sel), .wb_data(vector_result)
    );

    // pc_en marks the execute edge for vector instructions. Only a subsequent
    // vreg_we commits the captured value to the destination register.
    always @(posedge clk) begin
        if (pc_en)
            vector_wb_data <= vector_result;
    end
endmodule
