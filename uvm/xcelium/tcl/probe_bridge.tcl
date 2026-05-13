# probe_bridge.tcl
#
# Batch waveform capture for any bridge UVM sim target.
# Pass to xrun with -input; the sim runs to UVM completion and saves an SHM.
#
# Usage (from uvm/xcelium/):
#   xrun $(XRUN_FLAGS) $(UVM_ARGS) $(IFDIR) \
#        [source files] -top tb_uvm_simple \
#        -log sim_simple.log \
#        -input tcl/probe_bridge.tcl
#
# Or from the repo root (edit XRUN_FLAGS in the sub-Makefile, or pass inline):
#   make sim_simple XRUN_FLAGS="-64bit -sv -timescale 1ns/1ps -access +rwc \
#                               -input $(pwd)/uvm/xcelium/tcl/probe_bridge.tcl"
#
# Output:
#   waves_bridge.shm   -- open with: simvision waves_bridge.shm
#   waves_bridge.vcd   -- open with: gtkwave  waves_bridge.vcd

# ----- configuration ---------------------------------------------------------
# Change TOP to the module being simulated.
set TOP tb_uvm_simple

# Choose output format: "shm" (SimVision native) or "vcd" (GTKWave / open).
set WAVE_FMT shm

# Depth: "all" probes every signal in every sub-instance.
# Use a specific scope (e.g. "${TOP}.dut") to limit dump size.
set PROBE_SCOPE $TOP
set PROBE_DEPTH all

# -----------------------------------------------------------------------------

puts "probe_bridge.tcl: top=${TOP}  fmt=${WAVE_FMT}"

if { $WAVE_FMT eq "shm" } {
    database -open -shm wave_db -into waves_bridge.shm -default
    probe -create $PROBE_SCOPE -depth $PROBE_DEPTH -database wave_db
} elseif { $WAVE_FMT eq "vcd" } {
    database -open -vcd wave_db -into waves_bridge.vcd -default
    probe -create $PROBE_SCOPE -depth $PROBE_DEPTH -database wave_db
} else {
    puts "Unknown WAVE_FMT: $WAVE_FMT (use shm or vcd)"
    exit 1
}

# Run to UVM completion (UVM drop_objection ends the run_phase).
run

set end_time [time]
puts "Simulation finished at ${end_time}."
puts "Waveform written to waves_bridge.${WAVE_FMT}"

exit
