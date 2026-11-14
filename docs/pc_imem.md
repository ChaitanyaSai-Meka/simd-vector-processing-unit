# pc_imem — Program Counter and Instruction Memory

**File:** `rtl/pc_imem.v`
**Owner:** Jagruthi Pulumati (Role 3, Control and Memory)

---

## What it does

`pc_imem` combines the program counter (PC) and the instruction memory (IMEM) in one module. The PC is a 32-bit word-addressed register. The IMEM is a synchronous-write, asynchronous-read ROM (in practice, a register array loaded from a hex file). The module presents the current instruction at `instr` combinationally based on the current PC.

Set `INIT_FILE` to a hex filename (for example, `imem_init.hex`) to preload instruction memory via `$readmemh`. The default empty string skips preloading.

## Why it is built this way

Combining PC and IMEM avoids a registered delay between "PC has new value" and "instruction is visible" — the new instruction appears combinationally in the next cycle. The Harvard architecture (separate IMEM and DMEM) means instruction fetches never conflict with data memory operations.

**`pc_en`** is asserted only in the FETCH state (by `control_unit`). In DECODE/EXECUTE and WRITEBACK states, `pc_en=0` holds the PC so the control unit continues to decode the same instruction. This is the simplest non-pipelined approach.

**`branch_en`** overrides the normal `PC+1` increment with `branch_target` when `pc_en=1`. Both signals are asserted simultaneously (in FETCH of a branch instruction whose target is already computed).

## Timing

- **`instr`:** combinational. Valid within gate delay after PC changes.
- **PC update:** synchronous. New PC value takes effect on the **next rising clock edge** after `pc_en=1`.
- **Reset:** synchronous. `pc = 0` on the rising edge when `rst=1`.

## Worked example: BNE taken

Before FETCH: `pc = 5`, `imem[5] = BNE r1, r2, -3` (target = `5 + (-3) = 2`)

FETCH cycle:
- `pc_en=1`, `branch_en=1`, `branch_target=2`
- Rising edge: `pc ← 2`

Next cycle: `instr = imem[2]` — execution continues from address 2.

## Worked example: sequential execution

PC=0,1,2,3... Each FETCH cycle: `pc_en=1`, `branch_en=0` → `pc ← pc + 1`.
