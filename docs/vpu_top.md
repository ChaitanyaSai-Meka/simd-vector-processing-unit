# Integrated SIMD VPU

[`vpu_top.v`](../rtl/vpu_top.v) connects the instruction memory and PC, control
FSM, scalar and vector register files, lane array, write-back selector, and
data memory. The [block diagram](block_diagram.md#phase-ii-integrated-core)
shows how instructions and operands move through the core.

## Interface and timing

- `LANES` selects 1, 2, 4, or 8 lanes with the documented 32-bit `DW`. The
  vector buses are `LANES * DW` bits wide and lane 0 occupies the least
  significant word. Each memory depth determines the corresponding address
  width. Use addresses within the configured memory depth.
- On a rising edge with `rst=1`, the PC and counters return to zero, and
  `halted` clears. Memory and register contents follow their existing RTL
  behavior. Programs should initialize operands before using them.
- FETCH latches the instruction. In DECODE/EXECUTE, the controller updates the
  PC for each non-HALT instruction. A VST writes data memory at that edge.
  For loads and vector ALU operations, the same edge captures the selector's
  output in a full-width write-back register. That register keeps the result
  stable until WRITEBACK commits it to the destination. Scalar results use the
  controller's own result register.
- `instr_count` increments when an instruction completes. The HALT execute
  edge sets `halted` and counts toward both `instr_count` and `cycle_count`.
  HALT then holds the PC and both counters until reset.

## Worked example and smoke test

The testbench hand-encodes this program and preloads a different input value
for each lane at data address 4.

| PC | Instruction | Effect |
| --- | --- | --- |
| 0 | `SLI r1, 3` | Set the scalar base and addition operand. |
| 1 | `VLD v2, 1(r1)` | Load the vector at lane-group address 4. |
| 2 | `VADD.S v3, v2, r1` | Add 3 to each lane. For lane 0, `0x12345678` becomes `0x1234567b`. |
| 3 | `VST v3, -1(r1)` | Store the result at lane-group address 2. |
| 4 | `HALT` | Stop at PC 4. |

The bench compares the store to fixed words computed with the Python golden
model. It also checks the write edge, HALT, reset, and the five-instruction
total of 13 cycles.

```sh
make smoke
make test
```

Both targets accept `LANES=1`, `LANES=2`, `LANES=4`, or `LANES=8`.
`make test` runs the Phase I demo and the new smoke bench.

## Memory setup for system tests

To preload memories from a Verilog testbench, use `dut.u_imem.imem` and
`dut.u_dmem.mem`, where `dut` is the testbench's `vpu_top` instance. For the
[benchmark fixtures](verification.md#phase-ii-benchmark-fixtures), load the
instruction and data images at address zero. After HALT, read the requested
output groups from `dut.u_dmem.mem`.

The top-level ports expose PC, HALT, and the counters. For a meaningful
synthesis sweep, T7 needs to supply an instruction image and preserve the
internal vector datapath and data memory through synthesis.
