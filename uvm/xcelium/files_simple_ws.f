# From uvm/xcelium: xrun -64bit -sv -timescale 1ns/1ps -access +rwc -uvmhome $UVM_HOME +define+BRIDGE_READ_WS=2 -f files_simple_ws.f -top tb_uvm_simple_ws
# Requires export UVM_HOME

+incdir+../sv/interfaces
+incdir+../sv/pkg
+incdir+../sv/env
+incdir+../sv/monitors
+incdir+../sv/scoreboard
+incdir+../sv/transactions

../sv/interfaces/axi4_master_if.sv
../sv/interfaces/apb_sel_tracker_if.sv
../sv/interfaces/apb_burst_ext_side_if.sv

../../src/axi4_to_apb4_2x_simple.v

../sv/models/apb_dual_mem_ws.sv
../sv/pkg/bridge_stimulus_pkg.sv
../sv/interfaces/apb_mon_if.sv
../sv/pkg/bridge_uvm_env_pkg.sv
../sv/pkg/bridge_uvm_tests_pkg.sv
../tb/tb_uvm_simple_ws.sv
