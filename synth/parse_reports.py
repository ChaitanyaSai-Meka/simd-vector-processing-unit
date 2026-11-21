#!/usr/bin/env python3
"""Merge routed Vivado utilization and clk setup timing into the benchmark CSV."""

import argparse
import csv
from decimal import Decimal, InvalidOperation
from pathlib import Path
import re
import tempfile


ROOT = Path(__file__).resolve().parents[1]
LANE_COUNTS = (1, 2, 4, 8)
BENCHMARKS = ("B1", "B2", "B3")
METRICS = ("luts", "ffs", "dsps", "brams", "fmax_mhz", "throughput_melem_s")
NUMBER = r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?"


def number(value):
    try:
        parsed = Decimal(value.replace(",", ""))
    except InvalidOperation:
        raise ValueError(f"invalid number {value!r}") from None
    if not parsed.is_finite():
        raise ValueError(f"invalid number {value!r}")
    return parsed


def read_utilization(report):
    rows = {}
    for line in report.splitlines():
        if line.lstrip().startswith("|"):
            cells = line.split("|")
            if len(cells) > 3:
                label = cells[1].strip().rstrip("*").strip().casefold()
                rows.setdefault(label, cells[2].strip())

    def used(*labels):
        for label in labels:
            if label in rows:
                return number(rows[label])
        raise ValueError(f"missing utilization row {' or '.join(labels)}")

    luts = used("slice luts", "clb luts")
    if "register as flip flop" in rows or "register as flip-flop" in rows:
        ffs = used("register as flip flop", "register as flip-flop")
    else:
        ffs = used("slice registers", "clb registers")
        if "register as latch" in rows:
            ffs -= used("register as latch")
    dsps = used("dsps", "dsp slices")
    brams = used("block ram tile", "block ram tiles")

    if min(luts, ffs, dsps, brams) < 0 or any(v != int(v) for v in (luts, ffs, dsps)):
        raise ValueError("expected nonnegative utilization counts and whole LUTs, FFs, and DSPs")
    return {"luts": int(luts), "ffs": int(ffs), "dsps": int(dsps), "brams": format(brams, "f")}


def read_timing(report):
    # The sweep appends the exact PERIOD and clk-to-clk SLACK properties.
    footer = re.search(r"^T7 clk setup timing: period_ns=(\S+) wns_ns=(\S+)$", report, re.MULTILINE)
    if footer:
        period, wns = map(number, footer.groups())
    else:
        # A native Vivado report has clk rows in Clock Summary and Intra Clock Table.
        period_row = re.search(rf"^[ \t]*clk[ \t]+\{{[^}}\n]+\}}[ \t]+({NUMBER})(?=[ \t]|$)", report, re.MULTILINE)
        wns_row = re.search(
            rf"^[ \t]*Clock[ \t]+WNS\(ns\)[^\n]*\n(?:[ \t-]*\n)*"
            rf"[ \t]*clk[ \t]+({NUMBER})(?=[ \t]|$)",
            report, re.MULTILINE,
        )
        if not period_row or not wns_row:
            raise ValueError("missing clk period or constrained clk-to-clk setup WNS")
        period, wns = number(period_row[1]), number(wns_row[1])

    if period <= 0 or period - wns <= 0:
        raise ValueError(f"invalid setup timing: period={period} ns, WNS={wns} ns")
    return period, Decimal(1000) / (period - wns)


def read_report(path, parse):
    try:
        return parse(path.read_text(encoding="utf-8"))
    except ValueError as exc:
        raise ValueError(f"{path}: {exc}") from exc


def merge_results(csv_path, reports_dir):
    resources = {}
    periods = {}
    fmax = {}
    for lanes in LANE_COUNTS:
        folder = reports_dir / f"lanes{lanes}"
        resources[lanes] = read_report(folder / "utilization.rpt", read_utilization)
        periods[lanes], fmax[lanes] = read_report(folder / "timing_summary.rpt", read_timing)

    if len(set(periods.values())) != 1:
        raise ValueError(f"clock period differs between lane builds: {periods}")

    with csv_path.open(encoding="utf-8", newline="") as source:
        reader = csv.DictReader(source)
        fields = reader.fieldnames or []
        if not {"lanes", "benchmark", "cycles", "elements"}.issubset(fields):
            raise ValueError(f"{csv_path}: missing benchmark measurement columns")
        rows = list(reader)
    fields += [name for name in METRICS if name not in fields]

    seen = set()
    for row in rows:
        if None in row or None in row.values():
            raise ValueError(f"{csv_path}: malformed benchmark row")
        lanes, cycles, elements = (int(row[field]) for field in ("lanes", "cycles", "elements"))
        case = lanes, row["benchmark"]
        if lanes not in fmax or min(cycles, elements) <= 0 or case in seen:
            raise ValueError(f"{csv_path}: invalid or duplicate result for {case}")
        seen.add(case)
        row.update(resources[lanes])
        row["fmax_mhz"] = f"{fmax[lanes]:.6f}"
        row["throughput_melem_s"] = f"{Decimal(elements) / cycles * fmax[lanes]:.6f}"

    missing = {(lanes, bench) for lanes in LANE_COUNTS for bench in BENCHMARKS} - seen
    if missing:
        raise ValueError(f"{csv_path}: missing benchmark results for {sorted(missing)}")

    with tempfile.TemporaryDirectory(dir=csv_path.parent, prefix=".synth-results-") as temp:
        staged = Path(temp) / csv_path.name
        with staged.open("w", encoding="utf-8", newline="") as out:
            writer = csv.DictWriter(out, fieldnames=fields, lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)
        staged.replace(csv_path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reports-dir", type=Path, default=ROOT / "synth" / "reports")
    parser.add_argument("--csv", type=Path, default=ROOT / "report" / "results.csv")
    args = parser.parse_args()
    try:
        merge_results(args.csv, args.reports_dir)
    except (OSError, ValueError) as exc:
        parser.exit(1, f"parse_reports.py: {exc}\n")
    print(f"Updated {args.csv}")


if __name__ == "__main__":
    main()
