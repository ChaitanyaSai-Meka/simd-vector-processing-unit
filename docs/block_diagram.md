# Block Diagram — SIMD VPU Demo Datapath

**Module:** `vpu_demo_top.v`
**Owner:** Kasula Lalithendra (Role 1)

This is the Phase I demo datapath. The testbench loads two vectors into `vreg_file`, asserts `alu_op` and `opb_sel`, the `lane_array` computes all lanes **in the same cycle**, and the result is written back to a third vector register.

---

## Mermaid Block Diagram

```mermaid
flowchart LR
    TB(["Testbench\nvpu_demo_top_tb"])

    subgraph VRF["vreg_file\n(8 × LANES×32 bits)"]
        VP1["Read Port 1\n(vs1)"]
        VP2["Read Port 2\n(vs2)"]
        VW["Write Port\n(vd)"]
    end

    subgraph SRF["sreg_file\n(8 × 32 bits, r0=0)"]
        SR2["Read Port 2\n(rs2 → scalar)"]
    end

    subgraph LA["lane_array\n(LANES instances)"]
        direction TB
        MUX0["lane_mux 0"] --> ALU0["lane_alu 0"]
        MUX1["lane_mux 1"] --> ALU1["lane_alu 1"]
        MUX2["lane_mux 2"] --> ALU2["lane_alu 2"]
        MUX3["lane_mux 3"] --> ALU3["lane_alu 3"]
    end

    RC["result_combiner"]

    TB -->|"vs1_addr, vs2_addr\nvd_addr, alu_op\nopb_sel, vreg_we\nload_addr, load_data"| VRF
    TB -->|"rs2_addr"| SRF

    VP1 -->|"vs1[LANES×DW-1:0]\nlane i = vs1[i×DW +: DW]"| LA
    VP2 -->|"vs2[LANES×DW-1:0]"| LA
    SR2 -->|"scalar[31:0]\n(broadcast to all lanes)"| LA

    LA -->|"result[LANES×DW-1:0]"| RC
    RC -->|"wb_data\n(res_sel=0 → ALU)"| VW

    VW -->|"result_out"| TB
```

---

## Signal Flow (one VADD operation, LANES=4)

| Cycle | What happens |
|-------|-------------|
| **Setup** | Testbench writes vector A to `v0`, vector B to `v1` via `load_we`. |
| **Execute** | `vs1_addr=0`, `vs2_addr=1`, `alu_op=4'h0` (VADD), `opb_sel=0`. `lane_array` computes `v0[i] + v1[i]` for lanes 0–3 combinationally. |
| **Writeback** | `vd_addr=2`, `vreg_we=1`. Rising clock edge writes result into `v2`. |
| **Readout** | `vs1_addr=2` reads `v2` back through `result_out`. |

One clock cycle per operation: execute and writeback happen in the **same cycle** (combinational ALU + synchronous write).

---

## Demo Datapath Connections (text schematic)

```
                        ┌──────────────────────────────────────────────┐
                        │              lane_array                       │
   vreg_file            │                                               │
  ┌──────────┐          │  lane i:                                      │
  │ rdata1   ├──vs1────►│  vs1[i×DW +: DW] ──────────────► lane_alu.a  │
  │ (vs1)    │          │                                   lane_alu.b ◄─lane_mux─┐
  │          │          │  vs2[i×DW +: DW] ──► lane_mux ──►            │          │
  │ rdata2   ├──vs2────►│                        ▲          lane_alu   │          │
  │ (vs2)    │          │                        │          .result    │   opb_sel│
  │          │          │  scalar ───────────────┘           │         │          │
  │ wdata ◄──┤          │                                    ▼         │          │
  │ (vd wb)  │          │  result[i×DW +: DW] ◄─────────────           │
  └──────────┘          └──────────────────────────────────────────────┘
       ▲                         │
       │                         ▼
       │                  result_combiner
       │                 (res_sel=0: ALU)
       └─────────────────────── wb_data
  
  sreg_file
  ┌──────────┐
  │ rdata2   ├──scalar──► (broadcast to all lane_mux instances)
  │ (rs2)    │
  └──────────┘
```

---

## Module List (Phase I)

| Module | File | Instantiates |
|--------|------|-------------|
| `vpu_demo_top` | `rtl/vpu_demo_top.v` | `vreg_file`, `sreg_file`, `lane_array`, `result_combiner` |
| `lane_array` | `rtl/lane_array.v` | `lane_mux` × LANES, `lane_alu` × LANES |
| `lane_alu` | `rtl/lane_alu.v` | — |
| `lane_mux` | `rtl/lane_mux.v` | — |
| `vreg_file` | `rtl/vreg_file.v` | — |
| `sreg_file` | `rtl/sreg_file.v` | — |
| `result_combiner` | `rtl/result_combiner.v` | — |
| `dmem` | `rtl/dmem.v` | — |
| `pc_imem` | `rtl/pc_imem.v` | — |
