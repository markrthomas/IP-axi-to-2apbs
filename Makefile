IVERILOG ?= iverilog
VVP ?= vvp
GTKWAVE ?= gtkwave
GTKWAVE_FLAGS ?=
VERILATOR ?= verilator

VERILATOR_ROOT := $(shell v=$$(command -v verilator 2>/dev/null); [ -n "$$v" ] && realpath "$$(dirname "$$v")/../share/verilator")
VERILATOR_INC  := $(VERILATOR_ROOT)/include
VERILATOR_CPP  := $(VERILATOR_INC)/verilated.cpp $(VERILATOR_INC)/verilated_cov.cpp \
                  $(VERILATOR_INC)/verilated_threads.cpp

COV_DIR_SIMPLE := obj_dir_cov_simple
COV_DIR_BURST  := obj_dir_cov_burst

UVM_SV_LINT_SRCS = \
	uvm/sv/interfaces/axi4_master_if.sv \
	uvm/sv/interfaces/apb_burst_ext_side_if.sv \
	uvm/sv/interfaces/apb_sel_tracker_if.sv \
	uvm/sv/interfaces/apb_mon_if.sv \
	uvm/sv/models/apb_dual_mem_simple.sv \
	uvm/sv/models/apb_dual_mem_burst.sv \
	uvm/sv/models/apb_dual_mem_ws.sv \
	uvm/sv/models/apb_dual_mem_param.sv \
	uvm/sv/models/apb_ext_mem_dual.sv \
	uvm/sv/pkg/bridge_stimulus_pkg.sv

# Default UVM SV lint is strict (separate tops; see scripts/verilator_lint_uvm_strict.sh).
# Relaxed: one multitop elaboration with broad waivers (quick local smoke).
VERILATOR_LINT_UVM_RELAXED_FLAGS := --lint-only \
	-Wno-fatal \
	-Wno-MULTITOP \
	-Wno-DECLFILENAME \
	-Wno-UNUSEDSIGNAL \
	-Wno-UNDRIVEN \
	-Wno-WIDTHEXPAND \
	-Wno-WIDTHTRUNC

IVERILOG_FLAGS ?= -g2012 -Wall -I$(CURDIR)/test

# Markdown to PDF (requires pandoc + $(PANDOC_PDF_ENGINE), e.g. pdflatex from TeX Live)
PANDOC ?= pandoc
README_MD ?= README.md
README_PDF ?= README.pdf
PANDOC_PDF_ENGINE ?= pdflatex
PANDOC_PDF_VARS ?= -V geometry:margin=1in -V fontsize=11pt

# All Markdown sources (repo root; skips .git), each becomes a sibling .pdf via md-pdfs
ALL_MD := $(shell find . -name .git -prune -o -name '*.md' -type f -print 2>/dev/null | LC_ALL=C sort)
ALL_MD_PDF := $(ALL_MD:%.md=%.pdf)

# All README.md only (same pandoc rule as %.pdf: %.md)
ALL_README_MD := $(shell find . -name .git -prune -o -name 'README.md' -type f -print 2>/dev/null | LC_ALL=C sort)
ALL_README_PDF := $(ALL_README_MD:%.md=%.pdf)

README_PDF_DEFAULT := $(patsubst %.md,%.pdf,$(README_MD))

REGBLOCK_RTL = src/axi3lite_regblock.v
REGBLOCK_TB  = test/tb_axi3lite_regblock.v
COV_DIR_RB   = obj_dir_cov_regblock

SIMPLE_TB = test/tb_axi4_to_apb4_2x_simple.v
SIMPLE_RTL = src/axi4_to_apb4_2x_simple.v
BURST_TB = test/tb_axi4_to_apb4_2x_burst.v
BURST_EXT_TB = test/tb_axi4_to_apb4_2x_burst_extended.v
BURST_RTL = src/axi4_to_apb4_2x_burst.v
SIMPLE_WS_TB = test/tb_axi4_to_apb4_2x_simple_ws.v
PARAM_TB = test/tb_parameterized_config.v
STRESS_TB = test/tb_stress_burst.v
WAVE_MACROS = test/wave_macros.v

WAIT_CYCLES ?= 2
READ_WS     ?= 2

# Stress test knobs (passed as vvp plusargs)
STRESS_N     ?= 200   # random transactions (total sim length)
STRESS_SEED  ?= 0     # $random seed; change for different stimulus
STRESS_WAIT0 ?= 1     # APB0 wait cycles per transfer
STRESS_WAIT1 ?= 1     # APB1 wait cycles per transfer
STRESS_BP    ?= 3     # max BREADY/RREADY back-pressure cycles

# Waveform dumps (GTKWave / Surfer). FST requires vvp -fst after the sim binary.
WAVEFMT ?= fst

ifeq ($(WAVEFMT),fst)
 VVP_WAVEFLAGS := -fst
else ifeq ($(WAVEFMT),vcd)
 VVP_WAVEFLAGS :=
else
 $(error WAVEFMT must be fst or vcd)
endif

# Default bench for: make wave | make gtk | make sim
WAVETB ?= simple

