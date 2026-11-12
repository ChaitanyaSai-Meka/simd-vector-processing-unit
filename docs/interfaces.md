# Interface Contract — SIMD Vector Processing Unit

**Owner:** Kasula Lalithendra (Role 1, Architecture Lead)
**Status:** Frozen at end of Phase 0. Any change must be committed with this file and must list every affected module.

---

## Global Parameters

```verilog
parameter LANES = 4;   // number of parallel lanes; valid: 1, 2, 4, 8
parameter DW    = 32;  // lane data width in bits (fixed at 32)
```

## Bus Layout Convention

Vector buses are **flat**: `[LANES*DW-1:0]`.
Lane `i` occupies bits `[i*DW +: DW]` (i.e., `[(i+1)*DW-1 : i*DW]`).

```
 Lane 3 (MSB side)   Lane 2         Lane 1         Lane 0 (LSB side)
 [127:96]            [95:64]        [63:32]        [31:0]
```

For LANES=4, DW=32: total bus width = 128 bits.

---

## ALU Operation Encoding (`alu_op[3:0]`)

| `alu_op` | Mnemonic | Operation |
|----------|----------|-----------|
| `4'h0`   | VADD     | `a + b` |
| `4'h1`   | VSUB     | `a - b` |
| `4'h2`   | VAND     | `a & b` |
| `4'h3`   | VOR      | `a \| b` |
| `4'h4`   | VXOR     | `a ^ b` |
| `4'h5`   | VSLT     | `($signed(a) < $signed(b)) ? 1 : 0` |
| `4'h6`   | VEQ      | `(a == b) ? 1 : 0` |
| `4'h7`   | VSLL     | `a << b[4:0]` |
| `4'h8`   | VSRL     | `a >> b[4:0]` |
| `4'h9`   | VMUL     | `a * b` (low 32 bits, stretch goal) |

---

## Instruction Encoding (32-bit fixed-width)

```
[31:26]  opcode (6 bits)
[25:23]  vd / rd — destination register index (3 bits → 8 registers)
[22:20]  vs1 / rs1 — source register 1 index (3 bits)
[19:17]  vs2 / rs2 — source register 2 index (3 bits)
[16]     opb_sel — 0: use vs2 (vector), 1: broadcast rs2 (scalar .S form)
[15:0]   imm / offset — sign-extended where relevant
```

### Opcode Table

| Opcode `[31:26]` | Mnemonic | Type |
|------------------|----------|------|
| `6'h00`          | VADD     | Vector ALU |
| `6'h01`          | VSUB     | Vector ALU |
| `6'h02`          | VAND     | Vector ALU |
| `6'h03`          | VOR      | Vector ALU |
| `6'h04`          | VXOR     | Vector ALU |
| `6'h05`          | VSLT     | Vector ALU |
| `6'h06`          | VEQ      | Vector ALU |
| `6'h07`          | VSLL     | Vector ALU |
| `6'h08`          | VSRL     | Vector ALU |
| `6'h09`          | VMUL     | Vector ALU (stretch) |
| `6'h10`          | VLD      | Vector Memory Load |
| `6'h11`          | VST      | Vector Memory Store |
| `6'h20`          | SADDI    | Scalar ALU |
| `6'h21`          | SLI      | Scalar Load Immediate |
| `6'h22`          | BNE      | Branch |
| `6'h3F`          | HALT     | Control |

---

## Module Port Lists

### `lane_alu.v`

Combinational. One lane's 32-bit ALU.

```verilog
module lane_alu #(
    parameter DW = 32
) (
    input  [DW-1:0]  a,        // operand A (from vreg_file lane i)
    input  [DW-1:0]  b,        // operand B (from lane_mux output lane i)
    input  [3:0]     alu_op,   // operation select (see ALU opcode table)
    output [DW-1:0]  result    // combinational result
);
```

**Timing:** Pure combinational, no clock. Result is valid the same cycle operands are presented.

---

### `lane_mux.v`

Combinational. Selects per-lane operand B.

```verilog
module lane_mux #(
    parameter DW = 32
) (
    input  [DW-1:0]  vs2_lane,   // vector operand: vs2[i*DW +: DW]
    input  [DW-1:0]  scalar,     // scalar broadcast: sreg_file rdata (same value all lanes)
    input            opb_sel,    // 0 = use vs2_lane, 1 = use scalar broadcast
    output [DW-1:0]  operand_b   // selected operand B → lane_alu.b
);
```

**Timing:** Pure combinational.

---

### `lane_array.v`

Combinational. Instantiates `LANES` copies of `lane_alu` through a `generate` loop, each with its own `lane_mux`.

```verilog
module lane_array #(
    parameter LANES = 4,
    parameter DW    = 32
) (
    input  [LANES*DW-1:0]  vs1,       // vector operand A (flat bus)
    input  [LANES*DW-1:0]  vs2,       // vector operand B — vector source (flat bus)
    input  [DW-1:0]        scalar,    // scalar broadcast value (same for all lanes)
    input                  opb_sel,   // 0 = use vs2 per lane, 1 = broadcast scalar
    input  [3:0]           alu_op,    // shared operation for all lanes
    output [LANES*DW-1:0]  result     // flat result bus, lane i at [i*DW +: DW]
);
```

**Timing:** Pure combinational. All lanes execute in the same cycle.

