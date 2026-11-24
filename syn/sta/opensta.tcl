# opensta.tcl — STA driver for IP-axi-to-2apbs (T2 collateral).
#
# Authored for the tapeout-readiness program; NOT run in this workspace (no OpenSTA
# and no target liberty here). This is the exact script a team with OpenSTA (open
# pathfind) or PrimeTime (sign-off) runs. See syn/SIGNOFF.md.
#
# Prereqs the runner supplies:
#   LIB     — target standard-cell liberty (e.g. sky130_fd_sc_hd__tt_025C_1v80.lib)
#   NETLIST — gate netlist from a liberty-mapped synth (extend syn/synth.sh with
#             `dfflibmap -liberty $LIB; abc -liberty $LIB; write_verilog -noattr`)
#   TOP     — axi4_to_apb4_2x_simple | axi4_to_apb4_2x_burst
#
# Run:  sta -exit syn/sta/opensta.tcl   (with LIB/NETLIST/TOP set in the env)

if {![info exists ::env(LIB)] || ![info exists ::env(NETLIST)] || ![info exists ::env(TOP)]} {
  puts "SKIP: set LIB, NETLIST, TOP (see header). No liberty/OpenSTA in this workspace."
  exit 0
}
read_liberty $::env(LIB)
read_verilog  $::env(NETLIST)
link_design   $::env(TOP)
read_sdc      [file join [file dirname [info script]] .. constraints axi_apb.sdc]

report_checks -path_delay max -fields {slew cap input nets fanout} -digits 4
report_checks -path_delay min -digits 4
report_worst_slack -max
report_worst_slack -min
report_tns
report_wns
report_check_types -violators
