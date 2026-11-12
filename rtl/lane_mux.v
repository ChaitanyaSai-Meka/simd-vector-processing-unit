// lane_mux.v
// Per-lane operand-B selector: vector element vs2[i] or scalar broadcast.
// Part of: SIMD Vector Processing Unit, LANE BREAKERS
// Owner: Dhanvin Vadlamudi (Role 2, Datapath RTL)

`timescale 1ns/1ps

module lane_mux #(
    parameter DW = 32
) (
    input  [DW-1:0]  vs2_lane,   // vector source: vs2[i*DW +: DW]
    input  [DW-1:0]  scalar,     // scalar register value broadcast to all lanes
    input            opb_sel,    // 0 = use vs2_lane, 1 = use scalar broadcast
    output [DW-1:0]  operand_b   // selected operand B → lane_alu.b
);

    assign operand_b = opb_sel ? scalar : vs2_lane;

endmodule
