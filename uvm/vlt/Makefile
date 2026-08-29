# Verilator UVM flow for the AXI4->2xAPB4 bridge UVM environment.
#
# Runs the *same* SystemVerilog UVM env as the VCS/Xcelium flows (../sv, ../tb)
# but under open-source Verilator (>= 5.050, which can elaborate/run UVM) using
# the Accellera UVM 2020.3.1 library that ships bundled in the Verilator source
# tree (test_regress/t/uvm) — the same library mirrored at
# https://github.com/chipsalliance/uvm-verilator.
#
# Quick start (local):
#   export UVM_HOME=/path/to/verilator/test_regress/t/uvm
#   make -C uvm/vlt simple            # build + run tb_uvm_simple
#   make -C uvm/vlt all               # simple + burst + burst_ext + parameterized
#
# NOTE: single-threaded and slow to build/run — this is a correctness flow, not
# a performance one.  Prefer `simple` as a CI smoke test.

VERILATOR ?= verilator

# Directory holding uvm_pkg_all_v2020_3_1_dpi.svh and v2020_3_1/dpi/uvm_dpi.cc.
# Override on the command line or via the environment for your install.
UVM_HOME ?= $(error Set UVM_HOME to the bundled Verilator UVM dir, e.g. \
  /path/to/verilator/test_regress/t/uvm)

UVM_HDR := $(UVM_HOME)/uvm_pkg_all_v2020_3_1_dpi.svh
UVM_DPI := $(UVM_HOME)/v2020_3_1/dpi/uvm_dpi.cc

# Parallelism.  The generated UVM C++ is large; more jobs build faster but use
# more RAM.  BUILD_JOBS=1 is the RAM-safe default; raise it (e.g. nproc) where
# memory allows — CI sets BUILD_JOBS=$(nproc).
BUILD_JOBS ?= 1

# C++ flags for the generated model, forwarded to g++ via verilator --CFLAGS.
# -O0 keeps the (large) UVM compile's RAM/time modest.  On a RAM-tight host where
# even a single-job UVM precompiled-header compile OOM-kills cc1plus (e.g. a small
# cloud instance), append GCC aggressive-GC params to slash peak RSS at the cost
# of compile time, e.g.:
#   make ... CFLAGS_MODEL='-O0 --param ggc-min-expand=1 --param ggc-min-heapsize=32768'
# (also settable via the environment — the Docker image/Railway can export it).
CFLAGS_MODEL ?= -O0

# --binary: self-contained executable; --timing: UVM needs event/#delay support;
# --vpi: UVM DPI/HDL backdoor. -Wno-fatal keeps library-side warnings non-fatal.
# -Wno-COVERIGN silences the (excluded) covergroup notes; width warnings stay
# non-fatal via -Wno-fatal.
VFLAGS ?= --binary --timing --vpi -j $(BUILD_JOBS) --build-jobs $(BUILD_JOBS) \
          -Wno-fatal -Wno-COVERIGN --CFLAGS "$(CFLAGS_MODEL)"

# Runtime plusargs common to every test.
UVM_PLUSARGS ?= +UVM_NO_RELNOTES

VLT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SV      := $(abspath $(VLT_DIR)/../sv)
TB      := $(abspath $(VLT_DIR)/../tb)
RTL     := $(abspath $(VLT_DIR)/../../src)
OBJ     := $(VLT_DIR)/obj

INCS := +incdir+$(SV)/interfaces +incdir+$(SV)/pkg +incdir+$(SV)/env \
        +incdir+$(SV)/monitors +incdir+$(SV)/scoreboard \
        +incdir+$(SV)/transactions +incdir+$(SV)/cov +incdir+$(SV)/seq \
        +incdir+$(UVM_HOME) +incdir+$(VLT_DIR)

# Env/test packages shared by every bridge top (order-independent for Verilator).
COMMON := $(SV)/interfaces/axi4_master_if.sv \
          $(SV)/interfaces/apb_sel_tracker_if.sv \
          $(SV)/interfaces/apb_burst_ext_side_if.sv \
          $(SV)/pkg/bridge_stimulus_pkg.sv \
          $(SV)/interfaces/apb_mon_if.sv \
          $(SV)/pkg/bridge_uvm_env_pkg.sv \
          $(SV)/pkg/bridge_uvm_tests_pkg.sv

# $(call build,<top>,<rtl+model srcs>) -> compile into $(OBJ)/<top>/V<top>
define build
	rm -rf $(OBJ)/$(1)
	mkdir -p $(OBJ)/$(1)
	$(VERILATOR) $(VFLAGS) --top-module $(1) --Mdir $(OBJ)/$(1) $(INCS) \
	  $(UVM_HDR) $(UVM_DPI) $(2) $(COMMON) $(TB)/$(1).sv
endef

# $(call run,<top>,<extra plusargs>) — runs the sim and turns the UVM report
# into a make pass/fail: any non-zero UVM_ERROR/UVM_FATAL count, or a missing
# report (crash before report_phase), fails the target.
define run
	$(OBJ)/$(1)/V$(1) $(UVM_PLUSARGS) $(2) 2>&1 | tee $(OBJ)/$(1)/run.log
	@echo "----- UVM report counts ($(1)) -----"
	@grep -E "UVM_(INFO|WARNING|ERROR|FATAL) :" $(OBJ)/$(1)/run.log || true
	@if grep -qE "UVM_(ERROR|FATAL) :[[:space:]]*[1-9]" $(OBJ)/$(1)/run.log; then \
	  echo "FAIL: $(1) reported UVM_ERROR/UVM_FATAL"; exit 1; \
	elif ! grep -qE "UVM_INFO :" $(OBJ)/$(1)/run.log; then \
	  echo "FAIL: $(1) produced no UVM report (crash before report_phase?)"; exit 1; \
	else echo "PASS: $(1) — clean UVM report (0 errors, 0 fatals)"; fi
