# From the checkout: vivado -mode batch -source synth/run_synth.tcl
# Then merge the routed reports: python3 synth/parse_reports.py
set FPGA_PART xc7a35tcpg236-1

# Seed the instruction ROM with every base opcode and varied register and
# immediate fields so Vivado can see the whole decoder. This identical ROM
# is used at every width for area and timing. Benchmark cycles come from T6.
proc write_measurement_rom {filename} {
    set opcodes {0 1 2 3 4 5 6 7 8 16 17 32 33 34 63}
    set state 1
    set words {}
    for {set addr 0} {$addr < 256} {incr addr} {
        set state [expr {(1664525 * $state + 1013904223) & 0xffffffff}]
        set opcode [lindex $opcodes [expr {$addr % [llength $opcodes]}]]
        set word [expr {($opcode << 26) | ($state >> 6)}]
        lappend words [format %08x $word]
    }
    set fd [open $filename w]
    puts $fd [join $words "\n"]
    close $fd
}

proc replace_once {text original replacement} {
    set first [string first $original $text]
    set length [string length $original]
    if {$first < 0 || [string first $original $text [expr {$first + $length}]] >= 0} {
        error "Expected one occurrence of '$original' in rtl/vpu_top.v"
    }
    return [string replace $text $first [expr {$first + $length - 1}] $replacement]
}

# Stage the measurement-only top so the simulation RTL stays independent of
# Vivado attributes. The public ports only expose control status, so retain
# both vector write-back and data-memory read nets with RTL attributes.
proc stage_synthesis_top {source dest rom} {
    set fd [open $source r]
    set text [read $fd]
    close $fd
    set rom [string map [list "\\" "\\\\" "\"" "\\\""] $rom]
    set text [replace_once $text {.ADDR_W(IMEM_ADDR_W)) u_imem} \
        [format {.ADDR_W(IMEM_ADDR_W), .INIT_FILE("%s")) u_imem} $rom]]
    set text [replace_once $text {reg  [VECTOR_WIDTH-1:0] vector_wb_data;} \
        {(* DONT_TOUCH = "true" *) reg [VECTOR_WIDTH-1:0] vector_wb_data;}]
    set text [replace_once $text {alu_result, mem_rdata, vector_result;} \
        "alu_result, vector_result;\n    (* DONT_TOUCH = \"true\" *) wire \[VECTOR_WIDTH-1:0\] mem_rdata;"]
    set fd [open $dest w]
    puts -nonewline $fd $text
    close $fd
}

proc run_lane {lanes part report_dir} {
    puts "Implementing vpu_top at LANES=$lanes on $part"
    synth_design -top vpu_top -part $part -generic [list LANES=$lanes] \
        -mode out_of_context -flatten_hierarchy rebuilt

    opt_design
    place_design
    route_design
    if {![report_route_status -boolean_check ROUTED_FULLY]} {
        error "LANES=$lanes did not route fully"
    }

    # Fail before publishing reports if the datapath has been pruned.
    foreach bus {vector_wb_data mem_rdata} {
        set pattern [format {^%s\[[0-9]+\]$} $bus]
        set kept [get_nets -quiet -regexp $pattern]
        if {[llength $kept] != 32 * $lanes} {
            error "Expected [expr {32 * $lanes}] retained nets for $bus at LANES=$lanes; found [llength $kept]"
        }
    }

    set clk [get_clocks -quiet clk]
    set paths [get_timing_paths -quiet -delay_type max -from $clk -to $clk -max_paths 1]
    if {[llength $clk] != 1 || [llength $paths] != 1} {
        error "No constrained clk-to-clk setup path for LANES=$lanes"
    }
    set period [get_property PERIOD $clk]
    set wns [get_property SLACK $paths]
    set timing [file join $report_dir timing_summary.rpt]
    file mkdir $report_dir
    report_utilization -file [file join $report_dir utilization.rpt]
    report_timing_summary -delay_type max -file $timing
    set fd [open $timing a]
    puts $fd ""
    puts $fd "T7 clk setup timing: period_ns=$period wns_ns=$wns"
    close $fd
    puts [format "LANES=%d clk period=%sns, WNS=%sns" $lanes $period $wns]
    close_design
}

if {![llength [info commands synth_design]]} {
    error "Run this script with Vivado in batch mode."
}

set root [file normalize [file join [file dirname [info script]] ..]]
set source_dir [file join $root rtl]
set output_dir [file join $root synth reports]
set work [file join $root synth .Xil vpu_sweep_[pid]_[clock clicks]]
set lane_counts {1 2 4 8}
file mkdir $work

set status [catch {
    set rom [file join $work measurement_imem.hex]
    set staged_top [file join $work vpu_top.v]
    set original_top [file join $source_dir vpu_top.v]
    write_measurement_rom $rom
    stage_synthesis_top $original_top $staged_top $rom
    set sources [lsort [glob -directory $source_dir *.v]]
    set top_index [lsearch -exact $sources $original_top]
    set sources [lreplace $sources $top_index $top_index $staged_top]
    read_verilog $sources
    read_xdc [file join $root synth constraints.xdc]

    foreach lanes $lane_counts {
        run_lane $lanes $FPGA_PART [file join $work lanes$lanes]
    }

    # Publish a complete sweep only after all four runs succeed.
    foreach lanes $lane_counts {
        set dest [file join $output_dir lanes$lanes]
        file mkdir $dest
        foreach name {utilization.rpt timing_summary.rpt} {
            file copy -force [file join $work lanes$lanes $name] [file join $dest $name]
        }
    }
    puts "Reports written to $output_dir"
} message options]
file delete -force $work
if {$status} {
    return -options $options $message
}
