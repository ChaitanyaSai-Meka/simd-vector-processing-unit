// dmem.v - lane-group data memory: one LANES*DW-bit port, async read, sync write.
// Owner: Jagruthi Pulumati (Role 3, Control and Memory)

`timescale 1ns/1ps

module dmem #(
    parameter LANES   = 4,
    parameter DW      = 32,
    parameter DEPTH   = 256,   // lane-groups stored
    parameter ADDR_W  = 8,     // log2(DEPTH)
    parameter INIT_FILE = ""  // optional hex preload, one lane-group per line
) (
    input                    clk,
    input                    we,      // synchronous write enable
    input  [31:0]            addr,    // lane-group address
    input  [LANES*DW-1:0]    wdata,
    output [LANES*DW-1:0]    rdata    // combinational
);

    reg [LANES*DW-1:0] mem [0:DEPTH-1];

    // Initialise from hex only when a filename is configured.
    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    // Only the low ADDR_W bits index memory, so addresses wrap at DEPTH.
    assign rdata = mem[addr[ADDR_W-1:0]];

    // Synchronous write
    always @(posedge clk) begin
        if (we)
            mem[addr[ADDR_W-1:0]] <= wdata;
    end

endmodule
