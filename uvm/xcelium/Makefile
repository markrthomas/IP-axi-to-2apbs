# From uvm/xcelium/:   export UVM_HOME=...   &&   make sim_simple

UVM_HOME ?= $(error Set UVM_HOME (directory containing src/uvm.sv))

XRUN       ?= xrun
XRUN_FLAGS ?= -64bit -sv -timescale 1ns/1ps -access +rwc

UVM_ARGS  = -uvmhome $(UVM_HOME)
IFDIR     = +incdir+$(abspath ../sv/interfaces) \
            +incdir+$(abspath ../sv/pkg) \
            +incdir+$(abspath ../sv/env) \
            +incdir+$(abspath ../sv/monitors) \
            +incdir+$(abspath ../sv/scoreboard) \
            +incdir+$(abspath ../sv/transactions)
RTL       = $(abspath ../../src)

READ_WS ?= 2

.PHONY: sim_simple sim_burst sim_burst_ext sim_simple_ws sim_parameterized clean

sim_simple:
	$(XRUN) $(XRUN_FLAGS) $(UVM_ARGS) $(IFDIR) \
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
	  -top tb_uvm_simple \
	  -log sim_simple.log

sim_burst:
	$(XRUN) $(XRUN_FLAGS) $(UVM_ARGS) $(IFDIR) \
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
	  -top tb_uvm_burst \
	  -log sim_burst.log

sim_burst_ext:
	$(XRUN) $(XRUN_FLAGS) $(UVM_ARGS) $(IFDIR) \
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
	  -top tb_uvm_burst_ext \
	  -log sim_burst_ext.log

sim_simple_ws:
	$(XRUN) $(XRUN_FLAGS) $(UVM_ARGS) $(IFDIR) \
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
	  -top tb_uvm_simple_ws \
	  -log sim_simple_ws.log

sim_parameterized:
	$(XRUN) $(XRUN_FLAGS) $(UVM_ARGS) $(IFDIR) \
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
	  -top tb_uvm_parameterized \
	  -log sim_parameterized.log

clean:
	rm -f sim_simple.log sim_burst.log sim_burst_ext.log sim_simple_ws.log sim_parameterized.log
	rm -rf xcelium.d INCA_libs *.shm xrun.log *.key
