# sreg_file — Scalar Register File

**File:** `rtl/sreg_file.v`
**Owner:** Dhanvin Vadlamudi (Role 2, Datapath RTL)

---

## What it does

`sreg_file` holds 8 scalar 32-bit registers `r0..r7` for loop counters, addresses, and scalar operands. The design mirrors `vreg_file` but with 32-bit width.

**`r0` is permanently 0:** any write to address `3'b000` is silently discarded, and any read from address `3'b000` returns `32'h0` regardless of what is stored internally.

## Why it is built this way

- **r0 = 0 always:** This is the RISC convention. It provides a free zero constant for comparisons (`BNE rs, r0, offset`) and zeroing vectors (`VSUB vd, vd, vd` via scalar 0), without needing a dedicated zero-load instruction.
- **Same async-read / sync-write policy as `vreg_file`:** Keeps the FSM cycle structure identical for both register files — no special casing in the control logic.
- **Write guard on r0:** Implemented in the write `always` block (`if (we && waddr != 0)`), and the read mux forces 0 for address 0. This double protection ensures r0 stays 0 even if the control unit accidentally asserts `we` with `waddr=0`.

## Timing

Identical to `vreg_file`: combinational reads, synchronous write (next rising edge).

## Worked example: r0 stays zero

1. Assert `we=1`, `waddr=3'd0`, `wdata=32'hDEADBEEF`.
2. Rising clock edge → write is **ignored** (guard condition fails).
3. Read `raddr1=3'd0` → `rdata1 = 32'h00000000`. ✅

## Worked example: normal write

1. Assert `we=1`, `waddr=3'd5`, `wdata=32'd64`.
2. Rising edge → `mem[5] = 64`.
3. Read `raddr2=3'd5` → `rdata2 = 32'd64`. ✅
