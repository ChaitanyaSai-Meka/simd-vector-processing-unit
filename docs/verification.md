# Verification Plan and Strategy

**File:** `docs/verification.md`
**Owner:** Rakshita (Role 4, Verification)

---

## Overview

Verification of the SIMD VPU follows a **golden-model-first** strategy. The Python script `verif/golden.py` is the reference — RTL output is never compared against itself. A test passes only when the testbench prints `PASS` and exits 0; `FAIL` lines include expected vs actual values, and failed checks return a nonzero simulator exit status.

---

## Verification Files

| File | Purpose |
|------|---------|
| `verif/golden.py` | Python reference for the base ALU ops and three benchmarks. Generates data-memory and expected-output hex. |
| `verif/asm.py` | Two-pass assembler. Generates instruction-memory hex from a `.s` file. |
| `verif/programs/b1.s`, `b2.s`, `b3.s` | Benchmark sources shared across all four lane counts. |
| `tb/lane_alu_tb.v` | Unit test for `lane_alu`: every opcode, all edge cases |
| `tb/lane_mux_tb.v` | Unit test for `lane_mux`: opb_sel=0/1, dynamic switching |
| `tb/vreg_file_tb.v` | Unit test for `vreg_file`: all 8 regs, both ports, sync/async timing |
| `tb/sreg_file_tb.v` | Unit test for `sreg_file`: r0 invariant, write guard |
| `tb/lane_array_tb.v` | Parameterized test for `lane_array` at LANES=1, 4, 8 |
| `tb/result_combiner_tb.v` | Unit test for the ALU and memory-data write-back selections |
| `tb/dmem_tb.v` | Unit test for `dmem`: wide port, all lanes, we guard |
| `tb/pc_imem_tb.v` | Unit test for `pc_imem`: reset, sequential, branch |
| `tb/vpu_demo_top_tb.v` | Integrated datapath test: VADD, VSUB, VAND, vector VSLT, VADD overflow |

---

## Test Strategy

### 1. Unit Tests (Phase I)

Phase I uses self-checking module and integration tests. Tests are:
- **Directed:** specific corner cases crafted by hand
- **Self-checking:** testbench computes expected value and compares; prints `PASS` or `FAIL expected=X actual=Y`

### 2. Edge Cases Covered

| Category | Values tested |
|----------|--------------|
| Boundary values | 0, 1, −1 (`0xFFFFFFFF`), `0x7FFFFFFF` (INT_MAX), `0x80000000` (INT_MIN) |
| Overflow (VADD) | `0xFFFFFFFF + 1 = 0x00000000` |
| Underflow (VSUB) | `0x00000000 - 1 = 0xFFFFFFFF` |
| Signed compare | INT_MIN < 1, −1 < 1, 1 < INT_MIN (false) |
| Shift by 0 | `a << 0 = a`, `a >> 0 = a` |
| Shift by 31 | `1 << 31 = 0x80000000`, `0x80000000 >> 31 = 1` |
| Shift uses low 5 bits | `shift=32` treated as `shift=0` |
| r0 write guard | write to sreg_file addr=0 silently dropped |
| Same-cycle R/W | vreg_file async read returns old data while sync write is pending |
| we=0 guard | dmem and register files do not write when we=0 |

### 3. Lane Independence Test

In `lane_array_tb`: set all lanes to the same input, change only lane 0's input, confirm only lane 0's output changes. This verifies the `generate` loop creates truly independent instances.

### 4. LANES Parameter Sweep

`lane_array_tb` is compiled three times with `-DLANES=1`, `-DLANES=4`, `-DLANES=8`. The same test logic runs at each width — the parameterized `generate` loop is verified at all required lane counts.

### 5. Golden Model Self-Test

`python3 verif/golden.py --self-test` runs built-in assertions on the Python model itself before it is used to generate hex files. This catches bugs in the reference model before they contaminate the testbench.

### 6. Vector Compare and Scalar Broadcast

In `vpu_demo_top_tb` T4, `VSLT v6, v0, v5` compares `v0` lane by lane against `v5 = [5, 5, 5, 5]` in the four-lane run, with `opb_sel = 0`. Scalar broadcast (`opb_sel = 1`) is exercised separately by `lane_mux_tb` and `lane_array_tb`.

---

## How to Run

