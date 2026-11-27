# axi_apb.sdc — timing constraints for IP-axi-to-2apbs (AXI4 → 2× APB4 bridge)
#
# T0/T2 collateral for the tapeout-readiness program. Authored here; run on a real
# STA tool: OpenSTA (run by the sky130 LibreLane flow in CI, syn/pnr/) or PrimeTime
# sign-off against the target library. See syn/SIGNOFF.md.
#
# KEY FACT established by the pathfinder: this IP is SINGLE CLOCK DOMAIN. The only
# clock/reset ports are ACLK and ARESETn (async, active-low). Both APB ports run on
# ACLK — there is NO second (PCLK) domain, so there are NO clock-domain crossings and
# NO CDC timing exceptions to declare. This is why this block leads the program as the
# cheapest flow pathfinder.

#--- Clock -------------------------------------------------------------------
# Placeholder target; set to the real budget at integration. 200 MHz = 5.0 ns.
set CLK_PERIOD 5.0
create_clock -name ACLK -period $CLK_PERIOD [get_ports ACLK]

# No generated clocks, no second domain. (If an APB prescaler divider is added
# later, declare it here with create_generated_clock and this file is the one place
# that changes.)

#--- Reset -------------------------------------------------------------------
# ARESETn is an asynchronous, active-low reset: not a timing path for setup/hold.
set_false_path -from [get_ports ARESETn]

#--- I/O budgets (default: 40% of period in, 40% out) ------------------------
set IN_DEL  [expr {0.40 * $CLK_PERIOD}]
set OUT_DEL [expr {0.40 * $CLK_PERIOD}]
# PrimeTime has remove_from_collection; OpenSTA (LibreLane/OpenROAD) has
# delete_from_list. Use whichever this tool provides.
if {[llength [info commands remove_from_collection]]} {
  set all_in [remove_from_collection [all_inputs] [get_ports {ACLK ARESETn}]]
} else {
  set all_in [delete_from_list [all_inputs] [get_ports {ACLK ARESETn}]]
}
set_input_delay  -clock ACLK $IN_DEL  $all_in
set_output_delay -clock ACLK $OUT_DEL [all_outputs]

#--- Driving cell / load (set at tech mapping) -------------------------------
# set_driving_cell -lib_cell <buf> [all_inputs]
# set_load <cap> [all_outputs]

#--- Exceptions --------------------------------------------------------------
# None. Single clock, fully synchronous datapath; the AXI-serialized-to-APB FSM
# has no multicycle or false paths beyond the async reset above.
