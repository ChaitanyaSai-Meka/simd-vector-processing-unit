# SIMD Vector Processing Unit: Full Project Spec

**Course:** Modern Computer Architecture, B.Tech CS & AI (Rishihood University / NST)
**Team:** LANE BREAKERS (5 members)
**Project:** #11, SIMD Vector Processing Unit (Intermediate+, SIMD / Parallelism)

This file is the single source of truth. It is written so a coding agent can build the whole project from it, and so each team member can own one slice.

---

## 0. Instructions for the Coding Agent

Read this whole file before writing anything.

1. Build in the phases from section 9, in order. Do not start a phase until the previous phase's tests pass.
2. Interfaces in section 5 are a contract. If you must change one, update `docs/interfaces.md` in the same commit and list every module affected.
3. Every RTL module gets its own self-checking testbench. "Looks right in the waveform" is not a pass. A test passes only when the testbench prints `PASS` and exits 0, and prints `FAIL` with expected vs actual otherwise.
4. Verify against the Python golden model (section 7), never against the RTL's own output.
5. Synthesizable Verilog-2001 only for RTL. No `initial` delays, no `#` delays, no `$display` inside RTL files. These are allowed in testbenches only. No SystemVerilog unless the toolchain check in section 8 passes.
6. Commit after every phase with a message naming the phase.
7. The students must be able to explain and defend every module in a live demo. Next to each module write a short `docs/<module>.md` covering: what it does, why it is built this way, the timing, and one worked example. Plain language, no filler.
8. When something is ambiguous, choose the simplest option that satisfies the requirements, record the choice in `docs/decisions.md`, and continue. Do not stall.

---

## 1. Goal

Design, implement, verify, and synthesize a small SIMD (Single Instruction, Multiple Data) vector processing unit in Verilog. One instruction operates on all lanes in parallel. Then measure how much faster it is than a scalar baseline, and what it costs in FPGA resources and clock frequency.

**Required by the course:**
- Vector register file, multiple ALUs, vector control unit, lane MUXes, result combiner, optional scalar interface
- Operations: vector ADD, SUB, AND, OR, comparison; optionally shifts and multiply
- Four or eight lanes
- Scalar and SIMD versions of the same workload, vector results verified
- Measured: cycle count, throughput, FPGA resource usage, maximum frequency
- Common requirements: block diagram, state description, modular synthesizable RTL, directed testbench, waveforms, at least one quantitative metric, synthesis results (utilization and Fmax), baseline comparison, final report, live demo

---

## 2. Architecture Summary

- Parameterized lane count `LANES` (default 4; must also work at 1, 2, 8)
- Lane width `DW = 32` bits
- 8 vector registers `v0..v7`, each `LANES * DW` bits wide. `v0` is **NOT** hardwired to zero (keep it simple, use an explicit zero via `VSUB vX, vX, vX` if needed)
- 8 scalar registers `r0..r7` (`r0` hardwired to 0) for loop counters and addresses
- Separate instruction memory and data memory (Harvard style)
- Data memory has one wide port of `LANES * DW` bits for vector load/store, word-addressed by lane group. Scalar baseline is the same design with `LANES = 1`
- Single-issue, non-pipelined FSM with deterministic cycle counts: FETCH, DECODE/EXECUTE, WRITEBACK. Document exact cycles per instruction class in `docs/isa.md`
- Lanes are fully independent in the ALU stage. No cross-lane operations in the base design

**Baseline for comparison:** the identical RTL built with `LANES = 1` (the scalar machine), plus a lane sweep of 1, 2, 4, 8.

---

## 3. Instruction Set

32-bit fixed-width instructions. Recommended encoding:

```
Vector ALU (lane-wise, vd[i] = vs1[i] op vs2[i]):
[31:26]  opcode
[25:23]  vd or rd
[22:20]  vs1 or rs1
[19:17]  vs2 or rs2
[16:0]   imm / offset (sign-extended where relevant)
```

