#!/usr/bin/env python3
"""Run the verified system benchmarks and write their measured cycle counts."""

import argparse
import csv
from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "report" / "results.csv"
LANE_COUNTS = (1, 2, 4, 8)
BENCHMARKS = ("B1", "B2", "B3")
ELEMENTS = 64
FIELDS = ("lanes", "benchmark", "cycles", "elements", "cycles_per_element", "speedup_vs_1lane")
PASS_LINE = re.compile(
    r"^PASS top_tb BENCH=(b[123]) LANES=([0-9]+) cycle_count=([0-9]+) instr_count=[0-9]+$",
    re.MULTILINE,
)


def measure(make, build_dir, lanes, benchmark):
    name = benchmark.lower()
    dump = build_dir / f"{name}_dmem_L{lanes}.hex"
    result = subprocess.run(
        [
            make, "--no-print-directory", "system",
            f"LANES={lanes}", f"BENCH={name}", f"BUILD_DIR={build_dir}",
            f"DUMP_FILE={dump}",
        ],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    matches = PASS_LINE.findall(result.stdout)
    case = f"{benchmark} at LANES={lanes}"
    if result.returncode:
        raise RuntimeError(f"{case} failed with exit status {result.returncode}\n{result.stdout.rstrip()}")
    if len(matches) != 1:
        raise RuntimeError(f"{case} did not emit exactly one PASS measurement\n{result.stdout.rstrip()}")

    actual_bench, actual_lanes, cycles = matches[0]
    if actual_bench != name or int(actual_lanes) != lanes or int(cycles) <= 0:
        raise RuntimeError(f"{case} emitted an unexpected measurement\n{result.stdout.rstrip()}")
    return int(cycles)


def write_results(counts):
    # Replace the CSV only after all cases passed and all rows were written.
    with tempfile.TemporaryDirectory(dir=RESULTS.parent, prefix=".results-") as scratch:
        staged = Path(scratch) / RESULTS.name
        with staged.open("w", encoding="utf-8", newline="") as output:
            writer = csv.writer(output, lineterminator="\n")
            writer.writerow(FIELDS)
            for lanes in LANE_COUNTS:
                for benchmark in BENCHMARKS:
                    cycles = counts[lanes, benchmark]
                    writer.writerow((
                        lanes, benchmark, cycles, ELEMENTS,
                        f"{cycles / ELEMENTS:.6f}", f"{counts[1, benchmark] / cycles:.6f}",
                    ))
        staged.replace(RESULTS)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--make", default="make", help="GNU Make executable")
    args = parser.parse_args()

    counts = {}
    try:
        # Use freshly compiled simulations so a shared build directory cannot
        # contribute binaries from a different checkout.
        with tempfile.TemporaryDirectory(prefix="simd-vpu-bench-") as scratch:
            for lanes in LANE_COUNTS:
                for benchmark in BENCHMARKS:
                    cycles = measure(args.make, Path(scratch), lanes, benchmark)
                    counts[lanes, benchmark] = cycles
                    print(f"{benchmark} LANES={lanes} cycles={cycles}", flush=True)
        write_results(counts)
    except (OSError, RuntimeError) as exc:
        parser.exit(1, f"run_bench.py: {exc}\n")
    print(f"Wrote {RESULTS.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
