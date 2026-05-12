# From uvm/xcelium: xrun -64bit -sv -timescale 1ns/1ps -access +rwc -uvmhome $UVM_HOME -f files_burst_ext.f -top tb_uvm_burst_ext
# Requires export UVM_HOME

+incdir+../sv/interfaces

../sv/interfaces/axi4_master_if.sv
../sv/interfaces/apb_sel_tracker_if.sv
../sv/interfaces/apb_burst_ext_side_if.sv

../../src/axi4_to_apb4_2x_burst.v

../sv/models/apb_ext_mem_dual.sv
../sv/pkg/bridge_stimulus_pkg.sv
../sv/interfaces/apb_mon_if.sv
../sv/pkg/bridge_uvm_env_pkg.sv
../sv/pkg/bridge_uvm_tests_pkg.sv
../tb/tb_uvm_burst_ext.sv
