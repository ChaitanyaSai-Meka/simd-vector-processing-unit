// pc_imem.v
// Program counter and instruction memory.
// When enabled, the PC advances one word or loads the branch target.
// Instruction memory supports optional hex-file preload.
// Synchronous reset sets PC to 0. Asynchronous instruction read.
// Part of: SIMD Vector Processing Unit, LANE BREAKERS
// Owner: Jagruthi Pulumati (Role 3, Control and Memory)

`timescale 1ns/1ps

module pc_imem #(
    parameter IMEM_DEPTH = 256,
    parameter ADDR_W     = 8,   // ceil(log2(IMEM_DEPTH))
    parameter INIT_FILE  = ""  // optional hex file, one instruction per word
) (
    input              clk,
    input              rst,           // synchronous active-high reset; sets PC to 0
    input              pc_en,         // 1 = update PC on the rising edge
    input              branch_en,     // 1 = select branch_target when pc_en=1
    input  [31:0]      branch_target, // absolute branch target address
    output reg [31:0]  pc,            // current program counter (word address)
    output [31:0]      instr          // instruction at current PC (combinational)
);

    reg [31:0] imem [0:IMEM_DEPTH-1];

    // Initialise from hex only when a filename is configured.
    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, imem);
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
        // If pc_en is deasserted, PC holds its value.
    end

    // Asynchronous instruction read
    assign instr = imem[pc[ADDR_W-1:0]];

endmodule