### Vector ALU opcodes

| Mnemonic | Operation |
|----------|-----------|
| VADD  | add |
| VSUB  | subtract |
| VAND  | bitwise and |
| VOR   | bitwise or |
| VXOR  | bitwise xor |
| VSLT  | signed less-than, lane result is 1 or 0 |
| VEQ   | equal, lane result is 1 or 0 |
| VSLL  | shift left logical, shift amount from low 5 bits of vs2[i] |
| VSRL  | shift right logical, shift amount from low 5 bits of vs2[i] |
| VMUL  | optional stretch goal, low 32 bits of product |

Scalar-operand form: setting instruction bit 16 (suffix `.S`, e.g. `VSLT.S vd, vs1, rs2`) makes `lane_mux` broadcast scalar register `rs2` to every lane as operand B.

### Vector memory

| Mnemonic | Operation |
|----------|-----------|
| VLD vd, imm(rs1) | load LANES consecutive words from data memory at word address rs1 + imm |
| VST vs1, imm(rs1) | store LANES consecutive words |

### Scalar / control

| Mnemonic | Operation |
|----------|-----------|
| SADDI rd, rs1, imm | rd = rs1 + imm |
| SLI rd, imm | rd = imm |
| BNE rs1, rs2, off | branch if not equal, PC-relative |
| HALT | stop, raise `halted` |

Address increments in loops are in units of `LANES` words, so the same program binary does not work across lane counts. Generate programs per LANES with the Python assembler (section 7).

---

## 4. Module List

All under `rtl/`.

| Module | Responsibility |
|--------|---------------|
| `vpu_top.v` | Top level. Wires everything. Exposes `clk`, `rst`, `halted` and debug ports |
| `pc_imem.v` | Program counter and instruction memory (`$readmemh` loaded) |
| `control_unit.v` | Decoder and FSM. Produces all control signals. Owns the cycle behaviour |
| `vreg_file.v` | 8 vector registers, 2 read ports, 1 write port |
| `sreg_file.v` | 8 scalar registers, `r0 = 0`, 2 read ports, 1 write port |
| `lane_alu.v` | ONE lane's ALU (32-bit, all ops from section 3) |
| `lane_array.v` | Generates LANES copies of `lane_alu` with a `generate` loop |
| `lane_mux.v` | Per-lane operand B select: `vs2[i]` or the scalar register broadcast to every lane (`opb_sel`). This is the "Lane MUXes" block the course requires |
| `result_combiner.v` | Packs lane results into one `LANES*DW` write-back bus, selects between ALU result and memory load data |
| `dmem.v` | Data memory with wide port, `$readmemh` init for tests |
| `top_tb.v` | Full-system testbench that runs assembled programs |

---

## 5. Interface Contract

Define exact port lists in `docs/interfaces.md`. Fixed conventions:

- Single clock `clk`, synchronous active-high reset `rst`
- Vector buses are flat: `[LANES*DW-1:0]`, lane `i` occupies bits `[i*DW +: DW]`
- Register files: synchronous write, asynchronous read (keeps FSM cycle counts simple)
- Control signals are named `<what>_en`, `<what>_sel`, `alu_op[3:0]`
- `halted` goes high on HALT and stays high until reset
- Debug ports exported from `vpu_top`: `pc`, `cycle_count` (32-bit, counts cycles from reset until halted), `instr_count`
- `cycle_count` is the primary measurement hook for all benchmarks. Do not compute cycles any other way.

---

## 6. Benchmarks

Each benchmark has a Python reference, an assembly program, and a testbench check. Use N = 64 elements unless noted.

