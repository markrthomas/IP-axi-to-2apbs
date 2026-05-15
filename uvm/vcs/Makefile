# From uvm/vcs/:   export UVM_HOME=...   &&   make sim_simple

UVM_HOME ?= $(error Set UVM_HOME (directory containing src/uvm.sv))

VCS       ?= vcs
VCS_FLAGS ?= -full64 -sverilog -timescale=1ns/1ps +acc +vpi

UVM_SRC   = +incdir+$(UVM_HOME)/src $(UVM_HOME)/src/uvm.sv
IFDIR     = +incdir+$(abspath ../sv/interfaces) \
            +incdir+$(abspath ../sv/pkg) \
            +incdir+$(abspath ../sv/env) \
            +incdir+$(abspath ../sv/monitors) \
            +incdir+$(abspath ../sv/scoreboard) \
            +incdir+$(abspath ../sv/transactions) \
            +incdir+$(abspath ../sv/cov) \
            +incdir+$(abspath ../sv/seq)
RTL       = $(abspath ../../src)

READ_WS ?= 2

.PHONY: sim_simple sim_burst sim_burst_ext sim_simple_ws sim_parameterized \
        sim_rand_burst sim_rand_integrity sim_stress \
        sim_regblock_hw_reset sim_regblock_bit_bash \
        sim_regblock_reg_access sim_regblock_directed clean

REGBLOCK_FILES = \
  $(RTL)/axi3lite_regblock.v \
  ../sv/interfaces/axi3lite_if.sv \
  ../sv/pkg/regblock_stimulus_pkg.sv \
  ../sv/pkg/regblock_uvm_env_pkg.sv \
  ../sv/pkg/regblock_uvm_tests_pkg.sv \
  ../tb/tb_uvm_regblock.sv

sim_regblock_hw_reset:
	$(VCS) $(VCS_FLAGS) $(UVM_SRC) $(IFDIR) $(REGBLOCK_FILES) \
	  -o sim_regblock -top tb_uvm_regblock
	./sim_regblock +UVM_TESTNAME=test_regblock_hw_reset -l sim_regblock_hw_reset.log

sim_regblock_bit_bash:
	$(VCS) $(VCS_FLAGS) $(UVM_SRC) $(IFDIR) $(REGBLOCK_FILES) \
	  -o sim_regblock -top tb_uvm_regblock
	./sim_regblock +UVM_TESTNAME=test_regblock_bit_bash -l sim_regblock_bit_bash.log

sim_regblock_reg_access:
	$(VCS) $(VCS_FLAGS) $(UVM_SRC) $(IFDIR) $(REGBLOCK_FILES) \
	  -o sim_regblock -top tb_uvm_regblock
	./sim_regblock +UVM_TESTNAME=test_regblock_reg_access -l sim_regblock_reg_access.log

sim_regblock_directed:
	$(VCS) $(VCS_FLAGS) $(UVM_SRC) $(IFDIR) $(REGBLOCK_FILES) \
	  -o sim_regblock -top tb_uvm_regblock
	./sim_regblock +UVM_TESTNAME=test_regblock_directed -l sim_regblock_directed.log

sim_simple:
	$(VCS) $(VCS_FLAGS) $(UVM_SRC) $(IFDIR) \
	  $(RTL)/axi4_to_apb4_2x_simple.v \
	  ../sv/interfaces/axi4_master_if.sv \
	  ../sv/interfaces/apb_sel_tracker_if.sv \
	  ../sv/interfaces/apb_burst_ext_side_if.sv \
	  ../sv/models/apb_dual_mem_simple.sv \
	  ../sv/pkg/bridge_stimulus_pkg.sv \
	  ../sv/interfaces/apb_mon_if.sv \
	  ../sv/pkg/bridge_uvm_env_pkg.sv \
	  ../sv/pkg/bridge_uvm_tests_pkg.sv \
	  ../tb/tb_uvm_simple.sv \
	  -o sim_simple -top tb_uvm_simple
	./sim_simple -l sim_simple.log

sim_burst:
	$(VCS) $(VCS_FLAGS) $(UVM_SRC) $(IFDIR) \
	  $(RTL)/axi4_to_apb4_2x_burst.v \
	  ../sv/interfaces/axi4_master_if.sv \
	  ../sv/interfaces/apb_sel_tracker_if.sv \
	  ../sv/interfaces/apb_burst_ext_side_if.sv \
	  ../sv/models/apb_dual_mem_burst.sv \
	  ../sv/pkg/bridge_stimulus_pkg.sv \
	  ../sv/interfaces/apb_mon_if.sv \
	  ../sv/pkg/bridge_uvm_env_pkg.sv \
	  ../sv/pkg/bridge_uvm_tests_pkg.sv \
	  ../tb/tb_uvm_burst.sv \
	  -o sim_burst -top tb_uvm_burst
	./sim_burst -l sim_burst.log

sim_burst_ext:
	$(VCS) $(VCS_FLAGS) $(UVM_SRC) $(IFDIR) \
	  $(RTL)/axi4_to_apb4_2x_burst.v \
	  ../sv/interfaces/axi4_master_if.sv \
	  ../sv/interfaces/apb_sel_tracker_if.sv \
	  ../sv/interfaces/apb_burst_ext_side_if.sv \
	  ../sv/models/apb_ext_mem_dual.sv \
	  ../sv/pkg/bridge_stimulus_pkg.sv \
	  ../sv/interfaces/apb_mon_if.sv \
	  ../sv/pkg/bridge_uvm_env_pkg.sv \
	  ../sv/pkg/bridge_uvm_tests_pkg.sv \
	  ../tb/tb_uvm_burst_ext.sv \
	  -o sim_burst_ext -top tb_uvm_burst_ext
	./sim_burst_ext -l sim_burst_ext.log

