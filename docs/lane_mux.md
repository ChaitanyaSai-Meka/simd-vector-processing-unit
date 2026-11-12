# lane_mux — Per-Lane Operand B Selector

**File:** `rtl/lane_mux.v`
**Owner:** Dhanvin Vadlamudi (Role 2, Datapath RTL)

---

## What it does

`lane_mux` is a 2-to-1 multiplexer that selects the second operand (`operand_b`) for one lane's ALU. The choice is between:

- **`vs2_lane`** — the vector register's data for lane `i` (the normal SIMD case: `vd[i] = vs1[i] op vs2[i]`)
- **`scalar`** — a single 32-bit value from a scalar register, broadcast identically to all lanes (the `.S` suffix form: `vd[i] = vs1[i] op rs2`)

The `opb_sel` control signal (instruction bit 16) drives the selection.

## Why it is built this way

Having a per-lane mux (one instance inside `lane_array` per lane) means the selection is local to each lane and adds no extra wiring complexity. The scalar value is simply replicated to every mux input — this is exactly the "Lane MUXes" block the course requires. It enables benchmarks like threshold-clamp (`VSLT.S vd, vs1, r3`) without storing the threshold in a vector register first.

## Timing

Purely combinational. `operand_b` is valid the same cycle `vs2_lane`, `scalar`, and `opb_sel` are stable.

## Worked example: scalar broadcast

Instruction: `VADD.S v2, v0, r3` (add scalar `r3` to all lanes of `v0`)

- `r3 = 0x0000000A` (= 10)
- Lane 0: `vs2_lane = v1[0]` (ignored), `scalar = 10`, `opb_sel = 1` → `operand_b = 10`
- Lane 1: same scalar → `operand_b = 10`
- Lane 2: same scalar → `operand_b = 10`
- Lane 3: same scalar → `operand_b = 10`

All four lanes add 10 to their respective `v0[i]` values in the same cycle.
