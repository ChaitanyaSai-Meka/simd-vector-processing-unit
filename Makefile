# Makefile — SIMD Vector Processing Unit, LANE BREAKERS
# Owner: Kasula Lalithendra (Role 1, Architecture Lead)
#
# Targets:
#   make test   – compile and run every testbench; print PASS/FAIL per test
#   make smoke  – run the Phase II five-instruction smoke test
#   make system – run one Phase II system case (BENCH=b1, LANES=4 by default)
#   make wave   – dump the integrated four-lane B1 VCD
#   make clean  – remove compiled artefacts

IVERILOG  = iverilog
VVP       ?= vvp
PYTHON    ?= python3

LANES     ?= 4
DW        = 32

RTL = rtl
TB  = tb

# RTL source files (all modules)
RTL_SRCS = $(RTL)/lane_alu.v \
           $(RTL)/lane_mux.v \
           $(RTL)/lane_array.v \
           $(RTL)/vreg_file.v \
           $(RTL)/sreg_file.v \
           $(RTL)/result_combiner.v \
           $(RTL)/dmem.v \
           $(RTL)/pc_imem.v \
           $(RTL)/vpu_demo_top.v \
           $(RTL)/control_unit.v \
           $(RTL)/vpu_top.v

BUILD_DIR = /tmp/vpu_build
VCD_FILE ?= docs/vpu_b1_L4.vcd
BENCH    ?= b1
SYSTEM_CASES = b1 b2 b3 independence coverage
UNIT_TESTS   = lane_alu lane_mux vreg_file sreg_file result_combiner dmem pc_imem
DATAPATH_SRCS = $(addprefix $(RTL)/,vreg_file.v sreg_file.v lane_array.v lane_mux.v lane_alu.v result_combiner.v dmem.v)
DUMP_FILE ?= $(BUILD_DIR)/$(BENCH)_dmem_L$(LANES).hex

.PHONY: test smoke system wave clean golden_self_test

# Collect the failing case names while still running the rest of the suite.
test:
	@mkdir -p $(BUILD_DIR)
	@failures=; \
	run() { test_name=$$1; shift; "$$@" || failures="$$failures $$test_name"; }; \
	run golden $(MAKE) --no-print-directory golden_self_test; \
	for unit in $(UNIT_TESTS); do \
	    run "$${unit}_tb" $(MAKE) --no-print-directory _run_tb \
	        TB_SRC="$(TB)/$${unit}_tb.v" TB_NAME="$${unit}_tb" EXTRA_SRC="$(RTL)/$$unit.v"; \
	done; \
	run control_unit_tb $(MAKE) --no-print-directory _run_tb TB_SRC="$(TB)/control_unit_tb.v" \
	    TB_NAME=control_unit_tb EXTRA_SRC="$(addprefix $(RTL)/,control_unit.v pc_imem.v dmem.v sreg_file.v)"; \
	run demo $(MAKE) --no-print-directory _run_demo_tb; \
	run smoke $(MAKE) --no-print-directory smoke; \
	for width in 1 2 4 8; do \
	    run "lane_array_L$$width" $(MAKE) --no-print-directory _run_tb \
	        TB_SRC="$(TB)/lane_array_tb.v" TB_NAME=lane_array_tb TB_FLAGS="-DLANES=$$width" \
	        EXTRA_SRC="$(addprefix $(RTL)/,lane_array.v lane_alu.v lane_mux.v)"; \
	    run "datapath_L$$width" $(MAKE) --no-print-directory _run_tb \
	        TB_SRC="$(TB)/datapath_sweep_tb.v" TB_NAME=datapath_sweep_tb \
	        TB_FLAGS="-Pdatapath_sweep_tb.LANES=$$width" EXTRA_SRC="$(DATAPATH_SRCS)"; \
	    for benchmark in $(SYSTEM_CASES); do \
	        run "$${benchmark}_L$$width" $(MAKE) --no-print-directory system BENCH="$$benchmark" LANES="$$width"; \
	    done; \
	done; \
	if [ -n "$$failures" ]; then echo "FAILED:$$failures"; exit 1; fi; \
	echo "ALL PASS"

# ── smoke: run the Phase II integration test ───────────────────────────────────
smoke:
	@mkdir -p $(BUILD_DIR)
	@$(IVERILOG) -g2001 -Wall -s vpu_top_smoke_tb -Pvpu_top_smoke_tb.LANES=$(LANES) \
	    -o $(BUILD_DIR)/vpu_top_smoke_L$(LANES).vvp $(TB)/vpu_top_smoke_tb.v $(RTL_SRCS)
	@$(VVP) $(BUILD_DIR)/vpu_top_smoke_L$(LANES).vvp

# ── internal: compile + run a single tb against one RTL file ─────────────────
_run_tb:
	@echo "--- $(TB_NAME) ---"
	@$(IVERILOG) $(TB_FLAGS) -s $(TB_NAME) -o $(BUILD_DIR)/$(TB_NAME).vvp $(TB_SRC) $(EXTRA_SRC) && \
	    $(VVP) $(BUILD_DIR)/$(TB_NAME).vvp

# ── internal: compile + run vpu_demo_top_tb with all RTL ─────────────────────
_run_demo_tb:
	@echo "--- vpu_demo_top_tb LANES=$(LANES) ---"
	@$(IVERILOG) -s vpu_demo_top_tb -DLANES=$(LANES) -o $(BUILD_DIR)/vpu_demo_top_tb.vvp \
	    $(TB)/vpu_demo_top_tb.v $(RTL_SRCS) && \
	    $(VVP) $(BUILD_DIR)/vpu_demo_top_tb.vvp

# ── system: compile once per lane width and select the workload at runtime ────
$(BUILD_DIR)/top_L%.vvp: $(TB)/top_tb.v $(RTL_SRCS)
	@mkdir -p $(BUILD_DIR)
	@$(IVERILOG) -g2001 -Wall -s top_tb -Ptop_tb.LANES=$* -o "$@" $^

system: $(BUILD_DIR)/top_L$(LANES).vvp
	@$(VVP) "$<" +BENCH=$(BENCH) "+DUMP=$(DUMP_FILE)"

# ── wave: dump the integrated B1 simulation at four lanes ─────────────────────
wave: $(BUILD_DIR)/top_L4.vvp
	@$(VVP) "$<" +BENCH=b1 "+VCD=$(VCD_FILE)"
	@echo "VCD written to $(VCD_FILE)"

# ── golden model self-test ────────────────────────────────────────────────────
golden_self_test:
	@echo "--- golden.py self-test ---"
	@$(PYTHON) verif/golden.py --self-test

# ── clean ─────────────────────────────────────────────────────────────────────
clean:
	rm -rf $(BUILD_DIR)
	rm -f *.vcd *.vvp
	find . -name "*.pyc" -delete
	find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
	@echo "Clean done."

