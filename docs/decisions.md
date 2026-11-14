# Design Decisions Log

**Owner:** Kasula Lalithendra (Role 1, Architecture Lead)
All ambiguous choices are recorded here per agent rule 8.

---

## Phase 0

### D-001: Async read, sync write for register files
**Decision:** `vreg_file` and `sreg_file` use **asynchronous read, synchronous write**.
**Rationale:** Keeps the FSM cycle count simple. With async reads, the DECODE/EXECUTE phase can read operands and produce the ALU result combinationally in the same cycle. The write then happens on the next clock edge (WRITEBACK). This gives a clean 3-state FSM without needing an extra READ cycle.
**Modules affected:** `vreg_file.v`, `sreg_file.v`, `control_unit.v`

### D-002: v0 is not hardwired to zero
**Decision:** `v0` is a normal read/write vector register.
**Rationale:** The spec explicitly says so. Avoids a special case in `vreg_file`. Teams that want zero use `VSUB vX, vX, vX`.

### D-003: `opb_sel` encoded in instruction bit 16
**Decision:** Instruction bit `[16]` selects scalar broadcast (`opb_sel`).
**Rationale:** Simplest encoding that does not conflict with the opcode or register fields. The `.S` suffix on a mnemonic sets this bit. The assembler `asm.py` handles the encoding.
**Modules affected:** `lane_mux.v`, `control_unit.v`, `verif/asm.py`

### D-004: Address stride for `dmem` is in lane-groups
**Decision:** `dmem` address `A` reads/writes words `[A×LANES .. A×LANES+LANES-1]`.
**Rationale:** Naturally aligned vector loads. The assembler generates strides of `LANES` between iterations so the same loop logic works at any `LANES` value.
**Modules affected:** `dmem.v`, `verif/asm.py`

### D-005: FPGA target part
**Decision:** Default part is `xc7a35tcpg236-1` (Artix-7, Basys 3 class).
**Rationale:** No physical board specified. This is the standard course FPGA. Change the variable `FPGA_PART` at the top of `synth/run_synth.tcl`.

### D-006: `vpu_demo_top` for Phase I demo, `vpu_top` for Phase II
**Decision:** Phase I uses a simplified `vpu_demo_top.v` where the testbench drives control signals directly (no FSM). Phase II adds `control_unit.v` and uses `vpu_top.v`.
**Rationale:** Allows the demo video to be recorded before the FSM is complete. The interfaces are identical to what `vpu_top` will use.

### D-007: Toolchain versions recorded
| Tool | Version check command | Required |
|------|-----------------------|---------|
| Icarus Verilog | `iverilog -V` | Yes |
| vvp | bundled with iverilog | Yes |
| GTKWave | `gtkwave --version` | Yes |
| Python | `python3 --version` | ≥ 3.8 |
| make | `make --version` | Yes |
| Vivado | `vivado -version` | For synth only |

*(Fill in actual version numbers after running toolchain check.)*

### D-008: PC update and HALT timing
**Decision:** Update the PC at the end of DECODE/EXECUTE. A taken BNE asserts both `pc_en` and `branch_en` and uses the BNE instruction address as the offset base. HALT latches `halted` and holds the controller in DECODE/EXECUTE until reset.
**Rationale:** The PC remains at the current instruction during decode. A branch outcome can select the next PC in the same cycle, and HALT can freeze the PC at its own address.
**Modules affected:** `control_unit.v`, `pc_imem.v`, `verif/asm.py`