.PHONY: help default test test-all test-full check check-full check-uvm check-uvm-mirror lint-uvm-sv lint-uvm-sv-relaxed \
	test-simple test-simple-ws test-simple-ws-sweep test-burst test-burst-ext test-param \
	test-stress wave-stress gtk-stress test-regblock \
	lint clean sim readme-pdf readme-md-pdfs md-pdfs \
	wave wave-simple wave-burst wave-burst-ext wave-simple-ws wave-param \
	gtk gtk-simple gtk-burst gtk-burst-ext gtk-simple-ws gtk-param \
	regress coverage cov-report formal ci cocotb cocotb-regblock _lint_iverilog _lint_verilator \
	_cov_regblock \
	uvm-vcs uvm-vcs-simple uvm-vcs-burst uvm-vcs-burst-ext uvm-vcs-simple-ws uvm-vcs-parameterized \
	uvm-vcs-rand-burst uvm-vcs-rand-integrity uvm-vcs-stress \
	uvm-vcs-regblock-hw-reset uvm-vcs-regblock-bit-bash uvm-vcs-regblock-reg-access uvm-vcs-regblock-directed \
	uvm-xcelium uvm-xcelium-simple uvm-xcelium-burst uvm-xcelium-burst-ext uvm-xcelium-simple-ws uvm-xcelium-parameterized \
	uvm-xcelium-rand-burst uvm-xcelium-rand-integrity uvm-xcelium-stress

default: help

help:
	@echo "IP-axi-to-2apbs - common targets"
	@echo ""
	@echo "  Tests (fast -> full):"
	@echo "    make test          # same as test-all (simple + burst)"
	@echo "    make test-all"
	@echo "    make test-full     # all TBs except wait-state sweep"
	@echo "    make check         # lint then test-all"
	@echo "    make check-full    # lint then test-full"
	@echo "    make test-simple | test-burst | test-burst-ext | test-param | test-simple-ws"
	@echo "    make test-simple-ws-sweep    # WAIT_CYCLES 1,2,3"
	@echo "    make test-stress             # randomised stress (STRESS_N/SEED/WAIT0/WAIT1/BP)"
	@echo "    make wave-stress             # stress + FST waveform dump"
	@echo "    make gtk-stress              # stress + launch GTKWave"
	@echo "    STRESS_N=500 STRESS_SEED=7 STRESS_WAIT0=2 STRESS_WAIT1=0 STRESS_BP=4"
	@echo ""
	@echo "  Build simulators only:"
	@echo "    make sim                    # WAVETB=simple|burst|burst-ext|simple-ws|param"
	@echo "    make sim_simple sim_burst ..."
	@echo ""
	@echo "  Waveforms (then open GTKWave yourself, or use gtk targets below):"
	@echo "    make wave                   # WAVETB=simple|burst|burst-ext|simple-ws|param"
	@echo "    make wave-simple | wave-burst | ..."
	@echo "    WAVEFMT=fst|vcd   WAVEFILE=path   WAIT_CYCLES=n (for simple-ws)"
	@echo ""
	@echo "  GTKWave (simulate + launch viewer):"
	@echo "    make gtk                    # uses WAVETB (default: simple)"
	@echo "    make gtk-simple | gtk-burst | gtk-burst-ext | gtk-simple-ws | gtk-param"
	@echo "    GTKWAVE=/path/to/gtkwave  GTKWAVE_FLAGS='...'"
	@echo ""
	@echo "  UVM mirror (no VCS required):"
	@echo "    make check-uvm-mirror   # literals vs test/tb_*.v (python3)"
	@echo "    make lint-uvm-sv        # strict Verilator (per-module + shims; scripts/verilator_lint_uvm_strict.sh)"
	@echo "    make lint-uvm-sv-relaxed # single-pass multitop; many warnings waived"
	@echo "    make check-uvm          # check-uvm-mirror + lint-uvm-sv (strict)"
	@echo ""
	@echo "  UVM simulation — Synopsys VCS (requires export UVM_HOME=...):"
	@echo "    make uvm-vcs-simple | uvm-vcs-burst | uvm-vcs-burst-ext | uvm-vcs-parameterized"
	@echo "    make uvm-vcs-simple-ws [READ_WS=N]  # default READ_WS=2"
	@echo "    make uvm-vcs-rand-burst             # constrained-random write+read sequences"
	@echo "    make uvm-vcs-rand-integrity         # write-then-read integrity rounds"
	@echo "    make uvm-vcs-stress [STRESS_N=N]    # three-phase stress (mirrors tb_stress_burst.v)"
	@echo "    make uvm-vcs                        # all 5 directed VCS targets"
	@echo ""
	@echo "  UVM simulation — Cadence Xcelium (requires export UVM_HOME=...):"
	@echo "    make uvm-xcelium-simple | uvm-xcelium-burst | uvm-xcelium-burst-ext | uvm-xcelium-parameterized"
	@echo "    make uvm-xcelium-simple-ws [READ_WS=N]  # default READ_WS=2"
	@echo "    make uvm-xcelium-rand-burst             # constrained-random write+read sequences"
	@echo "    make uvm-xcelium-rand-integrity         # write-then-read integrity rounds"
	@echo "    make uvm-xcelium-stress [STRESS_N=N]    # three-phase stress (mirrors tb_stress_burst.v)"
	@echo "    make uvm-xcelium                        # all 5 directed Xcelium targets"
	@echo ""
	@echo "  Docs:"
	@echo "    make readme-pdf               # README.md -> README.pdf (override README_MD / README_PDF)"
	@echo "    make readme-md-pdfs           # every README.md -> sibling README.pdf"
	@echo "    make md-pdfs                  # every *.md under . (except .git) -> sibling .pdf"
	@echo "    PANDOC_PDF_ENGINE=xelatex     # optional, for richer Unicode/fonts"
	@echo ""
	@echo "  Coverage:"
	@echo "    make cov-report                   # build + run + terminal table + coverage_report.html"
	@echo "    make cov-html                     # cov-report, then open the HTML in a browser"
	@echo "    COV_REPORT_HTML=my.html make cov-report"
	@echo "    make coverage                     # build + run only (produces .info files)"
	@echo ""
	@echo "  Performance:"
	@echo "    make perf                         # benchmark burst bridge + terminal table + perf_report.html"
	@echo "    make perf-html                    # perf, then open the HTML in a browser"
	@echo "    PERF_ITERS=20000 make perf        # larger workload for a steadier timing sample"
	@echo ""
	@echo "  PyUVM:"
	@echo "    make pyuvm                        # run the PyUVM burst testbench (directed + random)"
	@echo "    make pyuvm-waves                  # randomized PyUVM run, dump FST for GTKWave"
	@echo "    make pyuvm-wave-view              # pyuvm-waves, then open the trace in GTKWave"
	@echo "    PYUVM_SEED=<n> make pyuvm-waves   # reproduce a specific random trace"
	@echo ""
	@echo ""
	@echo "  Docker / Railway (license-free UVM on Verilator in a container):"
	@echo "    make docker-uvm-build             # build image (uvm/vlt/Dockerfile)"
	@echo "    make docker-uvm-run               # build + run the full UVM gate in a container"
	@echo "    make railway-deploy               # railway up (needs: railway login && railway link)"
	@echo "    make railway-logs                 # tail the Railway deployment logs"
	@echo "    UVM_IMAGE=name:tag  DOCKER=podman  RAILWAY=railway"
	@echo ""
	@echo "  Other: make lint | make clean | make check-full"

