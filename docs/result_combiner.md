# result_combiner — Write-Back Data Selector

**File:** `rtl/result_combiner.v`
**Owner:** Dhanvin Vadlamudi (Role 2, Datapath RTL)

---

## What it does

`result_combiner` is a `LANES*DW`-bit 2-to-1 multiplexer that selects the data to write back into `vreg_file`. Two sources compete for the write port:

- **`alu_result`** — the output of `lane_array` (for all vector ALU instructions: VADD, VSUB, etc.)
- **`mem_rdata`** — data loaded from `dmem` (for the VLD instruction)

The `res_sel` control signal (driven by `control_unit`) makes the selection:
- `res_sel = 0` → write ALU result
- `res_sel = 1` → write memory load data

## Why it is built this way

Both the ALU and the data memory produce results that need to go into a vector register. By routing both through a single combinational mux, `vreg_file` needs only **one write port**. The control unit raises `res_sel` only on a VLD instruction. For all other instructions `res_sel = 0`, passing the ALU result through transparently.

## Timing

Purely combinational. `wb_data` is valid the same cycle as `alu_result`, `mem_rdata`, and `res_sel`.

## Worked example: VLD instruction

- `dmem` outputs `mem_rdata = {0xAABBCCDD, 0x11223344, 0x55667788, 0x99AABBCC}` (4 lanes)
- `alu_result` = whatever the ALU computed (irrelevant)
- `res_sel = 1` (control unit sets this for VLD)
- `wb_data = {0xAABBCCDD, 0x11223344, 0x55667788, 0x99AABBCC}` → written to `vreg_file`
