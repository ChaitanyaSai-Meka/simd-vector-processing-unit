# lane_alu — Single Lane ALU

**File:** `rtl/lane_alu.v`
**Owner:** Dhanvin Vadlamudi (Role 2, Datapath RTL)

---

## What it does

`lane_alu` is a single 32-bit combinational ALU for one lane of the SIMD datapath. It takes two 32-bit operands `a` and `b` and an operation selector `alu_op[3:0]`, and produces a 32-bit `result` in the same clock cycle. Nine operations are supported.

## Why it is built this way

The lane is the fundamental unit of SIMD parallelism. By designing one clean, self-contained ALU and letting `lane_array` replicate it with a `generate` loop, the design scales from LANES=1 to LANES=8 by changing only a parameter — no RTL changes needed. Keeping it purely combinational (no registers) means `lane_array` controls all timing from above.

## Operation table

| `alu_op` | Mnemonic | Operation | Notes |
|----------|----------|-----------|-------|
| `4'h0` | VADD | `a + b` | 32-bit wraparound |
| `4'h1` | VSUB | `a - b` | 32-bit wraparound |
| `4'h2` | VAND | `a & b` | Bitwise |
| `4'h3` | VOR  | `a \| b` | Bitwise |
| `4'h4` | VXOR | `a ^ b` | Bitwise |
| `4'h5` | VSLT | `($signed(a) < $signed(b)) ? 1 : 0` | Signed compare, result is 1 or 0 |
| `4'h6` | VEQ  | `(a == b) ? 1 : 0` | Equality, result is 1 or 0 |
| `4'h7` | VSLL | `a << b[4:0]` | Logical left shift, shift amount = low 5 bits of b |
| `4'h8` | VSRL | `a >> b[4:0]` | Logical right shift (zero-fills), shift amount = low 5 bits of b |

## Timing

Purely combinational. No clock, no reset. `result` is valid within the propagation delay of the `case` logic after `a`, `b`, and `alu_op` are stable. All lanes in `lane_array` compute in the same clock cycle.

## Worked example: VSLT (signed less-than)

Inputs: `a = 0x80000000` (= −2147483648 signed), `b = 0x00000001` (= 1 signed), `alu_op = 4'h5`

Comparison: `$signed(0x80000000) < $signed(0x00000001)` → `−2147483648 < 1` → **true**

Output: `result = 0x00000001`

## Edge cases

- **Overflow (VADD/VSUB):** Silently wraps modulo 2³². Example: `0xFFFFFFFF + 1 = 0x00000000`.
- **Shift by 0 (VSLL/VSRL):** `a << 0 = a`. No change.
- **Shift by 31:** `0x00000001 << 31 = 0x80000000`.
- **VSLT with equal values:** Result is 0 (not strictly less than).
- **VSLT of two negatives:** `0x80000000 < 0xFFFFFFFF` → `−2147483648 < −1` → true → result = 1.
