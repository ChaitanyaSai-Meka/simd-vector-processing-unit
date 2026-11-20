# Phase I Audit

Audit baseline is commit `67d6738` on `main`. The Phase I regression passes and all nine RTL modules have self-checking testbenches. The module documentation checklist has one open item, the dedicated demo-top document.

## Module inventory

| RTL | Testbench | Module documentation |
| --- | --- | --- |
| [`dmem`](../rtl/dmem.v) | [`dmem_tb.v`](../tb/dmem_tb.v) | [`dmem.md`](dmem.md) |
| [`lane_alu`](../rtl/lane_alu.v) | [`lane_alu_tb.v`](../tb/lane_alu_tb.v) | [`lane_alu.md`](lane_alu.md) |
| [`lane_array`](../rtl/lane_array.v) | [`lane_array_tb.v`](../tb/lane_array_tb.v) | [`lane_array.md`](lane_array.md) |
| [`lane_mux`](../rtl/lane_mux.v) | [`lane_mux_tb.v`](../tb/lane_mux_tb.v) | [`lane_mux.md`](lane_mux.md) |
| [`pc_imem`](../rtl/pc_imem.v) | [`pc_imem_tb.v`](../tb/pc_imem_tb.v) | [`pc_imem.md`](pc_imem.md) |
| [`result_combiner`](../rtl/result_combiner.v) | [`result_combiner_tb.v`](../tb/result_combiner_tb.v) | [`result_combiner.md`](result_combiner.md) |
| [`sreg_file`](../rtl/sreg_file.v) | [`sreg_file_tb.v`](../tb/sreg_file_tb.v) | [`sreg_file.md`](sreg_file.md) |
| [`vpu_demo_top`](../rtl/vpu_demo_top.v) | [`vpu_demo_top_tb.v`](../tb/vpu_demo_top_tb.v) | Dedicated `vpu_demo_top.md` missing. Existing coverage includes the [block diagram](block_diagram.md) and [interface contract](interfaces.md#vpu_demo_topv-step-5--lalithendra). |
| [`vreg_file`](../rtl/vreg_file.v) | [`vreg_file_tb.v`](../tb/vreg_file_tb.v) | [`vreg_file.md`](vreg_file.md) |

## Regression and artifacts

- `make test` exited 0 from a fresh export of the tracked baseline using Icarus Verilog 13.0, Python 3.9.6, and GNU Make 3.81. The Python golden model self-test passed. The simulator reported 203 passing RTL checks across 11 runs, including the lane-array runs at 1, 4, and 8 lanes and the demo at 4 lanes. The final line of the test summary was `Test run complete.`
- The Phase I datapath block diagram and worked VADD signal flow are in [`block_diagram.md`](block_diagram.md). The [four-lane VADD screenshot](vadd_4lane_waveform.png) and its [report figure](../report/vadd_writeback_waveform.pdf) are tracked. The regression regenerated `docs/vpu_demo_vadd_L4.vcd` in the fresh export. The VCD is git-ignored.
- The [README](../README.md) includes the project overview, team roles, and commands for the tests and waveform. The Phase I video link is still a placeholder.

## Open items and owners

| Item | Owner | Follow-up |
| --- | --- | --- |
| Dedicated `docs/vpu_demo_top.md` | Kasula Lalithendra, Phase I demo-top owner | Document the demo’s purpose, design choices, timing, and a worked example. Update the README’s module-documentation checklist to reflect the gap until the document exists. |
| Phase I video link | Kasula Lalithendra, README owner | Add the video URL once it is available. The checkout does not establish whether a recording was uploaded. |
| All-lane datapath regression | Dhanvin Vadlamudi (T3), with Polana Rakshita for shared tests | Cover `LANES=1,2,4,8`. The current default test target omits 2 lanes from the lane-array sweep. |
| Phase II regression summary | Polana Rakshita (T5) | Add the required `ALL PASS` or `FAILED: <list>` summary when the system tests are integrated. |

The final controller and integrated top are Phase II work assigned to T1 and T4 in the brief. The Phase I demo drives datapath control signals directly and tests instruction and data memory separately.
