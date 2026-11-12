# ============================================================
# run_synth.tcl  —  Vivado non-project-mode synthesis script
# SIMD Vector Processing Unit, LANE BREAKERS
# Owner: Chaitanya Sai Meka (Role 5, Synthesis and Results)
#
# Usage:
#   vivado -mode batch -source synth/run_synth.tcl
#
# Phase I: synthesizes lane_alu for an early resource estimate.
# Phase II: synthesizes vpu_top at LANES = 1, 2, 4, 8.
# ============================================================

# ---- User-configurable variables ----------------------------------------
set FPGA_PART    "xc7a35tcpg236-1"    ;# Basys 3 / Artix-7 (change if needed)
set CLK_PERIOD   "10.0"               ;# Target clock period in ns (100 MHz)
set REPORT_DIR   "synth/reports"
set RTL_DIR      "rtl"

# ---- Helper: run synthesis for one top and one LANES value --------------
proc run_one {top lanes part clk_period report_dir rtl_dir} {
    set run_dir "${report_dir}/lanes${lanes}"
    file mkdir $run_dir

    puts "====================================================="
    puts " Synthesizing: top=${top}  LANES=${lanes}"
    puts "====================================================="

    # Read all RTL sources
    read_verilog [glob ${rtl_dir}/*.v]

    # Synthesize
    synth_design \
        -top       $top \
        -part      $part \
        -generic   "LANES=${lanes}" \
        -flatten_hierarchy rebuilt

    # Clock constraint
    create_clock -period $clk_period -name clk [get_ports clk]

    # Optimize
    opt_design

    # Place (required for timing)
    place_design

    # Route (required for accurate timing)
    route_design

    # Reports
    report_utilization \
        -file "${run_dir}/${top}_L${lanes}_utilization.rpt"
    report_timing_summary \
        -max_paths 10 \
        -file "${run_dir}/${top}_L${lanes}_timing.rpt"
    report_power \
        -file "${run_dir}/${top}_L${lanes}_power.rpt"

    puts "Reports written to: ${run_dir}/"
    puts ""
}

# ---- Phase I: lane_alu early resource estimate --------------------------
# lane_alu is purely combinational; no clock port, so we just synthesize.
puts "====================================================="
puts " Phase I: lane_alu resource estimate (all LANES=1)"
puts "====================================================="

file mkdir "${REPORT_DIR}/lane_alu"
read_verilog [glob ${RTL_DIR}/lane_alu.v]
synth_design -top lane_alu -part $FPGA_PART -flatten_hierarchy rebuilt
report_utilization -file "${REPORT_DIR}/lane_alu/lane_alu_utilization.rpt"
puts "lane_alu utilization report: ${REPORT_DIR}/lane_alu/lane_alu_utilization.rpt"

# ---- Phase II: full vpu_top sweep (uncomment when RTL is complete) ------
# foreach lanes {1 2 4 8} {
#     run_one "vpu_top" $lanes $FPGA_PART $CLK_PERIOD $REPORT_DIR $RTL_DIR
# }

# ---- Parse Fmax from timing report (helper proc) ------------------------
proc parse_fmax {timing_rpt clk_period_ns} {
    # Reads WNS from timing_summary report and computes Fmax.
    # Fmax (MHz) = 1000 / (clk_period - WNS)   if WNS < clk_period
    set fmax "N/A"
    if {[catch {open $timing_rpt r} fh]} {
        return $fmax
    }
    while {[gets $fh line] >= 0} {
        # Look for the WNS line in timing_summary
        if {[regexp {WNS\(ns\)\s+([-\d\.]+)} $line match wns]} {
            if {$wns ne "N/A" && [string is double $wns]} {
                set slack [expr {$clk_period_ns - $wns}]
                if {$slack > 0} {
                    set fmax [format "%.1f" [expr {1000.0 / $slack}]]
                }
            }
            break
        }
    }
    close $fh
    return $fmax
}

# ---- Results CSV skeleton -----------------------------------------------
# When Phase II runs are complete, collect results with:
#
# set csv "report/results.csv"
# set fh [open $csv w]
# puts $fh "lanes,benchmark,cycles,elements,cycles_per_element,speedup_vs_1lane,luts,ffs,dsps,brams,fmax_mhz,throughput_melem_s"
# # Fill rows from cycle_count (simulation) and report files (synthesis).
# close $fh
# puts "Results written to ${csv}"

puts ""
puts "====================================================="
puts " run_synth.tcl complete."
puts " Phase I report: ${REPORT_DIR}/lane_alu/"
puts " Phase II: uncomment the foreach loop above when"
puts "           vpu_top.v is available."
puts "====================================================="
