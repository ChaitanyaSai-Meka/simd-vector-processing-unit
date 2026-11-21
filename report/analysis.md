# SIMD lane sweep

The simulations in [results.csv](results.csv) process the same 64 elements at
1, 2, 4, and 8 lanes. The [cycle counts](figures/cycles_vs_lanes.pdf) come from
the RTL counter at HALT. [Cycle speedup](figures/speedup_vs_lanes.pdf) divides
each benchmark's one-lane count by its count at the selected width.

| Benchmark | Cycles at 1 lane | Cycles at 8 lanes | Speedup at 8 lanes |
| --- | ---: | ---: | ---: |
| B1 vector add | 1,032 | 136 | 7.59× |
| B2 signed clamp | 1,998 | 262 | 7.63× |
| B3 bitwise mix | 1,437 | 205 | 7.01× |

## Cycle scaling

Speedup ranges from 1.96× to 1.99× at two lanes and from 3.77× to 3.92× at
four lanes. At eight lanes, B1 and B2 are still close to the ideal 8×, while
B3 falls farther below it. B1 uses the fewest cycles at every tested width.

The measured counts fit a fixed cost plus a cost per lane group, where the
number of groups is 64 divided by the lane count. B1 uses 8 fixed cycles plus
16 per group, B2 uses 14 plus 31 per group, and B3 uses 29 plus 22 per group.
These terms agree with the [ISA timing](../docs/isa.md#cycles-per-instruction-class)
and the benchmark programs. Each group incurs instruction fetch and decode
cycles, vector loads and stores, a scalar index increment, and a branch. Wider
vectors reduce how often those instructions execute. The setup and HALT costs
remain fixed. B3's pre-loop mask setup makes its fixed share larger, which
explains its lower relative speedup as the number of groups falls.

## FPGA measurements and baseline

Increasing the lane count replicates the lane ALU and operand mux and widens
the vector registers and data-memory port. The current CSV contains simulation
results. Routed Vivado measurements are needed to quantify the LUT cost,
compare maximum clock frequency, and estimate throughput in elements per second.

The one-lane baseline runs the same RTL and instruction sequence for each
benchmark, with one element per lane group. It isolates the effect of widening
this VPU for the tested workloads and length. The measured cycle speedups apply
to that baseline. A comparison against a separate scalar processor would
require measurements for that processor.

## Regenerate the figures

Run `python3 report/plot.py` with ReportLab installed. The script currently
generates the cycle and speedup PDFs. Once the routed reports are merged with
`python3 synth/parse_reports.py`, rerun the plot script to generate the LUT,
Fmax, and throughput figures from the populated CSV.
