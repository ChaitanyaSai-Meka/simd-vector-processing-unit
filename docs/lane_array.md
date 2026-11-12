# lane_array — Parameterized SIMD Lane Array

**File:** `rtl/lane_array.v`
**Owner:** Dhanvin Vadlamudi (Role 2, Datapath RTL)

---

## What it does

`lane_array` is the core SIMD execution engine. It instantiates `LANES` copies of `lane_mux` + `lane_alu` using a Verilog `generate` loop. Every lane receives the same `alu_op` and `opb_sel` control signals but operates on its own slice of the flat vector buses. All lanes execute **in the same clock cycle** — this is what makes it SIMD.

Flat bus slicing: lane `i` occupies bits `[i*DW +: DW]` of the input and output buses.

## Why it is built this way

A `generate` loop is the standard synthesizable Verilog-2001 pattern for replicating identical hardware structures. Changing only the `LANES` parameter at instantiation time yields LANES=1 (scalar baseline), LANES=2, LANES=4, or LANES=8 — no RTL edits needed. This is the apples-to-apples comparison the spec requires.

## Timing

Fully combinational. All `LANES` ALUs compute in parallel. `result` is valid the same cycle the inputs are presented.

## Worked example: 4-lane VADD

Parameters: `LANES=4`, `DW=32`, `alu_op=4'h0` (VADD), `opb_sel=0`

```
vs1 = [0x00000001, 0x00000002, 0x00000003, 0x00000004]  (lanes 0-3)
vs2 = [0x0000000A, 0x0000000B, 0x0000000C, 0x0000000D]  (lanes 0-3)

Lane 0: 0x1 + 0xA = 0x0000000B
Lane 1: 0x2 + 0xB = 0x0000000D
Lane 2: 0x3 + 0xC = 0x0000000F
Lane 3: 0x4 + 0xD = 0x00000011

result = [0x0000000B, 0x0000000D, 0x0000000F, 0x00000011]
```

All four additions happen simultaneously — 1 cycle for 4 elements.

## Lane independence

Each lane's `lane_mux` and `lane_alu` are entirely independent instances. Changing lane 2's input affects only lane 2's output. The `generate` loop labels each instance `lane[i].u_mux` and `lane[i].u_alu`, making waveform debugging straightforward.
