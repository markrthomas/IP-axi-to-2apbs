# Requires export UVM_HOME

+incdir+${UVM_HOME}/src
${UVM_HOME}/src/uvm.sv

+incdir+../sv/interfaces
+incdir+../sv/pkg
+incdir+../sv/env
+incdir+../sv/monitors
+incdir+../sv/scoreboard
+incdir+../sv/transactions
+incdir+../sv/cov
+incdir+../sv/seq

../sv/interfaces/axi4_master_if.sv
../sv/interfaces/apb_sel_tracker_if.sv
../sv/interfaces/apb_burst_ext_side_if.sv

../../src/axi4_to_apb4_2x_burst.v

../sv/models/apb_dual_mem_burst.sv
../sv/pkg/bridge_stimulus_pkg.sv
../sv/interfaces/apb_mon_if.sv
../sv/pkg/bridge_uvm_env_pkg.sv
../sv/pkg/bridge_uvm_tests_pkg.sv
../tb/tb_uvm_burst.sv
