#!/usr/bin/env python3
"""Open-source synthesis sweep for vpu_top at LANES = 1, 2, 4, 8.

Vivado does not run on macOS, so this script uses the open-source
Yosys + nextpnr flow (OSS CAD Suite) instead:

  * Lattice ECP5 (LFE5U-85F): Yosys synth_ecp5, then nextpnr-ecp5 place and
    route. Reports routed resource use and maximum clock frequency.
  * Xilinx Artix-7: Yosys synth_xilinx for resource estimates only
    (no place and route, so no Fmax).

The design is staged exactly like synth/run_synth.tcl: the instruction ROM is
seeded with every base opcode so the whole decoder is kept, and the vector
write-back register and data-memory read bus are marked keep so the datapath
is not pruned (the top-level ports only expose control status).

Usage:  python3 synth/run_oss_synth.py [--tools ~/tools/oss-cad-suite/bin]
Writes: synth/oss_reports/lanes<N>/{ecp5_nextpnr.log,xc7_stat.txt}
        synth/oss_results.csv
"""

import argparse
import csv
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RTL = ROOT / "rtl"
OUT_DIR = ROOT / "synth" / "oss_reports"
CSV_OUT = ROOT / "synth" / "oss_results.csv"
LANE_COUNTS = (1, 2, 4, 8)
TARGET_MHZ = 50
ECP5_DEVICE = "--85k"
ECP5_PACKAGE = "CABGA381"

# Same opcode list and LCG as write_measurement_rom in run_synth.tcl.
OPCODES = [0, 1, 2, 3, 4, 5, 6, 7, 8, 16, 17, 32, 33, 34, 63]


def write_measurement_rom(path):
    state = 1
    words = []
    for addr in range(256):
        state = (1664525 * state + 1013904223) & 0xFFFFFFFF
        opcode = OPCODES[addr % len(OPCODES)]
        words.append(f"{(opcode << 26) | (state >> 6):08x}")
    path.write_text("\n".join(words) + "\n")


def replace_once(text, old, new):
    if text.count(old) != 1:
        sys.exit(f"Expected one occurrence of {old!r} in rtl/vpu_top.v")
    return text.replace(old, new)


def stage_top(dest, rom):
    text = (RTL / "vpu_top.v").read_text()
    text = replace_once(text, ".ADDR_W(IMEM_ADDR_W)) u_imem",
                        f'.ADDR_W(IMEM_ADDR_W), .INIT_FILE("{rom}")) u_imem')
    text = replace_once(text, "reg  [VECTOR_WIDTH-1:0] vector_wb_data;",
                        "(* keep *) reg [VECTOR_WIDTH-1:0] vector_wb_data;")
    text = replace_once(text, "alu_result, mem_rdata, vector_result;",
                        "alu_result, vector_result;\n"
                        "    (* keep *) wire [VECTOR_WIDTH-1:0] mem_rdata;")
    dest.write_text(text)


def run(cmd, log, env):
    with open(log, "w") as fh:
        result = subprocess.run(cmd, stdout=fh, stderr=subprocess.STDOUT, env=env)
    if result.returncode != 0:
        sys.exit(f"Command failed ({' '.join(map(str, cmd))}); see {log}")
    return log.read_text()


def ecp5_resources(nextpnr_log):
    """Parse the post-route device utilisation table from nextpnr-ecp5."""
    used = {}
    for name in ("TRELLIS_COMB", "TRELLIS_FF", "TRELLIS_RAMW", "DP16KD", "MULT18X18D"):
        hits = re.findall(rf"{name}:\s+(\d+)/\s*(\d+)", nextpnr_log)
        used[name] = int(hits[-1][0]) if hits else 0
    fmax = re.findall(r"Max frequency for clock\s+'[^']*clk[^']*':\s+([\d.]+) MHz", nextpnr_log)
    if not fmax:
        sys.exit("nextpnr log has no Fmax line for clk")
    used["fmax"] = float(fmax[-1])
    return used


def xc7_resources(stat_json):
    data = json.loads(stat_json.read_text())
    cells = data["design"]["num_cells_by_type"]
    luts = sum(n for c, n in cells.items() if re.fullmatch(r"LUT[1-6]", c))
    ffs = sum(n for c, n in cells.items() if re.fullmatch(r"FD[CPRSE]+", c))
    lutram = sum(n for c, n in cells.items() if c.startswith("RAM") and not c.startswith("RAMB"))
    bram = sum(n for c, n in cells.items() if c.startswith("RAMB"))
    carry = sum(n for c, n in cells.items() if c.startswith("CARRY"))
    return {"luts": luts, "ffs": ffs, "lutram": lutram, "bram": bram, "carry": carry}


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--tools", default=os.path.expanduser("~/tools/oss-cad-suite/bin"),
                        help="directory containing yosys and nextpnr-ecp5")
    args = parser.parse_args()

    env = dict(os.environ)
    env["PATH"] = args.tools + os.pathsep + env["PATH"]
    for tool in ("yosys", "nextpnr-ecp5"):
        if not shutil.which(tool, path=env["PATH"]):
            sys.exit(f"{tool} not found; install OSS CAD Suite or pass --tools")

    rows = []
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        rom = tmp / "measurement_imem.hex"
        top = tmp / "vpu_top.v"
        write_measurement_rom(rom)
        stage_top(top, rom)
        sources = [str(top)] + [str(p) for p in sorted(RTL.glob("*.v"))
                                if p.name not in ("vpu_top.v", "vpu_demo_top.v")]

        for lanes in LANE_COUNTS:
            out = OUT_DIR / f"lanes{lanes}"
            out.mkdir(parents=True, exist_ok=True)
            read = (f"read_verilog -DSYNTHESIS {' '.join(sources)}; "
                    f"chparam -set LANES {lanes} vpu_top; hierarchy -top vpu_top")

            # ECP5: synthesise, then place and route for Fmax.
            json_net = tmp / f"ecp5_L{lanes}.json"
            run(["yosys", "-q", "-p", f"{read}; synth_ecp5 -top vpu_top -json {json_net}"],
                out / "ecp5_yosys.log", env)
            log = run(["nextpnr-ecp5", ECP5_DEVICE, "--package", ECP5_PACKAGE,
                       "--json", str(json_net), "--freq", str(TARGET_MHZ),
                       "--seed", "1", "--timing-allow-fail"],
                      out / "ecp5_nextpnr.log", env)
            ecp5 = ecp5_resources(log)

            # Artix-7: Yosys resource estimate only.
            stat = out / "xc7_stat.json"
            run(["yosys", "-q", "-p",
                 f"{read}; synth_xilinx -family xc7 -top vpu_top; "
                 f"tee -q -o {out / 'xc7_stat.txt'} stat; "
                 f"tee -q -o {stat} stat -json"],
                out / "xc7_yosys.log", env)
            xc7 = xc7_resources(stat)

            row = {
                "lanes": lanes,
                "ecp5_luts": ecp5["TRELLIS_COMB"],
                "ecp5_ffs": ecp5["TRELLIS_FF"],
                "ecp5_lutram": ecp5["TRELLIS_RAMW"],
                "ecp5_bram": ecp5["DP16KD"],
                "ecp5_fmax_mhz": f"{ecp5['fmax']:.2f}",
                "xc7_luts": xc7["luts"],
                "xc7_ffs": xc7["ffs"],
                "xc7_lutram": xc7["lutram"],
                "xc7_bram": xc7["bram"],
            }
            rows.append(row)
            print(", ".join(f"{k}={v}" for k, v in row.items()), flush=True)

    with open(CSV_OUT, "w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {CSV_OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