| ID | Workload | Why |
|----|----------|-----|
| B1 | `C[i] = A[i] + B[i]` | Pure data parallelism, best case |
| B2 | Threshold/clamp: `C[i] = (A[i] < T) ? A[i] : T` using VSLT, mask from `0 - cmp`, VAND/VOR blend | Shows compare and masking, no branches in the vector path |
| B3 | Bitwise mix: `C[i] = (A[i] & M) ^ (B[i] << 2)` | Exercises logic and shift ops |
| B4 (stretch) | `C[i] = a * A[i] + B[i]` | Only if VMUL is implemented. Check DSP usage in synthesis |

Run every benchmark at LANES = 1, 2, 4, 8. Record `cycle_count`.

---

## 7. Verification Plan

Directory `verif/`.

1. **Golden model** `verif/golden.py`: Python reference for every opcode and every benchmark. Generates input data hex files and expected output hex files.
2. **Assembler** `verif/asm.py`: tiny two-pass assembler. Input `.s`, output `.hex` for instruction memory, parameterized by LANES for address strides.
3. **Unit testbenches**, each self-checking, with directed cases and edge cases:
   - `lane_alu_tb.v`: every op, plus 0, 1, -1, `0x7FFFFFFF`, `0x80000000`, overflow wraparound, shift by 0 and 31, compare of equal values and of negatives
   - `vreg_file_tb.v`: write then read both ports, same-cycle read/write behaviour, all 8 registers
   - `sreg_file_tb.v`: r0 stays zero after a write attempt
   - `control_unit_tb.v`: each opcode produces the expected control word and the expected cycle count
   - `lane_array_tb.v`: random vectors versus Python-generated expected values, for LANES = 1, 4, 8
4. **System test** `top_tb.v`: load program and data, run until halted, dump data memory, compare against expected hex. Report `cycle_count`.
5. **Lane independence test**: change one lane's input, confirm only that lane's output changes.
6. **Regression**: `make test` runs everything and prints a one-line summary per test and a final `ALL PASS` or `FAILED: <list>`.
7. **Waveforms**: `make wave` dumps VCD for the B1 run at LANES = 4. Keep one annotated screenshot of a VADD executing across all lanes for the report.

**Coverage target:** every opcode executed at least once in a system test, every lane exercised, every register read and written.

---

## 8. Toolchain and Repo Layout

Assumed tools (verify at the start, record versions in `docs/decisions.md`):
- Icarus Verilog (`iverilog`, `vvp`), GTKWave, Python 3, `make`
- Vivado for synthesis (Xilinx). If Vivado is not installed, still write the scripts and leave the run to a team member.
- Default FPGA part if no board is specified: `xc7a35tcpg236-1` (Basys 3 class). Change in one variable in `synth/run_synth.tcl`

Makefile targets: `test`, `wave`, `bench` (runs all benchmarks over all lane counts and writes `report/results.csv`), `synth`, `clean`.

### 8a. Synthesis and Measurement

`synth/run_synth.tcl`: non-project-mode Vivado script. Reads `rtl/*.v`, sets LANES via `-generic`, synthesizes `vpu_top` for LANES = 1, 2, 4, 8, applies a clock constraint, writes utilization and timing_summary reports per run into `synth/reports/lanes<N>/`.

Collect into `report/results.csv`:

| Column | Meaning |
|--------|---------|
| lanes | 1, 2, 4, 8 |
| benchmark | B1..B3 (B4) |
| cycles | from `cycle_count` |
| elements | N |
| cycles_per_element | cycles / N |
| speedup_vs_1lane | cycles(1) / cycles(L) |
| luts, ffs, dsps, brams | from utilization report |
| fmax_mhz | from timing report: `1000 / (period - WNS)` |
| throughput_melem_s | (N / cycles) * fmax |

Pick the target clock so WNS is near zero for the 1-lane build, then use the same constraint for all builds.

### Repo layout

```
simd-vector-processing-unit/
├── rtl/            all Verilog RTL
├── tb/             testbenches
├── verif/          golden.py, asm.py, programs/*.s, data/*.hex
├── synth/          run_synth.tcl, constraints.xdc, reports/
├── docs/           isa.md, interfaces.md, decisions.md, one .md per module,
│                   block_diagram.*, fsm_diagram.*
├── report/         final report source, results tables, figures
├── Makefile
└── README.md       how to build, test, synthesize, reproduce results
```

