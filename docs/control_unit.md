# Control Unit

[`control_unit.v`](../rtl/control_unit.v) turns one 32-bit instruction into register, memory, ALU, and PC controls. It uses the same control signals for every lane. Keeping the fetched word in a register lets the PC advance in DECODE/EXECUTE while the current instruction still controls WRITEBACK.

## Wiring for the integrated top

| Signals | Connection |
| --- | --- |
| `instr`, `pc`, `pc_en`, `branch_en`, `branch_target` | Connect directly to the matching `pc_imem` ports. `branch_target` matters when `branch_en` is high. |
| `rs1_addr`, `rs2_addr`, `rs1_data`, `rs2_data` | Connect to the two scalar register read ports. Also pass `rs2_data` to the lane datapath as the broadcast scalar. |
| `rd_addr`, `sreg_wdata`, `sreg_we` | Connect to the scalar write port. The controller saves the SADDI or SLI result at the end of DECODE/EXECUTE. |
| `vs1_addr`, `vs2_addr`, `vd_addr`, `vreg_we` | Connect to the vector register read addresses, write address, and write enable. For VST, `vs1_addr` selects the store data on read port 1. |
| `dmem_addr`, `dmem_we` | Connect to the data memory address and write enable. Drive the memory write data from vector read port 1. |
| `alu_op`, `opb_sel`, `res_sel` | Drive the lane ALU, broadcast select, and result combiner. `res_sel=1` selects load data in DECODE/EXECUTE and WRITEBACK. |
| `halted`, `cycle_count`, `instr_count` | Export from the top as status and benchmark counters. |

The controller has no lane-width ports. The integrated datapath can capture the result combiner's vector output at the DECODE/EXECUTE edge, qualified by `pc_en`, and feed that register to vector write-back. `vreg_we` qualifies the write on the following edge. The vector data captured for stores and branches is unused. Register indices and arithmetic buses are meaningful for the active instruction in the states that use them. See the [FSM timing table](control_fsm.md).

## Worked example

For `VLD v4, -2(r3)` with `r3=10` and PC at 20:

1. FETCH latches the load instruction and holds PC at 20.
2. DECODE/EXECUTE selects `r3`, computes lane-group address `10 - 2 = 8`, and selects the asynchronous memory output. At the rising edge, the datapath can save that vector and the PC advances to 21.
3. WRITEBACK asserts `vreg_we` with destination `v4`. At the rising edge the vector register is written and `instr_count` increments. The load accounts for three cycles.

## Verification

```sh
iverilog -g2001 -Wall -s control_unit_tb -o /tmp/control_unit_tb.vvp \
    tb/control_unit_tb.v rtl/control_unit.v rtl/pc_imem.v rtl/dmem.v rtl/sreg_file.v
vvp /tmp/control_unit_tb.vvp
```

The testbench checks the ISA control word cycle by cycle for every required opcode, including both forms of each vector ALU opcode. It exercises the actual PC, scalar register file, and data memory ports. It checks signed offsets, taken and untaken branches, HALT, and reset during pending writes. Vector ALU results are covered separately by Phase I verification.
