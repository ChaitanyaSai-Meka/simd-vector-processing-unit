// pc_imem.v - program counter plus instruction memory with async read and sync reset.
// Owner: Jagruthi Pulumati (Role 3, Control and Memory)

`timescale 1ns/1ps

module pc_imem #(
    parameter IMEM_DEPTH = 256,
    parameter ADDR_W     = 8,   // log2(IMEM_DEPTH)
    parameter INIT_FILE  = ""  // optional hex preload, one instruction per line
) (
    input              clk,
    input              rst,           // sync reset, PC <= 0
    input              pc_en,         // update PC this edge
    input              branch_en,     // take branch_target when pc_en
    input  [31:0]      branch_target, // absolute word address
    output reg [31:0]  pc,            // word address
    output [31:0]      instr          // imem[pc], combinational
);

    reg [31:0] imem [0:IMEM_DEPTH-1];

    // Initialise from hex only when a filename is configured.
    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, imem);
    end

    // PC loads the branch target or advances by one when pc_en is high, else holds.
    always @(posedge clk) begin
        if (rst)
            pc <= 32'b0;
        else if (pc_en) begin
            if (branch_en)
                pc <= branch_target;
            else
                pc <= pc + 32'b1;
        end
    end

    // Asynchronous instruction read
    assign instr = imem[pc[ADDR_W-1:0]];

endmodule
