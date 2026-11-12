// lane_array.v
// Generates LANES parallel copies of lane_mux + lane_alu using a generate loop.
// Part of: SIMD Vector Processing Unit, LANE BREAKERS
// Owner: Dhanvin Vadlamudi (Role 2, Datapath RTL)

`timescale 1ns/1ps

module lane_array #(
    parameter LANES = 4,
    parameter DW    = 32
) (
    input  [LANES*DW-1:0]  vs1,       // flat vector bus: lane i at [i*DW +: DW]
    input  [LANES*DW-1:0]  vs2,       // flat vector bus: lane i at [i*DW +: DW]
    input  [DW-1:0]        scalar,    // scalar broadcast value (same for every lane)
    input                  opb_sel,   // 0 = use vs2 per lane, 1 = broadcast scalar
    input  [3:0]           alu_op,    // shared operation for all lanes
    output [LANES*DW-1:0]  result     // flat result bus: lane i at [i*DW +: DW]
);

    genvar i;
    generate
        for (i = 0; i < LANES; i = i + 1) begin : lane
            wire [DW-1:0] mux_out;

            lane_mux #(.DW(DW)) u_mux (
                .vs2_lane  (vs2[i*DW +: DW]),
                .scalar    (scalar),
                .opb_sel   (opb_sel),
                .operand_b (mux_out)
            );

            lane_alu #(.DW(DW)) u_alu (
                .a      (vs1[i*DW +: DW]),
                .b      (mux_out),
                .alu_op (alu_op),
                .result (result[i*DW +: DW])
            );
        end
    endgenerate

endmodule
