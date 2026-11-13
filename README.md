# SIMD Vector Processing Unit

**Team:** LANE BREAKERS
**Course:** Modern Computer Architecture — B.Tech CS & AI, Rishihood University / NST
**Project:** #11 — SIMD Vector Processing Unit (Intermediate+, SIMD / Parallelism)

---

## Team Members

| Role | Name | Responsibility |
|------|------|---------------|
| Architecture Lead | Kasula Lalithendra | Repo skeleton, interfaces, demo top, Makefile, README |
| Datapath RTL | Dhanvin Vadlamudi | lane_alu, lane_mux, lane_array, vreg_file, sreg_file, result_combiner |
| Control & Memory | Jagruthi Pulumati | ISA doc, control FSM design, dmem, pc_imem |
| Verification | Polana Rakshita | golden.py, all testbenches, verification strategy |
| Report & Results | Chaitanya Sai Meka | IEEE report, Vivado synthesis TCL |

---

## What This Project Is

A parameterized **SIMD Vector Processing Unit** in synthesizable Verilog-2001. One instruction operates on all `LANES` data lanes in parallel (default: 4 lanes × 32 bits). Every module is verified with self-checking testbenches (201 checks, all passing), alongside a Python golden reference model. A Vivado synthesis script for Artix-7 is ready; synthesis results are Phase II work.

Key features:
- Parameterized lane count: `LANES ∈ {1, 2, 4, 8}` (same RTL, no edits needed)
- 9 vector ALU operations: VADD, VSUB, VAND, VOR, VXOR, VSLT, VEQ, VSLL, VSRL
- Scalar-broadcast addressing (`.S` suffix): `vd[i] = vs1[i] op rs2`
- 8 vector registers (`v0..v7`), 8 scalar registers (`r0..r7`, `r0 = 0`)
- Harvard architecture: separate instruction and data memories
- Self-checking testbenches with PASS/FAIL output for every module

---

## Repository Layout

```
simd-vector-processing-unit/
├── rtl/                   Synthesizable Verilog-2001 RTL
│   ├── lane_alu.v         Single-lane 32-bit ALU (combinational)
│   ├── lane_mux.v         Per-lane operand-B mux (vector or scalar broadcast)
│   ├── lane_array.v       LANES parallel ALUs via generate loop
│   ├── vreg_file.v        8 vector registers, async read, sync write
│   ├── sreg_file.v        8 scalar registers, r0 = 0
│   ├── result_combiner.v  ALU/load write-back mux
│   ├── dmem.v             Wide-port data memory (LANES×32 bits)
│   ├── pc_imem.v          Program counter and instruction memory
│   └── vpu_demo_top.v     Phase I demo datapath (all modules wired together)
├── tb/                    Self-checking testbenches (Icarus Verilog)
│   ├── lane_alu_tb.v
│   ├── lane_mux_tb.v
│   ├── lane_array_tb.v    Parameterized — compile with -DLANES=1/4/8
│   ├── vreg_file_tb.v
│   ├── sreg_file_tb.v
│   ├── dmem_tb.v
│   ├── pc_imem_tb.v
│   └── vpu_demo_top_tb.v  Full demo datapath test + VCD waveform
├── verif/
│   └── golden.py          Python golden reference model for all ALU ops
├── synth/
│   └── run_synth.tcl      Vivado non-project-mode synthesis script
├── docs/
│   ├── SPEC.md            Full project specification
│   ├── interfaces.md      Port contracts and bus layout (frozen)
│   ├── block_diagram.md   Demo datapath Mermaid diagram
│   ├── isa.md             Instruction encoding and opcode table
│   ├── control_fsm.md     FSM state diagram and control decode table
│   ├── decisions.md       Design decision log
│   ├── verification.md    Verification strategy and test list
│   └── <module>.md        One doc file per RTL module
├── report/
│   ├── main.tex           IEEE conference report (IEEEtran)
│   ├── refs.bib           Bibliography (14 references)
│   └── SIMD_VPU_Phase1_Report.pdf  Compiled Phase I report
├── Makefile
└── README.md
```

---

## Prerequisites

```bash
# macOS (Homebrew)
brew install icarus-verilog gtkwave python3

# Ubuntu / Debian
sudo apt install iverilog gtkwave python3

# Verify
iverilog -V
vvp -V
python3 --version
```

---

## How to Run

### Run all tests
```bash
make test
```
Expected output: every testbench prints `PASS <name>: all N checks passed`.

### Run a specific testbench manually
```bash
# lane_alu
iverilog -o /tmp/la.vvp tb/lane_alu_tb.v rtl/lane_alu.v && vvp /tmp/la.vvp

# lane_array at different lane counts
for L in 1 4 8; do
  iverilog -DLANES=$L -o /tmp/lar_L$L.vvp \
    tb/lane_array_tb.v rtl/lane_array.v rtl/lane_alu.v rtl/lane_mux.v
  vvp /tmp/lar_L$L.vvp
done

# demo top
iverilog -DLANES=4 -o /tmp/demo.vvp tb/vpu_demo_top_tb.v rtl/*.v && vvp /tmp/demo.vvp
```

### Generate waveform (GTKWave)
```bash
make wave
```
This dumps a VCD to `docs/vpu_demo_vadd_L4.vcd` and opens GTKWave.

### Run the Python golden model
```bash
# Self-test the golden model
python3 verif/golden.py --self-test

# Generate B1 hex files for LANES=4, N=64
python3 verif/golden.py --bench B1 --lanes 4 --n 64

# Generate all benchmarks at all lane counts
python3 verif/golden.py --all
```

### Synthesis (requires Vivado)
```bash
vivado -mode batch -source synth/run_synth.tcl
# Reports written to synth/reports/
```

---

## Demo Datapath (Phase I)

The Phase I demo (`vpu_demo_top.v`) shows the core SIMD operation:

1. Testbench loads two vectors into `v0` and `v1` via `load_we`
2. Issues `VADD v2, v0, v1` — `alu_op=4'h0`, `vreg_we=1`
3. All 4 (or 8) lane ALUs compute simultaneously in one clock cycle
4. Result is written back to `v2` and read out via `result_out`

```
  v0 = [1,  2,  3,  4 ]   (lanes 0–3)
  v1 = [10, 11, 12, 13]
       ─────────────────
  v2 = [11, 13, 15, 17]   ← computed in ONE cycle
```

---

## Video Link

📹 **[VIDEO LINK — replace after upload]**

Recording date: Saturday, November 14, 2026

---

## Definition of Done (Phase I Checklist)

- [x] `make test` prints PASS for all unit tests and demo datapath
- [x] Block diagram in `docs/block_diagram.md`
- [x] Every module has a `docs/<module>.md`
- [x] Report builds with all required sections (`report/main.tex`)
- [x] README has project idea, team names, how to run, video link placeholder
- [x] Waveform screenshot of 4-lane VADD saved to `docs/` (run `make wave`)
- [x] Individual Contributions filled in the report
- [ ] Video link updated after recording

