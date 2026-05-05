IVERILOG ?= iverilog
VVP ?= vvp
GTKWAVE ?= gtkwave
GTKWAVE_FLAGS ?=

IVERILOG_FLAGS ?= -g2012 -Wall -I$(CURDIR)/test

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

.PHONY: help default test test-all test-full check check-full \
	test-simple test-simple-ws test-simple-ws-sweep test-burst test-burst-ext test-param \
	lint clean sim \
	wave wave-simple wave-burst wave-burst-ext wave-simple-ws wave-param \
	gtk gtk-simple gtk-burst gtk-burst-ext gtk-simple-ws gtk-param

default: help

help:
	@echo "IP-axi-to-2apbs — common targets"
	@echo ""
	@echo "  Tests (fast → full):"
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
	@echo "    make sim_simple sim_burst …"
	@echo ""
	@echo "  Waveforms (then open GTKWave yourself, or use gtk targets below):"
	@echo "    make wave                   # WAVETB=simple|burst|burst-ext|simple-ws|param"
	@echo "    make wave-simple | wave-burst | …"
	@echo "    WAVEFMT=fst|vcd   WAVEFILE=path   WAIT_CYCLES=n (for simple-ws)"
	@echo ""
	@echo "  GTKWave (simulate + launch viewer):"
	@echo "    make gtk                    # uses WAVETB (default: simple)"
	@echo "    make gtk-simple | gtk-burst | gtk-burst-ext | gtk-simple-ws | gtk-param"
	@echo "    GTKWAVE=/path/to/gtkwave  GTKWAVE_FLAGS='…'"
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

# Unified wave/gtk defaults (depends on WAVETB)
ifeq ($(WAVETB),simple)
  WAVEFILE ?= waves_simple.$(WAVEFMT)
else ifeq ($(WAVETB),burst)
  WAVEFILE ?= waves_burst.$(WAVEFMT)
else ifeq ($(WAVETB),burst-ext)
  WAVEFILE ?= waves_burst_ext.$(WAVEFMT)
else ifeq ($(WAVETB),simple-ws)
  WAVEFILE ?= waves_simple_ws.$(WAVEFMT)
else ifeq ($(WAVETB),param)
  WAVEFILE ?= waves_param.$(WAVEFMT)
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
GTK_OPEN = @printf 'Opening %s in GTKWave…\n' "$(WAVEFILE)"; \
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

# Dispatch to gtk-simple, gtk-burst, … (avoids duplicating per-bench rules).
gtk:
	$(MAKE) gtk-$(WAVETB)

clean:
	rm -f sim_simple sim_burst sim_burst_ext sim_simple_ws_* sim_param \
		waves_*.fst waves_*.vcd burst.vcd param.vcd
