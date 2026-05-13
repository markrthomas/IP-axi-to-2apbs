# force_signals.tcl
#
# Demonstrates Xcelium force/release for injecting APB back-pressure.
# Works with tb_uvm_simple_ws where PREADY0/PREADY1 are declared as
# "logic" (driven by the slave model, not a wire from the DUT).
#
# The script overrides PREADY0 to inject additional stall cycles beyond
# those already inserted by apb_dual_mem_ws.  This lets you test the
# bridge's wait-state tolerance without recompiling.
#
# Usage (from uvm/xcelium/):
#   export UVM_HOME=CDNS
#   xrun $(XRUN_FLAGS) $(UVM_ARGS) $(IFDIR) \
#        [source files for sim_simple_ws] \
#        +define+BRIDGE_READ_WS=1 \
#        -top tb_uvm_simple_ws \
#        -log sim_ws_forced.log \
#        -input tcl/force_signals.tcl
#
# The base READ_WS=1 model inserts 1 wait cycle per read.  This script
# adds 3 extra cycles on PREADY0 for the first read, demonstrating
# combined back-pressure.

set TOP tb_uvm_simple_ws
set EXTRA_STALL_NS 30  ;# 3 cycles at 10 ns/cycle

# ---- wait for reset to deassert before doing anything -----------------------
proc on_reset_done {} {
    global TOP EXTRA_STALL_NS
    puts "\n\[[time]\] Reset deasserted -- monitoring for first APB0 read."

    # Arm a one-shot breakpoint on the first APB0 setup phase (read)
    stop -name first_apb0_read \
         -signal  ${TOP}.PSEL0 \
         -posedge -once \
         -command { inject_pready0_stall }
}

# ---- inject extra stall on PREADY0 ------------------------------------------
proc inject_pready0_stall {} {
    global TOP EXTRA_STALL_NS
    # Only stall on a read transaction
    if { [value -radix unsigned ${TOP}.PWRITE0] != 0 } {
        puts "\[[time]\] APB0 PSEL (write) -- not injecting stall."
        run
        return
    }
    puts "\[[time]\] APB0 read detected -- forcing PREADY0 low for ${EXTRA_STALL_NS} ns"
    force -deposit ${TOP}.PREADY0 1'b0

    # Schedule the release using a time-based one-shot breakpoint
    stop -name pready0_release \
         -time [expr {[time_ns] + $EXTRA_STALL_NS}] \
         -once \
         -command {
             global TOP
             puts "\[[time]\] Releasing PREADY0 force"
             release ${TOP}.PREADY0
             run
         }
    run
}

# Helper: return current simulation time as an integer number of nanoseconds.
# [time] returns a string like "105 ns"; extract the number.
proc time_ns {} {
    set t [time]
    # Strip the unit suffix -- works for ns / ps; scale as needed.
    regexp {([0-9]+)} $t match num
    return $num
}

# ---- arm the reset breakpoint -----------------------------------------------
stop -name rst_done \
     -signal  ${TOP}.rst_n \
     -posedge -once \
     -command { on_reset_done; run }

puts "force_signals.tcl loaded on ${TOP}"
puts "Will inject a ${EXTRA_STALL_NS} ns PREADY0 stall on the first APB0 read.\n"
run
exit
