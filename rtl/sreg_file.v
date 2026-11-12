// sreg_file.v
// 8 scalar registers, each DW bits wide.
// r0 (address 0) is hardwired to 0: writes are silently ignored, reads always return 0.
// 2 asynchronous read ports, 1 synchronous write port.
// Part of: SIMD Vector Processing Unit, LANE BREAKERS
// Owner: Dhanvin Vadlamudi (Role 2, Datapath RTL)

`timescale 1ns/1ps

module sreg_file #(
    parameter DW = 32
) (
    input              clk,
    // Write port (synchronous)
    input              we,
    input  [2:0]       waddr,
    input  [DW-1:0]    wdata,
    // Read port 1 — rs1 (asynchronous)
    input  [2:0]       raddr1,
    output [DW-1:0]    rdata1,
    // Read port 2 — rs2 (asynchronous)
    input  [2:0]       raddr2,
    output [DW-1:0]    rdata2
);

    reg [DW-1:0] mem [0:7];

    // Synchronous write; writes to r0 (waddr==0) are silently ignored
    always @(posedge clk) begin
        if (we && (waddr != 3'b000))
            mem[waddr] <= wdata;
    end

    // Asynchronous reads; r0 always returns 0 regardless of mem[0]
    assign rdata1 = (raddr1 == 3'b000) ? {DW{1'b0}} : mem[raddr1];
    assign rdata2 = (raddr2 == 3'b000) ? {DW{1'b0}} : mem[raddr2];

endmodule
