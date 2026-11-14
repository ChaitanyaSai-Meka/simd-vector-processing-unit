# Instruction Set Architecture (ISA) — SIMD Vector Processing Unit

**File:** `docs/isa.md`
**Owner:** Jagruthi Pulumati (Role 3, Control and Memory)

---

## Overview

The VPU uses 32-bit fixed-width instructions. All vector instructions operate lane-wise: `vd[i] = vs1[i] op vs2[i]` for `i = 0 .. LANES-1`. Every lane executes in the same clock cycle.

---

## Instruction Encoding

```
 31      26 25   23 22   20 19   17 16  15              0
┌──────────┬───────┬───────┬───────┬────┬────────────────┐
│ opcode   │  vd   │  vs1  │  vs2  │opb │   imm / offset │
│  [5:0]   │ [2:0] │ [2:0] │ [2:0] │sel │    [15:0]      │
└──────────┴───────┴───────┴───────┴────┴────────────────┘
```

- **`opcode[31:26]`** — instruction class and operation
- **`vd/rd [25:23]`** — destination: vector reg `v0..v7` or scalar reg `r0..r7`
- **`vs1/rs1 [22:20]`** — source operand 1
- **`vs2/rs2 [19:17]`** — source operand 2 (vector) or scalar for `.S` form
- **`opb_sel [16]`** — `0` = use `vs2` (vector lane data), `1` = broadcast `rs2` (scalar `.S` form)
- **`imm/offset [15:0]`** — sign-extended immediate or PC-relative offset

---

## Opcode Table

| Opcode `[31:26]` | Mnemonic | Type | Description |
|------------------|----------|------|-------------|
| `6'h00` | VADD | Vector ALU | `vd[i] = vs1[i] + vs2[i]` (32-bit wraparound) |
| `6'h01` | VSUB | Vector ALU | `vd[i] = vs1[i] - vs2[i]` (32-bit wraparound) |
| `6'h02` | VAND | Vector ALU | `vd[i] = vs1[i] & vs2[i]` |
| `6'h03` | VOR  | Vector ALU | `vd[i] = vs1[i] \| vs2[i]` |
| `6'h04` | VXOR | Vector ALU | `vd[i] = vs1[i] ^ vs2[i]` |
| `6'h05` | VSLT | Vector ALU | `vd[i] = ($signed(vs1[i]) < $signed(vs2[i])) ? 1 : 0` |
| `6'h06` | VEQ  | Vector ALU | `vd[i] = (vs1[i] == vs2[i]) ? 1 : 0` |
| `6'h07` | VSLL | Vector ALU | `vd[i] = vs1[i] << vs2[i][4:0]` |
| `6'h08` | VSRL | Vector ALU | `vd[i] = vs1[i] >> vs2[i][4:0]` (logical) |
| `6'h09` | VMUL | Vector ALU | `vd[i] = vs1[i] * vs2[i]` (low 32 bits, stretch goal) |
| `6'h10` | VLD  | Vector Mem | Load `LANES` words from `dmem[rs1 + imm]` into `vd` |
| `6'h11` | VST  | Vector Mem | Store `LANES` words from `vs1` to `dmem[rs1 + imm]` |
| `6'h20` | SADDI| Scalar ALU | `rd = rs1 + sign_ext(imm[15:0])` |
| `6'h21` | SLI  | Scalar ALU | `rd = sign_ext(imm[15:0])` |
| `6'h22` | BNE  | Branch     | If `rs1 != rs2`, PC = BNE address + sign_ext(offset[15:0]); otherwise PC = BNE address + 1 |
| `6'h3F` | HALT | Control    | Assert `halted`, freeze PC |

### Scalar-operand form (`.S` suffix)

Setting `opb_sel` (bit 16) on any Vector ALU instruction makes `lane_mux` broadcast scalar register `rs2` to all lanes as operand B:

```
VADD.S  vd, vs1, rs2   →  vd[i] = vs1[i] + rs2   (same scalar for all lanes)
VSLT.S  vd, vs1, rs2   →  vd[i] = (signed(vs1[i]) < signed(rs2)) ? 1 : 0
```

---

## Cycles per Instruction Class

The FSM has 3 states: **FETCH → DECODE/EXECUTE → WRITEBACK**.

| Instruction class | Cycles | FETCH | DECODE/EXECUTE | WRITEBACK |
|-------------------|--------|-------|----------------|-----------|
| Vector ALU (VADD..VSRL) | 3 | Fetch instr | Read regs, ALU computes | Write vd |
| Vector Load (VLD) | 3 | Fetch instr | Read rs1, compute addr, dmem read (async) | Write vd |
| Vector Store (VST) | 2 | Fetch instr | Read rs1+vs1, write dmem | — |
| Scalar ALU (SADDI, SLI) | 3 | Fetch instr | Compute result | Write rd |
| Branch (BNE) | 2 | Fetch instr | Compare rs1 and rs2, update PC | — |
| HALT | 2 | Fetch instr | Latch halted and hold the PC at HALT | — |

> VST and BNE return directly to FETCH after DECODE/EXECUTE. HALT holds the controller in DECODE/EXECUTE until reset. See [Control FSM](control_fsm.md) for PC enables and counter timing.

---

## Assembly Syntax

```
VADD  vd, vs1, vs2       # vector form:  vd[i] = vs1[i] + vs2[i]
VADD.S vd, vs1, rs2      # scalar form:  vd[i] = vs1[i] + rs2
VLD   vd, offset(rs1)    # load:  vd = dmem[rs1 + offset]
VST   vs1, offset(rs1)   # store: dmem[rs1 + offset] = vs1
SADDI rd, rs1, imm       # scalar add immediate
SLI   rd, imm            # scalar load immediate
BNE   rs1, rs2, label    # branch if not equal (PC-relative)
HALT                     # stop
```

Loop addresses increment by 1 lane-group per iteration. Each lane-group contains `LANES` 32-bit elements:

```asm
# B1 benchmark loop for LANES=4, N=64 (16 iterations)
    SLI   r1, 0          # i = 0 (dmem group address)
    SLI   r2, 16         # loop limit = N/LANES
loop:
    VLD   v0, 0(r1)      # load A[i*LANES .. i*LANES+LANES-1]
    VLD   v1, 64(r1)     # load B (offset by 64 groups = 256 words)
    VADD  v2, v0, v1     # C[i] = A[i] + B[i] for all lanes
    VST   v2, 128(r1)    # store C
    SADDI r1, r1, 1      # i++
    BNE   r1, r2, loop
    HALT
```
