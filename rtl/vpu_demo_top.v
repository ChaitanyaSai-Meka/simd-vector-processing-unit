// vpu_demo_top.v
// Phase I demo datapath. Wires vreg_file, sreg_file, lane_array, result_combiner.
// The testbench drives all control signals directly (no control_unit FSM needed
// for the Phase I demo). One clock cycle per operation: combinational ALU +
// synchronous write-back.
// Part of: SIMD Vector Processing Unit, LANE BREAKERS
// Owner: Kasula Lalithendra (Role 1, Architecture Lead)

`timescale 1ns/1ps

module vpu_demo_top #(
    parameter LANES = 4,
    parameter DW    = 32
) (
    input              clk,
    input              rst,          // synchronous active-high reset (future use)

    // --- Testbench control: register read addresses ---
    input  [2:0]       vs1_addr,     // vector source 1 address
    input  [2:0]       vs2_addr,     // vector source 2 address
    input  [2:0]       rs2_addr,     // scalar source 2 address (for opb_sel=1)

    // --- ALU control ---
    input  [3:0]       alu_op,       // operation (see docs/interfaces.md)
    input              opb_sel,      // 0=vector, 1=scalar broadcast

    // --- Write-back control ---
    input  [2:0]       vd_addr,      // destination vector register address
    input              vreg_we,      // vector register write enable

    // --- Direct load port for injecting test vectors ---
    input  [2:0]            load_addr,
    input  [LANES*DW-1:0]   load_data,
    input                   load_we,

    // --- Result readout (combinational, from vreg_file read port 1) ---
    output [LANES*DW-1:0]   result_out
);

    // ---- Internal wires ----
    wire [LANES*DW-1:0] vs1_data, vs2_data;
    wire [DW-1:0]       rs2_data_unused;  // port 1 of sreg (unused in demo)
    wire [DW-1:0]       scalar_data;
    wire [LANES*DW-1:0] alu_result;
    wire [LANES*DW-1:0] wb_data;

    // ---- Vector register file ----
    // Write port: multiplexed between load_we (direct inject) and vreg_we (ALU WB)
    // Priority: load_we takes precedence (for test setup)
    wire              vrf_we    = load_we | vreg_we;
    wire [2:0]        vrf_waddr = load_we ? load_addr : vd_addr;
    wire [LANES*DW-1:0] vrf_wdata = load_we ? load_data : wb_data;

    vreg_file #(.LANES(LANES), .DW(DW)) u_vreg (
        .clk    (clk),
        .we     (vrf_we),
        .waddr  (vrf_waddr),
        .wdata  (vrf_wdata),
        .raddr1 (vs1_addr),
        .rdata1 (vs1_data),
        .raddr2 (vs2_addr),
        .rdata2 (vs2_data)
    );

    // ---- Scalar register file ----
    sreg_file #(.DW(DW)) u_sreg (
        .clk    (clk),
        .we     (1'b0),          // no scalar writes in demo
        .waddr  (3'b000),
        .wdata  ({DW{1'b0}}),
        .raddr1 (3'b000),
        .rdata1 (rs2_data_unused),
        .raddr2 (rs2_addr),
        .rdata2 (scalar_data)
    );

    // ---- Lane array: LANES parallel mux+ALU instances ----
    lane_array #(.LANES(LANES), .DW(DW)) u_lanes (
        .vs1     (vs1_data),
        .vs2     (vs2_data),
        .scalar  (scalar_data),
        .opb_sel (opb_sel),
        .alu_op  (alu_op),
        .result  (alu_result)
    );

    // ---- Result combiner: ALU result only in demo (no VLD) ----
    result_combiner #(.LANES(LANES), .DW(DW)) u_comb (
        .alu_result (alu_result),
        .mem_rdata  ({LANES*DW{1'b0}}),
        .res_sel    (1'b0),          // always ALU in demo
        .wb_data    (wb_data)
    );

    // ---- Result readout: re-read vs1_addr port combinationally ----
    assign result_out = vs1_data;

endmodule
