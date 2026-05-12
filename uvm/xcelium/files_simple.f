# From uvm/xcelium: xrun -64bit -sv -timescale 1ns/1ps -access +rwc -uvmhome $UVM_HOME -f files_simple.f -top tb_uvm_simple
# Requires export UVM_HOME  (-uvmhome replaces the explicit uvm.sv needed by VCS)

+incdir+../sv/interfaces

../sv/interfaces/axi4_master_if.sv
../sv/interfaces/apb_sel_tracker_if.sv
../sv/interfaces/apb_burst_ext_side_if.sv

../../src/axi4_to_apb4_2x_simple.v

../sv/models/apb_dual_mem_simple.sv
../sv/pkg/bridge_stimulus_pkg.sv
../sv/interfaces/apb_mon_if.sv
../sv/pkg/bridge_uvm_env_pkg.sv
../sv/pkg/bridge_uvm_tests_pkg.sv
../tb/tb_uvm_simple.sv