endef

# --- RAM-safe lint -----------------------------------------------------------
# Elaborate-only (no C++ build): near-zero memory (~330 MB peak) and a few
# seconds, vs. the multi-GB `--binary` compile.  Use as a CI smoke check and to
# validate sources on RAM-constrained hosts where the full build OOMs.
# No UVM_DPI here (lint does not compile C++).
LINTFLAGS ?= --lint-only --timing -Wno-fatal -Wno-COVERIGN

# $(call lint,<top>,<rtl+model srcs>)
define lint
	$(VERILATOR) $(LINTFLAGS) --top-module $(1) $(INCS) \
	  $(UVM_HDR) $(2) $(COMMON) $(TB)/$(1).sv
endef

.PHONY: all ci simple burst burst_ext parameterized \
        regblock regblock-hw-reset regblock-bit-bash regblock-reg-access \
        regblock-directed regblock-all lint lint-simple lint-burst lint-burst_ext \
        lint-parameterized lint-regblock clean

all: simple burst burst_ext parameterized

# Full license-free gate: elaborate-only lint of every top, then build + run
# each top with the scoreboard/UVM_ERROR gate (all four regblock tests against
# a single regblock build).  This is what the Docker/Railway image runs by
# default — see Dockerfile and the repo-root .railway/railway.ts.
ci: lint all regblock-all

# lint every UVM top (elaborate-only; RAM-safe CI smoke check)
lint: lint-simple lint-burst lint-burst_ext lint-parameterized lint-regblock

lint-simple:
	$(call lint,tb_uvm_simple,$(RTL)/axi4_to_apb4_2x_simple.v \
	  $(SV)/models/apb_dual_mem_simple.sv)

lint-burst:
	$(call lint,tb_uvm_burst,$(RTL)/axi4_to_apb4_2x_burst.v \
	  $(SV)/models/apb_dual_mem_burst.sv)

lint-burst_ext:
	$(call lint,tb_uvm_burst_ext,$(RTL)/axi4_to_apb4_2x_burst.v \
	  $(SV)/models/apb_ext_mem_dual.sv)

lint-parameterized:
	$(call lint,tb_uvm_parameterized,$(RTL)/axi4_to_apb4_2x_burst.v \
	  $(SV)/models/apb_dual_mem_param.sv)

lint-regblock:
	$(VERILATOR) $(LINTFLAGS) --top-module tb_uvm_regblock $(INCS) \
	  $(UVM_HDR) $(REGBLOCK_SRCS) $(TB)/tb_uvm_regblock.sv

simple:
	$(call build,tb_uvm_simple,$(RTL)/axi4_to_apb4_2x_simple.v \
	  $(SV)/models/apb_dual_mem_simple.sv)
	$(call run,tb_uvm_simple,)

burst:
	$(call build,tb_uvm_burst,$(RTL)/axi4_to_apb4_2x_burst.v \
	  $(SV)/models/apb_dual_mem_burst.sv)
	$(call run,tb_uvm_burst,)

burst_ext:
	$(call build,tb_uvm_burst_ext,$(RTL)/axi4_to_apb4_2x_burst.v \
	  $(SV)/models/apb_ext_mem_dual.sv)
	$(call run,tb_uvm_burst_ext,)

parameterized:
	$(call build,tb_uvm_parameterized,$(RTL)/axi4_to_apb4_2x_burst.v \
	  $(SV)/models/apb_dual_mem_param.sv)
	$(call run,tb_uvm_parameterized,)

# --- regblock (axi3lite) UVM top: one build, selectable test via +UVM_TESTNAME ---
REGBLOCK_SRCS := $(RTL)/axi3lite_regblock.v \
                 $(SV)/interfaces/axi3lite_if.sv \
                 $(SV)/pkg/regblock_stimulus_pkg.sv \
                 $(SV)/pkg/regblock_uvm_env_pkg.sv \
                 $(SV)/pkg/regblock_uvm_tests_pkg.sv

regblock:
	rm -rf $(OBJ)/tb_uvm_regblock
	mkdir -p $(OBJ)/tb_uvm_regblock
	$(VERILATOR) $(VFLAGS) --top-module tb_uvm_regblock \
	  --Mdir $(OBJ)/tb_uvm_regblock $(INCS) \
	  $(UVM_HDR) $(UVM_DPI) $(REGBLOCK_SRCS) $(TB)/tb_uvm_regblock.sv

regblock-hw-reset: regblock
	$(call run,tb_uvm_regblock,+UVM_TESTNAME=test_regblock_hw_reset)
regblock-bit-bash: regblock
	$(call run,tb_uvm_regblock,+UVM_TESTNAME=test_regblock_bit_bash)
regblock-reg-access: regblock
	$(call run,tb_uvm_regblock,+UVM_TESTNAME=test_regblock_reg_access)
regblock-directed: regblock
	$(call run,tb_uvm_regblock,+UVM_TESTNAME=test_regblock_directed)

# Build the regblock top once, then run all four register tests against it
# (avoids four full --binary rebuilds).
regblock-all: regblock
	$(call run,tb_uvm_regblock,+UVM_TESTNAME=test_regblock_hw_reset)
	$(call run,tb_uvm_regblock,+UVM_TESTNAME=test_regblock_bit_bash)
	$(call run,tb_uvm_regblock,+UVM_TESTNAME=test_regblock_reg_access)
	$(call run,tb_uvm_regblock,+UVM_TESTNAME=test_regblock_directed)

clean:
	rm -rf $(OBJ)
