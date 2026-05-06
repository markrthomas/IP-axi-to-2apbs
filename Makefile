IVERILOG ?= iverilog
VVP ?= vvp
GTKWAVE ?= gtkwave
GTKWAVE_FLAGS ?=
VERILATOR ?= verilator

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

README_PDF_DEFAULT := $(patsubst %.md,%.pdf,$(README_MD))

SIMPLE_TB = test/tb_axi4_to_apb4_2x_simple.v
SIMPLE_RTL = src/axi4_to_apb4_2x_simple.v
BURST_TB = test/tb_axi4_to_apb4_2x_burst.v
BURST_EXT_TB = test/tb_axi4_to_apb4_2x_burst_extended.v
BURST_RTL = src/axi4_to_apb4_2x_burst.v
SIMPLE_WS_TB = test/tb_axi4_to_apb4_2x_simple_ws.v
PARAM_TB = test/tb_parameterized_config.v
WAVE_MACROS = test/wave_macros.v

WAIT_CYCLES ?= 2

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
	lint clean sim readme-pdf md-pdfs \
	wave wave-simple wave-burst wave-burst-ext wave-simple-ws wave-param \
	gtk gtk-simple gtk-burst gtk-burst-ext gtk-simple-ws gtk-param

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
	@echo "  Docs:"
	@echo "    make readme-pdf               # README.md -> README.pdf (override README_MD / README_PDF)"
	@echo "    make md-pdfs                  # every *.md under . (except .git) -> sibling .pdf"
	@echo "    PANDOC_PDF_ENGINE=xelatex     # optional, for richer Unicode/fonts"
	@echo ""
	@echo "  Other: make lint | make clean | make check-full"

# --- tests -------------------------------------------------------------------

test: test-all

test-all: test-simple test-burst

test-full: test-simple test-burst test-burst-ext test-param test-simple-ws

check: lint test-all

check-full: lint test-full

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

lint:
	$(IVERILOG) $(IVERILOG_FLAGS) -o /tmp/sim_simple_w $(SIMPLE_TB) $(SIMPLE_RTL)
	$(IVERILOG) $(IVERILOG_FLAGS) -DREAD_WAIT_CYCLES=$(WAIT_CYCLES) -o /tmp/sim_simple_ws_w $(SIMPLE_WS_TB) $(SIMPLE_RTL)
	$(IVERILOG) $(IVERILOG_FLAGS) -o /tmp/sim_burst_w $(BURST_TB) $(BURST_RTL)
	$(IVERILOG) $(IVERILOG_FLAGS) -o /tmp/sim_burst_ext_w $(BURST_EXT_TB) $(BURST_RTL)
	$(IVERILOG) $(IVERILOG_FLAGS) -o /tmp/sim_param_w $(PARAM_TB) $(BURST_RTL)

# --- compile -----------------------------------------------------------------

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

clean:
	rm -f sim_simple sim_burst sim_burst_ext sim_simple_ws_* sim_param \
		waves_*.fst waves_*.vcd burst.vcd param.vcd $(ALL_MD_PDF)
