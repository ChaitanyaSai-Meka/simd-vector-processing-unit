#!/usr/bin/env python3
"""Render publication-ready vector PDF figures from report/results.csv."""

import argparse
import csv
import math
from pathlib import Path

from reportlab.graphics import renderPDF
from reportlab.graphics.charts.legends import Legend
from reportlab.graphics.charts.lineplots import LinePlot
from reportlab.graphics.shapes import Drawing, Group, String
from reportlab.graphics.widgets.markers import makeMarker
from reportlab.lib.colors import HexColor


REPORT = Path(__file__).resolve().parent
LANES = (1, 2, 4, 8)
BENCHMARKS = ("B1", "B2", "B3")
STYLES = {
    "B1": ("#145c9e", "FilledCircle", None),
    "B2": ("#b14a13", "FilledSquare", [6, 2]),
    "B3": ("#146c59", "FilledDiamond", [2, 2]),
    "Ideal": ("#727c8b", None, [4, 3]),
    "VPU": ("#145c9e", "FilledCircle", None),
}


def read_results(path):
    with path.open(newline="", encoding="utf-8") as stream:
        rows = csv.DictReader(stream)
        required = {"lanes", "benchmark", "cycles", "speedup_vs_1lane"}
        if not required.issubset(rows.fieldnames or ()):
            raise ValueError(f"{path} is missing required simulation columns")
        data = {}
        for row in rows:
            if None in row or None in row.values():
                raise ValueError(f"{path} contains a malformed row")
            key = row["benchmark"], int(row["lanes"])
            if key in data:
                raise ValueError(f"{path} contains a duplicate row for {key}")
            data[key] = row

    expected = [(bench, width) for bench in BENCHMARKS for width in LANES]
    for key in expected:
        if key not in data:
            raise ValueError(f"{path} is missing the row for {key}")
    return {key: data[key] for key in expected}


def metric_series(data, column, *, hardware=False, optional=False):
    values = {key: row.get(column, "").strip() for key, row in data.items()}
    if optional and not any(values.values()):
        return None
    for key, value in values.items():
        if not value:
            raise ValueError(f"{column} is missing for {key}")
        numeric = float(value)
        if not math.isfinite(numeric) or numeric < 0 or (numeric == 0 and column != "luts"):
            raise ValueError(f"{column} has an invalid value for {key}")
        values[key] = numeric

    if hardware:
        result = []
        for width in LANES:
            lane_values = {values[bench, width] for bench in BENCHMARKS}
            if len(lane_values) != 1:
                raise ValueError(f"{column} differs across benchmarks at {width} lanes")
            result.append(lane_values.pop())
        return {"VPU": result}

    return {bench: [values[bench, width] for width in LANES] for bench in BENCHMARKS}


def draw_figure(path, title, axis_label, series):
    width, height = 500, 298
    drawing = Drawing(width, height)
    ink, axis_ink, grid = map(HexColor, ("#152434", "#536171", "#dce4ec"))
    drawing.add(String(68, 272, title, fontName="Helvetica-Bold", fontSize=15, fillColor=ink))
    drawing.add(String(270, 43, "SIMD lanes", textAnchor="middle",
                       fontName="Helvetica", fontSize=11, fillColor=ink))
    label = String(0, 0, axis_label, textAnchor="middle", fontName="Helvetica", fontSize=11, fillColor=ink)
    label_group = Group(label)
    label_group.translate(17, 159)
    label_group.rotate(90)
    drawing.add(label_group)

    chart = LinePlot()
    chart.x, chart.y, chart.width, chart.height = 68, 75, 404, 172
    chart.data = [list(enumerate(values)) for values in series.values()]
    chart.xValueAxis.valueMin, chart.xValueAxis.valueMax = -0.12, 3.12
    chart.xValueAxis.valueSteps = list(range(len(LANES)))
    chart.xValueAxis.labelTextFormat = lambda index: str(LANES[int(index)])
    chart.xValueAxis.labels.dy = -6
    chart.yValueAxis.valueMin = 0
    chart.yValueAxis.valueMax = max(1, max(max(values) for values in series.values()) * 1.06)
    chart.yValueAxis.maximumTicks = 6
    chart.yValueAxis.visibleGrid = True
    chart.yValueAxis.gridStrokeColor = grid
    chart.yValueAxis.gridStrokeWidth = 0.55
    for axis in (chart.xValueAxis, chart.yValueAxis):
        axis.strokeColor = axis.tickStrokeColor = axis_ink
        axis.labels.fillColor = ink
        axis.labels.fontName = "Helvetica"
        axis.labels.fontSize = 10

    for index, name in enumerate(series):
        color, symbol, dash = STYLES[name]
        line = chart.lines[index]
        line.strokeColor = HexColor(color)
        line.strokeWidth = 1.3 if name == "Ideal" else 2.0
        if dash:
            line.strokeDashArray = dash
        if symbol:
            line.symbol = makeMarker(symbol, size=6, fillColor=HexColor(color))
    drawing.add(chart)

    if len(series) > 1:
        legend = Legend()
        legend.x, legend.y = 117, 22
        legend.boxAnchor = "w"
        legend.columnMaximum = 1
        legend.deltax = 79
        legend.fontName = "Helvetica"
        legend.fontSize = 10
        legend.fillColor = ink
        legend.strokeWidth = 0
        legend.colorNamePairs = [(HexColor(STYLES[name][0]), name) for name in series]
        drawing.add(legend)
    renderPDF.drawToFile(drawing, str(path), title=title, invariant=True)


def generate(data, output_dir):
    cycles = metric_series(data, "cycles")
    speedup = metric_series(data, "speedup_vs_1lane")
    plots = [
        ("cycles_vs_lanes", "Execution cycles", "Cycles", cycles),
        ("speedup_vs_lanes", "Cycle speedup", "Speedup vs. one lane", {"Ideal": LANES, **speedup}),
        ("luts_vs_lanes", "FPGA LUT utilization", "LUTs",
         metric_series(data, "luts", hardware=True, optional=True)),
        ("fmax_vs_lanes", "Estimated maximum clock frequency", "Fmax (MHz)",
         metric_series(data, "fmax_mhz", hardware=True, optional=True)),
        ("throughput_vs_lanes", "Estimated throughput", "Million elements per second",
         metric_series(data, "throughput_melem_s", optional=True)),
    ]
    output_dir.mkdir(parents=True, exist_ok=True)
    for name, title, axis_label, series in plots:
        path = output_dir / f"{name}.pdf"
        if series is None:
            print(f"Skipped {path.name}: synthesis measurements absent from CSV")
            if path.exists():
                print(f"Existing figure may be stale: {path}")
            continue
        draw_figure(path, title, axis_label, series)
        print(f"Wrote {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", type=Path, default=REPORT / "results.csv")
    parser.add_argument("--output-dir", type=Path, default=REPORT / "figures")
    args = parser.parse_args()
    try:
        generate(read_results(args.csv), args.output_dir)
    except (OSError, ValueError) as exc:
        parser.exit(1, f"plot.py: {exc}\n")


if __name__ == "__main__":
    main()