# --- tests -------------------------------------------------------------------

test: test-all

test-all: test-simple test-burst test-regblock

test-full: test-simple test-burst test-burst-ext test-param test-simple-ws

check: lint test-all

check-full: lint test-full

test-regblock: sim_regblock
	$(VVP) sim_regblock

test-simple: sim_simple
	$(VVP) sim_simple

test-simple-ws: sim_simple_ws_$(WAIT_CYCLES)
	$(VVP) sim_simple_ws_$(WAIT_CYCLES)

test-simple-ws-sweep:
	$(MAKE) test-simple-ws WAIT_CYCLES=1
	$(MAKE) test-simple-ws WAIT_CYCLES=2
	$(MAKE) test-simple-ws WAIT_CYCLES=3

test-burst: sim_burst
	$(VVP) sim_burst

test-burst-ext: sim_burst_ext
	$(VVP) sim_burst_ext

test-param: sim_param
	$(VVP) sim_param

check-uvm-mirror:
	python3 $(CURDIR)/scripts/uvm_mirror_check.py --root $(CURDIR)

lint-uvm-sv:
	bash $(CURDIR)/scripts/verilator_lint_uvm_strict.sh

lint-uvm-sv-relaxed:
	$(VERILATOR) --version >/dev/null
	$(VERILATOR) $(VERILATOR_LINT_UVM_RELAXED_FLAGS) $(UVM_SV_LINT_SRCS)

check-uvm: check-uvm-mirror lint-uvm-sv

# --- UVM simulation (VCS + Xcelium) ------------------------------------------
# Requires: export UVM_HOME=/path/to/uvm (must contain src/uvm.sv)

uvm-vcs-simple:
	$(MAKE) -C $(CURDIR)/uvm/vcs sim_simple

uvm-vcs-burst:
	$(MAKE) -C $(CURDIR)/uvm/vcs sim_burst

uvm-vcs-burst-ext:
	$(MAKE) -C $(CURDIR)/uvm/vcs sim_burst_ext

uvm-vcs-simple-ws:
	$(MAKE) -C $(CURDIR)/uvm/vcs sim_simple_ws READ_WS=$(READ_WS)

uvm-vcs-parameterized:
	$(MAKE) -C $(CURDIR)/uvm/vcs sim_parameterized

uvm-vcs-rand-burst:
	$(MAKE) -C $(CURDIR)/uvm/vcs sim_rand_burst

uvm-vcs-rand-integrity:
	$(MAKE) -C $(CURDIR)/uvm/vcs sim_rand_integrity

uvm-vcs-stress:
	$(MAKE) -C $(CURDIR)/uvm/vcs sim_stress STRESS_N=$(STRESS_N)

