// pc_imem.v
// Program counter and instruction memory.
// PC increments by 1 (word-addressed) each FETCH cycle unless a branch is taken.
// Instruction memory loaded from hex file via $readmemh.
// Synchronous reset sets PC to 0. Asynchronous instruction read.
// Part of: SIMD Vector Processing Unit, LANE BREAKERS
// Owner: Jagruthi Pulumati (Role 3, Control and Memory)

`timescale 1ns/1ps

module pc_imem #(
    parameter IMEM_DEPTH = 256,
    parameter ADDR_W     = 8    // ceil(log2(IMEM_DEPTH))
) (
    input              clk,
    input              rst,           // synchronous active-high reset; sets PC to 0
    input              pc_en,         // 1 = advance PC (asserted in FETCH state)
    input              branch_en,     // 1 = take branch, load branch_target
    input  [31:0]      branch_target, // absolute branch target address
    output reg [31:0]  pc,            // current program counter (word address)
    output [31:0]      instr          // instruction at current PC (combinational)
);

    reg [31:0] imem [0:IMEM_DEPTH-1];

    // Load instruction memory from hex file at start of simulation
    initial begin
        $readmemh("imem_init.hex", imem);
    end

    // Synchronous PC update
    always @(posedge clk) begin
        if (rst)
            pc <= 32'b0;
        else if (pc_en) begin
            if (branch_en)
                pc <= branch_target;
            else
                pc <= pc + 32'b1;
        end
        // If pc_en is deasserted (non-FETCH states), PC holds its value
    end

    // Asynchronous instruction read
    assign instr = imem[pc[ADDR_W-1:0]];

endmodule