sim_simple_ws:
	$(VCS) $(VCS_FLAGS) $(UVM_SRC) $(IFDIR) \
	  $(RTL)/axi4_to_apb4_2x_simple.v \
	  ../sv/interfaces/axi4_master_if.sv \
	  ../sv/interfaces/apb_sel_tracker_if.sv \
	  ../sv/interfaces/apb_burst_ext_side_if.sv \
	  ../sv/models/apb_dual_mem_ws.sv \
	  ../sv/pkg/bridge_stimulus_pkg.sv \
	  ../sv/interfaces/apb_mon_if.sv \
	  ../sv/pkg/bridge_uvm_env_pkg.sv \
	  ../sv/pkg/bridge_uvm_tests_pkg.sv \
	  ../tb/tb_uvm_simple_ws.sv \
	  +define+BRIDGE_READ_WS=$(READ_WS) \
	  -o sim_simple_ws -top tb_uvm_simple_ws
	./sim_simple_ws -l sim_simple_ws.log

sim_parameterized:
	$(VCS) $(VCS_FLAGS) $(UVM_SRC) $(IFDIR) \
	  $(RTL)/axi4_to_apb4_2x_burst.v \
	  ../sv/interfaces/axi4_master_if.sv \
	  ../sv/interfaces/apb_sel_tracker_if.sv \
	  ../sv/interfaces/apb_burst_ext_side_if.sv \
	  ../sv/models/apb_dual_mem_param.sv \
	  ../sv/pkg/bridge_stimulus_pkg.sv \
	  ../sv/interfaces/apb_mon_if.sv \
	  ../sv/pkg/bridge_uvm_env_pkg.sv \
	  ../sv/pkg/bridge_uvm_tests_pkg.sv \
	  ../tb/tb_uvm_parameterized.sv \
	  -o sim_parameterized -top tb_uvm_parameterized
	./sim_parameterized -l sim_parameterized.log

sim_rand_burst:
	$(VCS) $(VCS_FLAGS) $(UVM_SRC) $(IFDIR) \
	  $(RTL)/axi4_to_apb4_2x_burst.v \
	  ../sv/interfaces/axi4_master_if.sv \
	  ../sv/interfaces/apb_sel_tracker_if.sv \
	  ../sv/interfaces/apb_burst_ext_side_if.sv \
	  ../sv/models/apb_ext_mem_dual.sv \
	  ../sv/pkg/bridge_stimulus_pkg.sv \
	  ../sv/interfaces/apb_mon_if.sv \
	  ../sv/pkg/bridge_uvm_env_pkg.sv \
	  ../sv/pkg/bridge_uvm_tests_pkg.sv \
	  ../tb/tb_uvm_burst_ext.sv \
	  -o sim_rand_burst -top tb_uvm_burst_ext
	./sim_rand_burst +UVM_TESTNAME=test_bridge_rand_burst -l sim_rand_burst.log

sim_rand_integrity:
	$(VCS) $(VCS_FLAGS) $(UVM_SRC) $(IFDIR) \
	  $(RTL)/axi4_to_apb4_2x_burst.v \
	  ../sv/interfaces/axi4_master_if.sv \
	  ../sv/interfaces/apb_sel_tracker_if.sv \
	  ../sv/interfaces/apb_burst_ext_side_if.sv \
	  ../sv/models/apb_ext_mem_dual.sv \
	  ../sv/pkg/bridge_stimulus_pkg.sv \
	  ../sv/interfaces/apb_mon_if.sv \
	  ../sv/pkg/bridge_uvm_env_pkg.sv \
	  ../sv/pkg/bridge_uvm_tests_pkg.sv \
	  ../tb/tb_uvm_burst_ext.sv \
	  -o sim_rand_integrity -top tb_uvm_burst_ext
	./sim_rand_integrity +UVM_TESTNAME=test_bridge_rand_integrity -l sim_rand_integrity.log

STRESS_N ?= 100

sim_stress:
	$(VCS) $(VCS_FLAGS) $(UVM_SRC) $(IFDIR) \
	  $(RTL)/axi4_to_apb4_2x_burst.v \
	  ../sv/interfaces/axi4_master_if.sv \
	  ../sv/interfaces/apb_sel_tracker_if.sv \
	  ../sv/interfaces/apb_burst_ext_side_if.sv \
	  ../sv/models/apb_ext_mem_dual.sv \
	  ../sv/pkg/bridge_stimulus_pkg.sv \
	  ../sv/interfaces/apb_mon_if.sv \
	  ../sv/pkg/bridge_uvm_env_pkg.sv \
	  ../sv/pkg/bridge_uvm_tests_pkg.sv \
	  ../tb/tb_uvm_burst_ext.sv \
	  -o sim_stress -top tb_uvm_burst_ext
	./sim_stress +UVM_TESTNAME=test_bridge_stress +N=$(STRESS_N) \
	  -l sim_stress.log

clean:
	rm -f sim_simple sim_burst sim_burst_ext sim_simple_ws sim_parameterized \
	      sim_rand_burst sim_rand_integrity sim_stress sim_regblock
	rm -f sim_simple.log sim_burst.log sim_burst_ext.log sim_simple_ws.log \
	      sim_parameterized.log sim_rand_burst.log sim_rand_integrity.log \
	      sim_stress.log sim_regblock_hw_reset.log sim_regblock_bit_bash.log \
	      sim_regblock_reg_access.log sim_regblock_directed.log
	rm -rf csrc vc_hdrs.h ucli.key simv.daidir DVEfiles