```bash
# Run all unit tests (after make is set up by Lalithendra):
make test

# Or run individually:
# lane_alu
iverilog -o /tmp/la_tb.vvp tb/lane_alu_tb.v rtl/lane_alu.v && vvp /tmp/la_tb.vvp

# lane_mux
iverilog -o /tmp/lm_tb.vvp tb/lane_mux_tb.v rtl/lane_mux.v && vvp /tmp/lm_tb.vvp

# lane_array at LANES=1, 4, 8
for L in 1 4 8; do
  iverilog -DLANES=$L -o /tmp/lar_tb_L${L}.vvp \
    tb/lane_array_tb.v rtl/lane_array.v rtl/lane_alu.v rtl/lane_mux.v
  vvp /tmp/lar_tb_L${L}.vvp
done

# vreg_file
iverilog -o /tmp/vrf_tb.vvp tb/vreg_file_tb.v rtl/vreg_file.v && vvp /tmp/vrf_tb.vvp

# sreg_file
iverilog -o /tmp/srf_tb.vvp tb/sreg_file_tb.v rtl/sreg_file.v && vvp /tmp/srf_tb.vvp

# dmem
iverilog -o /tmp/dmem_tb.vvp tb/dmem_tb.v rtl/dmem.v && vvp /tmp/dmem_tb.vvp

# pc_imem
iverilog -o /tmp/pci_tb.vvp tb/pc_imem_tb.v rtl/pc_imem.v && vvp /tmp/pci_tb.vvp
```

---

## Phase II benchmark fixtures

Each benchmark uses the same 64 input elements at `LANES=1,2,4,8`. Regenerate
the fixtures from the repository root with Python 3:

```sh
python3 verif/golden.py --all
for lanes in 1 2 4 8; do
    for bench in b1 b2 b3; do
        python3 verif/asm.py "verif/programs/${bench}.s" --lanes "$lanes" \
            -o "verif/data/${bench}_imem_L${lanes}.hex"
    done
done
```

For one case, use `golden.py --bench B1 --lanes 4` and assemble `b1.s` at
the same width. Both scripts accept `--n` for a positive element count divisible
by `LANES`. Ensure that the resulting addresses fit the configured data memory.

### Assembler

The assembler reads the [base ISA](isa.md), accepts case-insensitive mnemonics
and register names, and writes one eight-digit hex word per instruction. Use
`#` or `;` for comments. A label can stand alone or precede an instruction.
`BNE` uses the address of its own instruction as the base for a label offset
and also accepts an explicit signed displacement. For example, a branch at
instruction 7 to a label at instruction 2 encodes `-5` as `fffb`. Numeric
immediates accept values from `-32768` to `32767` in decimal or prefixed
notation such as `-0x20`. The `.S` suffix requires a scalar last operand and
sets bit 16. The optional VMUL opcode is reserved.

`LANES`, `N`, `GROUPS`, `B_BASE`, and `C_BASE` are built-in constants.
`GROUPS = N / LANES`, `B_BASE = GROUPS`, and `C_BASE = 2 * GROUPS`. A
data-memory address selects an entire lane group, so the loop advances by one
address per iteration. The loop bound and region offsets change with the lane
count. For example, at four lanes, B1 processes 16 groups and loads B at
`16(r1)` and stores C at `32(r1)`.

### Data and expected output

For each `<bench>` and lane count `<L>`, the testbench can load
`<bench>_imem_L<L>.hex` at instruction address 0 and
`<bench>_dmem_L<L>.hex` at data address 0. The data image contains
`3 * GROUPS` lines in order:

| Group addresses | Contents |
| --- | --- |
| `0` through `GROUPS - 1` | Input A |
| `GROUPS` through `2 * GROUPS - 1` | Input B for B1 and B3, zero padding for B2 |
| `2 * GROUPS` through `3 * GROUPS - 1` | Initially zero output region C |

Each line packs `LANES` 32-bit words with lane 0 at the least-significant end
of the hex value. After HALT, compare the C region in order against the
`GROUPS` lines of `<bench>_C_expected_L<L>.hex`. Separate A and B inputs are
also generated. B2 retains a separate threshold image for verification. Its
program gets the threshold from a scalar register.

- **B1** adds A and B with 32-bit wraparound.
- **B2** computes the signed minimum of A and `4096`. It turns the 0-or-1 result of `VSLT.S` into a mask with `0 - cmp` and blends A and T. The golden input includes `INT_MIN`, `-1`, the three values around the cutoff, and `INT_MAX`.
- **B3** computes `(A & 0xffff0000) ^ (B << 2)` with 32-bit truncation. The program builds the mask before the loop and broadcasts the shift count with `VSLL.S`.

---

## Waveform

A 4-lane VADD waveform is captured for the demo video. To regenerate:

```bash
make wave   # (once Makefile is in place from Lalithendra's Step 5)
```

This dumps `vpu_demo_top_tb` to a VCD and opens it in GTKWave. The key signals to show:
- `clk`, `vs1`, `vs2`, `alu_op`, `result` — verify all 4 lanes update simultaneously on the rising edge.

---

## 5 Interview Questions (Rakshita)

1. What does `opb_sel=1` do in `lane_mux`, and which instruction type uses it?
2. Why does `vreg_file` use asynchronous reads instead of registered (pipelined) reads?
3. How does the golden model handle 32-bit overflow in VADD? What is `0xFFFFFFFF + 1`?
4. What is the lane independence test, and why is it important?
5. How does the testbench verify that r0 in `sreg_file` is permanently zero?
