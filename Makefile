# Makefile — SIMD Vector Processing Unit, LANE BREAKERS
# Owner: Kasula Lalithendra (Role 1, Architecture Lead)
#
# Targets:
#   make test   – compile and run every testbench; print PASS/FAIL per test
#   make wave   – run vpu_demo_top_tb at LANES=4, dump VCD, open GTKWave
#   make clean  – remove compiled artefacts

IVERILOG  = iverilog
VVP       ?= vvp
GTKWAVE   ?= $(shell which gtkwave 2>/dev/null || which surfer 2>/dev/null || echo open)
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
           $(RTL)/vpu_demo_top.v

BUILD_DIR = /tmp/vpu_build
VCD_FILE  = docs/vpu_demo_vadd_L4.vcd

.PHONY: test wave clean golden_self_test

# ── test: run all testbenches ─────────────────────────────────────────────────
test: golden_self_test
	@echo "========================================"
	@echo " Running all testbenches (LANES=$(LANES))"
	@echo "========================================"
	@mkdir -p $(BUILD_DIR)
	@$(MAKE) _run_tb TB_SRC=$(TB)/lane_alu_tb.v    TB_NAME=lane_alu_tb    EXTRA_SRC="$(RTL)/lane_alu.v"
	@$(MAKE) _run_tb TB_SRC=$(TB)/lane_mux_tb.v    TB_NAME=lane_mux_tb    EXTRA_SRC="$(RTL)/lane_mux.v"
	@for L in 1 4 8; do \
	    echo "--- lane_array_tb LANES=$$L ---"; \
	    $(IVERILOG) -DLANES=$$L -o $(BUILD_DIR)/lane_array_tb_L$$L.vvp \
	        $(TB)/lane_array_tb.v $(RTL)/lane_array.v $(RTL)/lane_alu.v $(RTL)/lane_mux.v && \
	    $(VVP) $(BUILD_DIR)/lane_array_tb_L$$L.vvp; \
	done
	@$(MAKE) _run_tb TB_SRC=$(TB)/vreg_file_tb.v   TB_NAME=vreg_file_tb   EXTRA_SRC="$(RTL)/vreg_file.v"
	@$(MAKE) _run_tb TB_SRC=$(TB)/sreg_file_tb.v   TB_NAME=sreg_file_tb   EXTRA_SRC="$(RTL)/sreg_file.v"
	@$(MAKE) _run_tb TB_SRC=$(TB)/dmem_tb.v        TB_NAME=dmem_tb        EXTRA_SRC="$(RTL)/dmem.v"
	@$(MAKE) _run_tb TB_SRC=$(TB)/pc_imem_tb.v     TB_NAME=pc_imem_tb     EXTRA_SRC="$(RTL)/pc_imem.v"
	@$(MAKE) _run_demo_tb
	@echo ""
	@echo "========================================"
	@echo " Test run complete."
	@echo "========================================"

# ── internal: compile + run a single tb against one RTL file ─────────────────
_run_tb:
	@echo "--- $(TB_NAME) ---"
	@$(IVERILOG) -o $(BUILD_DIR)/$(TB_NAME).vvp $(TB_SRC) $(EXTRA_SRC) && \
	    $(VVP) $(BUILD_DIR)/$(TB_NAME).vvp

# ── internal: compile + run vpu_demo_top_tb with all RTL ─────────────────────
_run_demo_tb:
	@echo "--- vpu_demo_top_tb LANES=$(LANES) ---"
	@$(IVERILOG) -DLANES=$(LANES) -o $(BUILD_DIR)/vpu_demo_top_tb.vvp \
	    $(TB)/vpu_demo_top_tb.v $(RTL_SRCS) && \
	    $(VVP) $(BUILD_DIR)/vpu_demo_top_tb.vvp

# ── wave: generate and view waveform ─────────────────────────────────────────
wave:
	@echo "--- Generating waveform VCD (LANES=4) ---"
	@mkdir -p $(BUILD_DIR) docs
	@$(IVERILOG) -DLANES=4 -o $(BUILD_DIR)/wave_tb.vvp \
	    $(TB)/vpu_demo_top_tb.v $(RTL_SRCS)
	@$(VVP) $(BUILD_DIR)/wave_tb.vvp
	@echo "VCD written to: $(VCD_FILE)"
	@echo "Opening GTKWave..."
	@$(GTKWAVE) $(VCD_FILE) &

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