uvm-vcs: uvm-vcs-simple uvm-vcs-burst uvm-vcs-burst-ext uvm-vcs-simple-ws uvm-vcs-parameterized

uvm-xcelium-simple:
	$(MAKE) -C $(CURDIR)/uvm/xcelium sim_simple

uvm-xcelium-burst:
	$(MAKE) -C $(CURDIR)/uvm/xcelium sim_burst

uvm-xcelium-burst-ext:
	$(MAKE) -C $(CURDIR)/uvm/xcelium sim_burst_ext

uvm-xcelium-simple-ws:
	$(MAKE) -C $(CURDIR)/uvm/xcelium sim_simple_ws READ_WS=$(READ_WS)

uvm-xcelium-parameterized:
	$(MAKE) -C $(CURDIR)/uvm/xcelium sim_parameterized

uvm-xcelium-rand-burst:
	$(MAKE) -C $(CURDIR)/uvm/xcelium sim_rand_burst

uvm-xcelium-rand-integrity:
	$(MAKE) -C $(CURDIR)/uvm/xcelium sim_rand_integrity

uvm-xcelium-stress:
	$(MAKE) -C $(CURDIR)/uvm/xcelium sim_stress STRESS_N=$(STRESS_N)

uvm-xcelium: uvm-xcelium-simple uvm-xcelium-burst uvm-xcelium-burst-ext uvm-xcelium-simple-ws uvm-xcelium-parameterized

# --- compile -----------------------------------------------------------------

sim_regblock: $(REGBLOCK_TB) $(REGBLOCK_RTL)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $@ $^

sim_simple: $(SIMPLE_TB) $(SIMPLE_RTL) $(WAVE_MACROS)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $@ $(filter-out $(WAVE_MACROS),$^)

sim_burst: $(BURST_TB) $(BURST_RTL) $(WAVE_MACROS)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $@ $(filter-out $(WAVE_MACROS),$^)

sim_burst_ext: $(BURST_EXT_TB) $(BURST_RTL) $(WAVE_MACROS)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $@ $(filter-out $(WAVE_MACROS),$^)

sim_simple_ws_%: $(SIMPLE_WS_TB) $(SIMPLE_RTL) $(WAVE_MACROS)
	$(IVERILOG) $(IVERILOG_FLAGS) -DREAD_WAIT_CYCLES=$* -o $@ $(filter-out $(WAVE_MACROS),$^)

sim_param: $(PARAM_TB) $(BURST_RTL) $(WAVE_MACROS)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $@ $(filter-out $(WAVE_MACROS),$^)

sim_stress: $(STRESS_TB) $(BURST_RTL) $(WAVE_MACROS)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $@ $(filter-out $(WAVE_MACROS),$^)

# Run without waveform (fast pass/fail)
test-stress: sim_stress
	$(VVP) sim_stress \
	  +N=$(STRESS_N) +SEED=$(STRESS_SEED) \
	  +WAIT0=$(STRESS_WAIT0) +WAIT1=$(STRESS_WAIT1) +BP=$(STRESS_BP)

# Run with waveform dump (FST for GTKWave / Surfer)
wave-stress: WAVEFILE ?= waves_stress.fst
wave-stress: sim_stress
	$(VVP) sim_stress $(VVP_WAVEFLAGS) \
	  +N=$(STRESS_N) +SEED=$(STRESS_SEED) \
	  +WAIT0=$(STRESS_WAIT0) +WAIT1=$(STRESS_WAIT1) +BP=$(STRESS_BP) \
	  +wave +wavefile=$(WAVEFILE)

gtk-stress: WAVEFILE ?= waves_stress.fst
gtk-stress: wave-stress
	$(GTK_OPEN)

ifeq ($(WAVETB),simple)
  SIM_BIN := sim_simple
else ifeq ($(WAVETB),burst)
  SIM_BIN := sim_burst
else ifeq ($(WAVETB),burst-ext)
  SIM_BIN := sim_burst_ext
else ifeq ($(WAVETB),simple-ws)
  SIM_BIN := sim_simple_ws_$(WAIT_CYCLES)
else ifeq ($(WAVETB),param)
  SIM_BIN := sim_param
else
  $(error Unknown WAVETB '$(WAVETB)'. Use: simple burst burst-ext simple-ws param)
endif

# Unified wave default (depends on WAVETB). Keep this target-specific so the
# explicit wave-* targets can use their own WAVEFILE defaults.
ifeq ($(WAVETB),simple)
  wave: WAVEFILE ?= waves_simple.$(WAVEFMT)
else ifeq ($(WAVETB),burst)
  wave: WAVEFILE ?= waves_burst.$(WAVEFMT)
else ifeq ($(WAVETB),burst-ext)
  wave: WAVEFILE ?= waves_burst_ext.$(WAVEFMT)
else ifeq ($(WAVETB),simple-ws)
  wave: WAVEFILE ?= waves_simple_ws.$(WAVEFMT)
else ifeq ($(WAVETB),param)
  wave: WAVEFILE ?= waves_param.$(WAVEFMT)
endif

sim: $(SIM_BIN)
	@echo "Built $(SIM_BIN)"

# --- waves -------------------------------------------------------------------

