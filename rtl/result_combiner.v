// result_combiner.v
// Selects between ALU result and memory load data for vector register write-back.
// Part of: SIMD Vector Processing Unit, LANE BREAKERS
// Owner: Dhanvin Vadlamudi (Role 2, Datapath RTL)

`timescale 1ns/1ps

module result_combiner #(
    parameter LANES = 4,
    parameter DW    = 32
) (
    input  [LANES*DW-1:0]  alu_result,  // from lane_array.result
    input  [LANES*DW-1:0]  mem_rdata,   // from dmem.rdata (vector load)
    input                   res_sel,     // 0 = ALU result, 1 = memory load data
    output [LANES*DW-1:0]  wb_data      // write-back data → vreg_file.wdata
);

    assign wb_data = res_sel ? mem_rdata : alu_result;

endmodule
