// lane_alu.v
// ONE lane's 32-bit ALU. Combinational. Supports all SIMD opcodes.
// Part of: SIMD Vector Processing Unit, LANE BREAKERS
// Owner: Dhanvin Vadlamudi (Role 2, Datapath RTL)

`timescale 1ns/1ps

module lane_alu #(
    parameter DW = 32
) (
    input  [DW-1:0]  a,        // operand A (from vreg_file lane i)
    input  [DW-1:0]  b,        // operand B (from lane_mux output)
    input  [3:0]     alu_op,   // operation select (see docs/interfaces.md)
    output [DW-1:0]  result    // combinational result, valid same cycle as inputs
);

    reg [DW-1:0] res;

    always @(*) begin
        case (alu_op)
            4'h0: res = a + b;                                          // VADD
            4'h1: res = a - b;                                          // VSUB
            4'h2: res = a & b;                                          // VAND
            4'h3: res = a | b;                                          // VOR
            4'h4: res = a ^ b;                                          // VXOR
            4'h5: res = ($signed(a) < $signed(b)) ? {{(DW-1){1'b0}}, 1'b1}
                                                  : {DW{1'b0}};         // VSLT
            4'h6: res = (a == b) ? {{(DW-1){1'b0}}, 1'b1}
                                 : {DW{1'b0}};                           // VEQ
            4'h7: res = a << b[4:0];                                    // VSLL
            4'h8: res = a >> b[4:0];                                    // VSRL
            default: res = {DW{1'b0}};
        endcase
    end

    assign result = res;

endmodule
