// dmem.v
// Data memory with one wide port of LANES*DW bits.
// Word-addressed by lane-group: address A selects words [A*LANES .. A*LANES+LANES-1].
// Asynchronous read, synchronous write. Loaded from hex file via $readmemh.
// Part of: SIMD Vector Processing Unit, LANE BREAKERS
// Owner: Jagruthi Pulumati (Role 3, Control and Memory)

`timescale 1ns/1ps

module dmem #(
    parameter LANES   = 4,
    parameter DW      = 32,
    parameter DEPTH   = 256,   // number of lane-groups storable
    parameter ADDR_W  = 8      // ceil(log2(DEPTH)); must match DEPTH
) (
    input                    clk,
    input                    we,      // write enable (active high, synchronous)
    input  [31:0]            addr,    // lane-group word address
    input  [LANES*DW-1:0]    wdata,   // data to write (LANES*DW bits wide)
    output [LANES*DW-1:0]    rdata    // combinational read output
);

    reg [LANES*DW-1:0] mem [0:DEPTH-1];

    // Initialise from hex file when provided; silently skipped if file absent
    initial begin
        $readmemh("dmem_init.hex", mem);
    end

    // Asynchronous read
    assign rdata = mem[addr[ADDR_W-1:0]];

    // Synchronous write
    always @(posedge clk) begin
        if (we)
            mem[addr[ADDR_W-1:0]] <= wdata;
    end

endmodule
