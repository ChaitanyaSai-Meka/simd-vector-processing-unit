// vreg_file.v
// 8 vector registers, each LANES*DW bits wide.
// 2 asynchronous read ports, 1 synchronous write port.
// v0 is NOT hardwired to zero (see docs/decisions.md D-002).
// Part of: SIMD Vector Processing Unit, LANE BREAKERS
// Owner: Dhanvin Vadlamudi (Role 2, Datapath RTL)

`timescale 1ns/1ps

module vreg_file #(
    parameter LANES = 4,
    parameter DW    = 32
) (
    input                    clk,    // rising-edge clock
    // Write port (synchronous)
    input                    we,     // write enable, active high
    input  [2:0]             waddr,  // write address: 0..7 → v0..v7
    input  [LANES*DW-1:0]    wdata,  // data to write
    // Read port 1 — vs1 (asynchronous)
    input  [2:0]             raddr1,
    output [LANES*DW-1:0]    rdata1,
    // Read port 2 — vs2 (asynchronous)
    input  [2:0]             raddr2,
    output [LANES*DW-1:0]    rdata2
);

    reg [LANES*DW-1:0] mem [0:7];

    // Synchronous write
    always @(posedge clk) begin
        if (we)
            mem[waddr] <= wdata;
    end

    // Asynchronous (combinational) reads
    assign rdata1 = mem[raddr1];
    assign rdata2 = mem[raddr2];

endmodule