# Override path: make wave WAVEFILE=mytrace.fst
wave: $(SIM_BIN)
	$(VVP) $(SIM_BIN) $(VVP_WAVEFLAGS) +wave +wavefile=$(WAVEFILE)

wave-simple: WAVEFILE ?= waves_simple.$(WAVEFMT)
wave-simple: sim_simple
	$(VVP) sim_simple $(VVP_WAVEFLAGS) +wave +wavefile=$(WAVEFILE)

wave-burst: WAVEFILE ?= waves_burst.$(WAVEFMT)
wave-burst: sim_burst
	$(VVP) sim_burst $(VVP_WAVEFLAGS) +wave +wavefile=$(WAVEFILE)

wave-burst-ext: WAVEFILE ?= waves_burst_ext.$(WAVEFMT)
wave-burst-ext: sim_burst_ext
	$(VVP) sim_burst_ext $(VVP_WAVEFLAGS) +wave +wavefile=$(WAVEFILE)

wave-simple-ws: WAVEFILE ?= waves_simple_ws.$(WAVEFMT)
wave-simple-ws: sim_simple_ws_$(WAIT_CYCLES)
	$(VVP) sim_simple_ws_$(WAIT_CYCLES) $(VVP_WAVEFLAGS) +wave +wavefile=$(WAVEFILE)

wave-param: WAVEFILE ?= waves_param.$(WAVEFMT)
wave-param: sim_param
	$(VVP) sim_param $(VVP_WAVEFLAGS) +wave +wavefile=$(WAVEFILE)

# Launch viewer after a wave-* target (simulation must have written $(WAVEFILE)).
GTK_OPEN = @printf 'Opening %s in GTKWave...\n' "$(WAVEFILE)"; \
	command -v "$(GTKWAVE)" >/dev/null 2>&1 || { printf '%s\n' "Missing viewer: install gtkwave or set GTKWAVE=/path/to/gtkwave" >&2; exit 127; }; \
	$(GTKWAVE) $(GTKWAVE_FLAGS) "$(WAVEFILE)" &

gtk-simple: WAVEFILE ?= waves_simple.$(WAVEFMT)
gtk-simple: wave-simple
	$(GTK_OPEN)

gtk-burst: WAVEFILE ?= waves_burst.$(WAVEFMT)
gtk-burst: wave-burst
	$(GTK_OPEN)

gtk-burst-ext: WAVEFILE ?= waves_burst_ext.$(WAVEFMT)
gtk-burst-ext: wave-burst-ext
	$(GTK_OPEN)

gtk-simple-ws: WAVEFILE ?= waves_simple_ws.$(WAVEFMT)
gtk-simple-ws: wave-simple-ws
	$(GTK_OPEN)

gtk-param: WAVEFILE ?= waves_param.$(WAVEFMT)
gtk-param: wave-param
	$(GTK_OPEN)

# Dispatch to gtk-simple, gtk-burst, ... (avoids duplicating per-bench rules).
gtk:
	$(MAKE) gtk-$(WAVETB)

%.pdf: %.md
	@command -v $(PANDOC) >/dev/null 2>&1 || \
		{ printf '%s\n' "Missing pandoc (https://pandoc.org/installing.html). On Debian/Ubuntu: sudo apt install pandoc texlive-latex-recommended texlive-fonts-recommended." >&2; exit 127; }
	@command -v $(PANDOC_PDF_ENGINE) >/dev/null 2>&1 || \
		{ printf '%s\n' "Missing PDF engine '$(PANDOC_PDF_ENGINE)' on PATH. Install TeX Live or set PANDOC_PDF_ENGINE=wkhtmltopdf (wkhtmltopdf must be installed)" >&2; exit 127; }
	$(PANDOC) $(PANDOC_PDF_VARS) --resource-path=$(dir $(abspath $<)):$(CURDIR) --pdf-engine=$(PANDOC_PDF_ENGINE) $< -o $@

md-pdfs: $(ALL_MD_PDF)

readme-md-pdfs: $(ALL_README_PDF)

readme-pdf: $(README_PDF)

# Custom README output path (when it is not the usual sibling of README_MD)
ifneq ($(README_PDF),$(README_PDF_DEFAULT))
$(README_PDF): $(README_MD)
	@command -v $(PANDOC) >/dev/null 2>&1 || \
		{ printf '%s\n' "Missing pandoc (https://pandoc.org/installing.html). On Debian/Ubuntu: sudo apt install pandoc texlive-latex-recommended texlive-fonts-recommended." >&2; exit 127; }
	@command -v $(PANDOC_PDF_ENGINE) >/dev/null 2>&1 || \
		{ printf '%s\n' "Missing PDF engine '$(PANDOC_PDF_ENGINE)' on PATH. Install TeX Live or set PANDOC_PDF_ENGINE=wkhtmltopdf (wkhtmltopdf must be installed)" >&2; exit 127; }
	$(PANDOC) $(PANDOC_PDF_VARS) --resource-path=$(dir $(abspath $<)):$(CURDIR) --pdf-engine=$(PANDOC_PDF_ENGINE) $< -o $@
endif