---

### `vreg_file.v`

8 vector registers, each `LANES*DW` bits wide.
- **Write:** synchronous, rising-edge clock, write-enable gated.
- **Read:** asynchronous (combinational). Two independent read ports.
- `v0` is **not** hardwired to zero.

```verilog
module vreg_file #(
    parameter LANES = 4,
    parameter DW    = 32
) (
    input                   clk,     // rising-edge clock
    // Write port
    input                   we,      // write enable (active high)
    input  [2:0]            waddr,   // write address: 0..7 → v0..v7
    input  [LANES*DW-1:0]   wdata,   // data to write
    // Read port 1 (vs1)
    input  [2:0]            raddr1,
    output [LANES*DW-1:0]   rdata1,
    // Read port 2 (vs2)
    input  [2:0]            raddr2,
    output [LANES*DW-1:0]   rdata2
);
```

**Timing:** Read is combinational (async). Write takes effect on the **next** rising edge after `we` is asserted.

---

### `sreg_file.v`

8 scalar registers (`r0..r7`), each `DW` bits wide.
- `r0` is hardwired to `0`; writes to address `3'b000` are silently ignored.
- **Write:** synchronous. **Read:** asynchronous.
- Two independent read ports.

```verilog
module sreg_file #(
    parameter DW = 32
) (
    input              clk,
    // Write port
    input              we,
    input  [2:0]       waddr,
    input  [DW-1:0]    wdata,
    // Read port 1 (rs1)
    input  [2:0]       raddr1,
    output [DW-1:0]    rdata1,
    // Read port 2 (rs2)
    input  [2:0]       raddr2,
    output [DW-1:0]    rdata2
);
```

---

### `result_combiner.v`

Combinational. Selects between ALU result and memory load data for write-back.

```verilog
module result_combiner #(
    parameter LANES = 4,
    parameter DW    = 32
) (
    input  [LANES*DW-1:0]  alu_result,  // from lane_array.result
    input  [LANES*DW-1:0]  mem_rdata,   // from dmem.rdata
    input                   res_sel,     // 0 = ALU result, 1 = memory load
    output [LANES*DW-1:0]  wb_data      // write-back data → vreg_file.wdata
);
```

---

### `dmem.v`

Data memory. One wide read/write port of `LANES*DW` bits.
- Word-addressed by **lane group**: address `A` selects words `[A*LANES .. A*LANES+LANES-1]`.
- Loaded from a hex file at simulation start via `$readmemh`.
- **Write:** synchronous. **Read:** asynchronous (combinational).

```verilog
module dmem #(
    parameter LANES = 4,
    parameter DW    = 32,
    parameter DEPTH = 256    // number of lane-groups (total words = DEPTH * LANES)
) (
    input                   clk,
    input                   we,      // write enable
    input  [31:0]           addr,    // lane-group word address
    input  [LANES*DW-1:0]   wdata,
    output [LANES*DW-1:0]   rdata    // combinational read
);
```

---

### `pc_imem.v`

Program counter + instruction memory.
- PC increments by 1 (word-addressed) each cycle unless a branch is taken.
- Instruction memory loaded from hex file via `$readmemh`.
- Synchronous reset sets PC to 0.

```verilog
module pc_imem #(
    parameter IMEM_DEPTH = 256
) (
    input              clk,
    input              rst,       // synchronous active-high reset
    input              pc_en,     // 1 = advance PC (FETCH phase)
    input              branch_en, // 1 = load branch_target instead of PC+1
    input  [31:0]      branch_target,
    output reg [31:0]  pc,        // current program counter
    output [31:0]      instr      // instruction at current PC (combinational)
);
```

---

### `vpu_demo_top.v` (Step 5 — Lalithendra)

Demo datapath for Phase I. Wires all modules together without a full control FSM. Testbench drives control signals directly.

```verilog
module vpu_demo_top #(
    parameter LANES = 4,
    parameter DW    = 32
) (
    input              clk,
    input              rst,
    // Test-bench control inputs
    input  [2:0]       vs1_addr,
    input  [2:0]       vs2_addr,
    input  [2:0]       vd_addr,
    input  [2:0]       rs2_addr,
    input  [3:0]       alu_op,
    input              opb_sel,
    input              vreg_we,
    // Write-back data (from vreg_file for readout)
    output [LANES*DW-1:0] result_out,
    // Direct write port for loading test vectors
    input  [2:0]            load_addr,
    input  [LANES*DW-1:0]   load_data,
    input                   load_we
);
```

---

### `vpu_top.v` (Phase II — full system top)

Full system top, wires every module including `control_unit` and `pc_imem`. Debug ports for benchmarks.

```verilog
module vpu_top #(
    parameter LANES      = 4,
    parameter DW         = 32,
    parameter IMEM_DEPTH = 256,
    parameter DMEM_DEPTH = 256
) (
    input              clk,
    input              rst,
    output             halted,       // high after HALT, stays high until rst
    // Debug / benchmark ports
    output [31:0]      pc,
    output [31:0]      cycle_count,  // cycles from rst until halted
    output [31:0]      instr_count
);
```

---

## Change Log

| Date | Author | Change | Modules affected |
|------|--------|--------|-----------------|
| 2026-11-12 | Kasula Lalithendra | Initial interface contract (Phase 0) | All |