---

## 9. Phases

| Phase | Output | Exit criteria |
|-------|--------|---------------|
| 0 | Repo skeleton, `docs/isa.md`, `docs/interfaces.md`, block diagram, toolchain check | Interfaces reviewed by all roles |
| 1 | `lane_alu`, `vreg_file`, `sreg_file` with testbenches, `golden.py` | Unit tests pass |
| 2 | `lane_array`, `result_combiner`, `dmem`, `pc_imem` | Unit tests pass at LANES = 1, 4, 8 |
| 3 | `control_unit`, `vpu_top`, `asm.py` | A hand-written 5-instruction program runs end to end |
| 4 | Benchmarks B1 to B3 as `.s` files, system tests | All benchmarks match golden at every lane count |
| 5 | `make bench`, results CSV, scalar-vs-SIMD tables | Numbers reproduce from a clean clone |
| 6 | Vivado synthesis sweep, utilization and Fmax | Reports saved, CSV filled |
| 7 | Report, figures, demo script, slides | Dry run of the demo completes in 8 minutes |
| Stretch | VMUL and B4, cross-lane reduction, FPGA bitstream with LED or switch demo | Only after phase 7 is done |

---

## 10. Final Report Outline

1. Introduction and objectives
2. Background: SIMD, data-level parallelism, Amdahl-style limits
3. Architecture: block diagram, ISA table, FSM and cycle-per-instruction table
4. Module descriptions (short, link to `docs/`)
5. Verification: strategy, golden model, test list, waveform screenshots
6. Results: cycles, speedup, throughput, resource use, Fmax, with tables and plots (lanes on the x-axis)
7. Analysis: where speedup is linear and where it is not (loop overhead, scalar instructions, memory width), cost of added lanes, scalar baseline caveats
8. Limitations and future work
9. Conclusion
10. References and team contributions

---

## 11. Live Demo Script

1. Show the block diagram (1 min)
2. Run `make test`, show ALL PASS (1 min)
3. Open the B1 waveform at LANES = 4, step through one VADD and show all 4 lanes updating in the same cycle (2 min)
4. Show the `cycle_count` for B1 at LANES = 1 vs 4 vs 8 (2 min)
5. Show the utilization and Fmax table and explain the tradeoff (2 min)

---

## 12. Definition of Done

- `make test` prints ALL PASS from a clean clone
- `make bench` regenerates `report/results.csv`
- Vivado reports exist for all four lane counts
- Every module has a doc file and a testbench
- Report and demo slides complete, every number in them traceable to `results.csv`
- Each team member can explain their own modules without notes

---

## Team Roles

| # | Role | Owns | Phases | Reviews |
|---|------|------|--------|---------|
| 1 | Architecture lead and integration | ISA, interfaces, vpu_top, repo, Makefile, merging | 0, 3, 5 | Role 3 |
| 2 | Datapath RTL | lane_alu, lane_array, vreg_file, sreg_file, result_combiner | 1, 2 | Role 4 |
| 3 | Control and memory RTL | control_unit FSM, pc_imem, dmem, scalar interface, branch and HALT | 2, 3 | Role 1 |
| 4 | Verification | golden.py, asm.py, all testbenches, benchmarks .s files, regression, waveforms | 1 to 4 | Role 2 |
| 5 | Synthesis, results and report | Vivado scripts, resource and Fmax runs, results.csv, plots, report, slides, demo script | 5 to 7 | Role 4 |

**Team LANE BREAKERS:**
- Role 1 — Kasula Lalithendra
- Role 2 — Dhanvin Vadlamudi
- Role 3 — Jagruthi Pulumati
- Role 4 — Rakshita
- Role 5 — Chaitanya Sai Meka