# --- standard DV gate targets (consistent with other RTL repos) --------------

# lint: iverilog -Wall across all TBs, then Verilator RTL-only lint.
# Add Verilator pass after existing iverilog checks.
lint: _lint_iverilog _lint_verilator

_lint_iverilog:
	$(IVERILOG) $(IVERILOG_FLAGS) -o /tmp/sim_simple_w $(SIMPLE_TB) $(SIMPLE_RTL)
	$(IVERILOG) $(IVERILOG_FLAGS) -DREAD_WAIT_CYCLES=$(WAIT_CYCLES) -o /tmp/sim_simple_ws_w $(SIMPLE_WS_TB) $(SIMPLE_RTL)
	$(IVERILOG) $(IVERILOG_FLAGS) -o /tmp/sim_burst_w $(BURST_TB) $(BURST_RTL)
	$(IVERILOG) $(IVERILOG_FLAGS) -o /tmp/sim_burst_ext_w $(BURST_EXT_TB) $(BURST_RTL)
	$(IVERILOG) $(IVERILOG_FLAGS) -o /tmp/sim_param_w $(PARAM_TB) $(BURST_RTL)
	$(IVERILOG) $(IVERILOG_FLAGS) -o /tmp/sim_regblock_w $(REGBLOCK_TB) $(REGBLOCK_RTL)

_lint_verilator:
	@if command -v $(VERILATOR) >/dev/null 2>&1; then \
		echo "[LINT] Verilator RTL lint..."; \
		$(VERILATOR) --lint-only -Wall -Wno-DECLFILENAME $(SIMPLE_RTL); \
		$(VERILATOR) --lint-only -Wall -Wno-DECLFILENAME $(BURST_RTL); \
		$(VERILATOR) --lint-only -Wall -Wno-DECLFILENAME $(REGBLOCK_RTL); \
	else \
		echo "[LINT] verilator not on PATH — skipping RTL lint"; \
	fi

# regress: fast CI gate — lint + directed simulation (simple + burst).
regress: _lint_iverilog _lint_verilator test-all
	@echo "[REGRESS] lint + directed sim PASSED"

COV_REPORT_HTML ?= coverage_report.html

# Performance benchmark (optimized Verilator model of the burst bridge).
PERF_DIR         := obj_dir_perf
PERF_REPORT_HTML ?= perf_report.html
PERF_METRICS     ?= perf_metrics.txt
PERF_ITERS       ?= 4000

# coverage: Verilator --coverage for all three RTL blocks.
coverage: _cov_simple _cov_burst _cov_regblock
	@echo "[COVERAGE] Done. Wrote coverage_simple.info, coverage_burst.info, coverage_regblock.info."

# cov-report: run coverage then render terminal summary + self-contained HTML report.
cov-report: coverage
	python3 $(CURDIR)/scripts/cov_report.py \
		--root $(CURDIR) \
		--out $(COV_REPORT_HTML) \
		coverage_simple.info coverage_burst.info coverage_regblock.info

# cov-html: build the coverage HTML report and open it in a browser.
cov-html: cov-report
	bash $(CURDIR)/scripts/open_report.sh $(COV_REPORT_HTML)

# perf: build an optimized Verilator model of the burst bridge, run the
#       benchmark workload, and render a terminal + self-contained HTML report
#       (simulation speed + design cycles-per-beat / sustained bandwidth).
#       Override the workload size with:  PERF_ITERS=20000 make perf
perf:
	@command -v $(VERILATOR) >/dev/null 2>&1 || { echo "[PERF] verilator not on PATH; skipping"; exit 0; }
	rm -rf $(PERF_DIR)
	$(VERILATOR) -cc $(BURST_RTL) --top-module axi4_to_apb4_2x_burst \
		--Mdir $(PERF_DIR) -Wno-DECLFILENAME -Wall -Wno-fatal -O3 -CFLAGS -O2
	$(MAKE) -C $(PERF_DIR) -f Vaxi4_to_apb4_2x_burst.mk
	g++ -O2 -o $(PERF_DIR)/sim_perf \
		sim_main_perf.cpp $(PERF_DIR)/Vaxi4_to_apb4_2x_burst__ALL.a \
		-I$(PERF_DIR) -I$(VERILATOR_INC) -I$(VERILATOR_INC)/vltstd \
		$(VERILATOR_CPP) -pthread -lm
	$(PERF_DIR)/sim_perf $(PERF_ITERS) | tee $(PERF_METRICS)
	python3 $(CURDIR)/scripts/perf_report.py $(PERF_METRICS) --out $(PERF_REPORT_HTML)

# perf-html: run the performance benchmark and open the HTML report in a browser.
perf-html: perf
	bash $(CURDIR)/scripts/open_report.sh $(PERF_REPORT_HTML)

