# vreg_file — Vector Register File

**File:** `rtl/vreg_file.v`
**Owner:** Dhanvin Vadlamudi (Role 2, Datapath RTL)

---

## What it does

`vreg_file` holds 8 vector registers `v0..v7`. Each register is `LANES × DW` bits wide — for the default LANES=4, DW=32, that is 128 bits per register (4 × 32-bit lanes stored flat).

It has **2 asynchronous read ports** (for operands `vs1` and `vs2`) and **1 synchronous write port** (for the write-back result `vd`).

`v0` is a normal read/write register (not hardwired to zero). See `docs/decisions.md` D-002.

## Why it is built this way

- **2 read ports:** A binary vector ALU instruction needs two source operands simultaneously (`vs1` and `vs2`). One read port would require an extra cycle to fetch the second operand.
- **Async reads:** Combinational reads mean the FSM can present read addresses in DECODE/EXECUTE and get operands in the same cycle, feeding the ALU without an extra pipeline register.
- **Sync write:** A single write port on the rising edge is sufficient because the FSM issues one instruction at a time (non-pipelined).

## Timing

- Reads: combinational. `rdata1` and `rdata2` follow `raddr1`/`raddr2` after gate delay.
- Write: takes effect on the **next rising clock edge** after `we` is asserted with valid `waddr`/`wdata`.

## Worked example

Write `v2 = {0xDEADBEEF, 0xCAFEBABE, 0x12345678, 0xABCDABCD}` (lane 3 MSB, lane 0 LSB):

1. Assert `we=1`, `waddr=3'd2`, `wdata = {0xDEADBEEF, 0xCAFEBABE, 0x12345678, 0xABCDABCD}`.
2. Rising clock edge → `mem[2]` updated.
3. Set `raddr1=3'd2` → `rdata1[31:0] = 0xABCDABCD` (lane 0), `rdata1[63:32] = 0x12345678` (lane 1), etc.