_cov_simple:
	@command -v $(VERILATOR) >/dev/null 2>&1 || { echo "[COVERAGE] verilator not on PATH; skipping"; exit 0; }
	rm -rf $(COV_DIR_SIMPLE)
	$(VERILATOR) --coverage -cc $(SIMPLE_RTL) --top-module axi4_to_apb4_2x_simple \
		--Mdir $(COV_DIR_SIMPLE) -Wno-DECLFILENAME -Wall -Wno-fatal
	$(MAKE) -C $(COV_DIR_SIMPLE) -f Vaxi4_to_apb4_2x_simple.mk
	g++ -DVM_COVERAGE=1 -o $(COV_DIR_SIMPLE)/sim_simple \
		sim_main_simple.cpp $(COV_DIR_SIMPLE)/Vaxi4_to_apb4_2x_simple__ALL.a \
		-I$(COV_DIR_SIMPLE) -I$(VERILATOR_INC) -I$(VERILATOR_INC)/vltstd \
		$(VERILATOR_CPP) -pthread -lm
	cd $(COV_DIR_SIMPLE) && ./sim_simple
	@if command -v verilator_coverage >/dev/null 2>&1; then \
		verilator_coverage -write-info coverage_simple.info $(COV_DIR_SIMPLE)/coverage.dat; \
		echo "[COVERAGE] simple: coverage_simple.info written"; \
	else \
		echo "[COVERAGE] simple: coverage.dat in $(COV_DIR_SIMPLE) (install verilator for lcov export)"; \
	fi

_cov_burst:
	@command -v $(VERILATOR) >/dev/null 2>&1 || { echo "[COVERAGE] verilator not on PATH; skipping"; exit 0; }
	rm -rf $(COV_DIR_BURST)
	$(VERILATOR) --coverage -cc $(BURST_RTL) --top-module axi4_to_apb4_2x_burst \
		--Mdir $(COV_DIR_BURST) -Wno-DECLFILENAME -Wall -Wno-fatal
	$(MAKE) -C $(COV_DIR_BURST) -f Vaxi4_to_apb4_2x_burst.mk
	g++ -DVM_COVERAGE=1 -o $(COV_DIR_BURST)/sim_burst \
		sim_main_burst.cpp $(COV_DIR_BURST)/Vaxi4_to_apb4_2x_burst__ALL.a \
		-I$(COV_DIR_BURST) -I$(VERILATOR_INC) -I$(VERILATOR_INC)/vltstd \
		$(VERILATOR_CPP) -pthread -lm
	cd $(COV_DIR_BURST) && ./sim_burst
	@if command -v verilator_coverage >/dev/null 2>&1; then \
		verilator_coverage -write-info coverage_burst.info $(COV_DIR_BURST)/coverage.dat; \
		echo "[COVERAGE] burst: coverage_burst.info written"; \
	else \
		echo "[COVERAGE] burst: coverage.dat in $(COV_DIR_BURST) (install verilator for lcov export)"; \
	fi

_cov_regblock:
	@command -v $(VERILATOR) >/dev/null 2>&1 || { echo "[COVERAGE] verilator not on PATH; skipping"; exit 0; }
	rm -rf $(COV_DIR_RB)
	$(VERILATOR) --coverage -cc $(REGBLOCK_RTL) --top-module axi3lite_regblock \
		--Mdir $(COV_DIR_RB) -Wno-DECLFILENAME -Wall -Wno-fatal
	$(MAKE) -C $(COV_DIR_RB) -f Vaxi3lite_regblock.mk
	g++ -DVM_COVERAGE=1 -o $(COV_DIR_RB)/sim_regblock \
		sim_main_regblock.cpp $(COV_DIR_RB)/Vaxi3lite_regblock__ALL.a \
		-I$(COV_DIR_RB) -I$(VERILATOR_INC) -I$(VERILATOR_INC)/vltstd \
		$(VERILATOR_CPP) -pthread -lm
	cd $(COV_DIR_RB) && ./sim_regblock
	@if command -v verilator_coverage >/dev/null 2>&1; then \
		verilator_coverage -write-info coverage_regblock.info $(COV_DIR_RB)/coverage.dat; \
		echo "[COVERAGE] regblock: coverage_regblock.info written"; \
	else \
		echo "[COVERAGE] regblock: coverage.dat in $(COV_DIR_RB) (install verilator for lcov export)"; \
	fi

# UVM regblock targets (requires export UVM_HOME=...)
uvm-vcs-regblock-hw-reset:
	$(MAKE) -C $(CURDIR)/uvm/vcs sim_regblock_hw_reset

uvm-vcs-regblock-bit-bash:
	$(MAKE) -C $(CURDIR)/uvm/vcs sim_regblock_bit_bash

uvm-vcs-regblock-reg-access:
	$(MAKE) -C $(CURDIR)/uvm/vcs sim_regblock_reg_access

uvm-vcs-regblock-directed:
	$(MAKE) -C $(CURDIR)/uvm/vcs sim_regblock_directed

# formal: SymbiYosys formal proofs in verification/formal/.
#         Proves APB4 handshake timing, mutual exclusion, BVALID/RVALID
#         cleanup, BID/RID correctness, RLAST placement, and DECERR behavior
#         for both the simple and burst bridge variants.
formal:
	@if command -v sby >/dev/null 2>&1; then \
		$(MAKE) -C $(CURDIR)/verification/formal; \
	else \
		echo "[FORMAL] sby not found; install SymbiYosys (OSS CAD Suite) to run formal"; \
		echo "         Properties are in verification/formal/apb4_simple_props.sv"; \
		exit 0; \
	fi

# cocotb: Python-based OSS UVM-equivalent tests (Icarus + cocotb).
#         Requires: pip install cocotb  (no VCS needed).
cocotb: cocotb-regblock
	$(MAKE) -C $(CURDIR)/cocotb

cocotb-regblock:
	$(MAKE) -C $(CURDIR)/cocotb/regblock

# --- PyUVM testbench targets -------------------------------------------------
PYUVM_WAVE_FST  := $(CURDIR)/cocotb/pyuvm_waves/sim_build/axi4_to_apb4_2x_burst.fst
PYUVM_WAVE_GTKW := $(CURDIR)/cocotb/pyuvm_waves/pyuvm_burst.gtkw

# pyuvm: run the PyUVM burst testbench (directed + constrained-random).
pyuvm:
	$(MAKE) -C $(CURDIR)/cocotb/pyuvm_burst

# pyuvm-waves: run the randomized PyUVM test with waveform capture (FST).
#              Reproduce a specific trace with:  PYUVM_SEED=<n> make pyuvm-waves
pyuvm-waves:
	$(MAKE) -C $(CURDIR)/cocotb/pyuvm_waves WAVES=1
	@echo "[PYUVM] wave written: $(PYUVM_WAVE_FST)"

# pyuvm-wave-view: (re)generate the randomized trace and open it in GTKWave
#                  with the grouped-signal save file (pyuvm_burst.gtkw).
pyuvm-wave-view: pyuvm-waves
	@command -v $(GTKWAVE) >/dev/null 2>&1 || { echo "[PYUVM] $(GTKWAVE) not on PATH; open $(PYUVM_WAVE_FST) with $(PYUVM_WAVE_GTKW)"; exit 0; }
	$(GTKWAVE) $(GTKWAVE_FLAGS) $(PYUVM_WAVE_FST) $(PYUVM_WAVE_GTKW) >/dev/null 2>&1 &

# ci: comprehensive local run — regress + coverage check + UVM mirror + cocotb.
ci: regress coverage check-uvm-mirror cocotb
	@echo "[CI] All gates passed."

# --- Docker / Railway: license-free UVM on Verilator in a container ----------
# Builds an image with UVM-capable Verilator 5.050 + the bundled UVM library
# (root Dockerfile) whose entrypoint runs the full UVM gate (make -C uvm/vlt ci).
# Useful where the local host lacks the RAM for the --binary build: run it on
# Railway (or any container host) instead. See uvm/vlt/README.md.
DOCKER         ?= docker
RAILWAY        ?= railway
UVM_IMAGE      ?= ip-axi-2apbs-uvm:latest
UVM_DOCKERFILE := Dockerfile

docker-uvm-build:
	@command -v $(DOCKER) >/dev/null 2>&1 || { echo "[DOCKER] '$(DOCKER)' not found; install Docker or Podman (or set DOCKER=)"; exit 127; }
	$(DOCKER) build -f $(UVM_DOCKERFILE) -t $(UVM_IMAGE) .

# NOTE: the --binary build is RAM-heavy; on a small (~8 GB) host this can OOM.
# The point of this path is to run it on a RAM-generous host (Railway).
docker-uvm-run: docker-uvm-build
	$(DOCKER) run --rm $(UVM_IMAGE)

railway-deploy:
	@command -v $(RAILWAY) >/dev/null 2>&1 || { echo "[RAILWAY] '$(RAILWAY)' CLI not found: https://docs.railway.com/guides/cli"; exit 127; }
	@echo "[RAILWAY] Deploying via $(UVM_DOCKERFILE) (railway.toml). Requires: railway login && railway link."
	$(RAILWAY) up

railway-logs:
	@command -v $(RAILWAY) >/dev/null 2>&1 || { echo "[RAILWAY] '$(RAILWAY)' CLI not found: https://docs.railway.com/guides/cli"; exit 127; }
	$(RAILWAY) logs

.PHONY: regress coverage cov-report cov-html perf perf-html pyuvm pyuvm-waves pyuvm-wave-view _cov_simple _cov_burst formal ci _lint_iverilog _lint_verilator \
	docker-uvm-build docker-uvm-run railway-deploy railway-logs

clean:
	rm -f sim_simple sim_burst sim_burst_ext sim_simple_ws_* sim_param sim_stress sim_regblock \
		waves_*.fst waves_*.vcd burst.vcd param.vcd $(ALL_MD_PDF) \
		coverage_simple.info coverage_burst.info coverage_regblock.info $(COV_REPORT_HTML) \
		$(PERF_REPORT_HTML) $(PERF_METRICS)
	rm -rf $(COV_DIR_SIMPLE) $(COV_DIR_BURST) $(COV_DIR_RB) $(PERF_DIR)
	$(MAKE) -C $(CURDIR)/verification/formal clean 2>/dev/null || true
	$(MAKE) -C $(CURDIR)/uvm/vcs clean 2>/dev/null || true
	$(MAKE) -C $(CURDIR)/uvm/xcelium clean 2>/dev/null || true
