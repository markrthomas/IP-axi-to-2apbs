# hier_inspect.tcl
#
# Hierarchy and signal inspection utilities for interactive Xcelium sessions.
# Source this file at the xcelium> prompt after starting xrun in interactive mode.
#
# Interactive startup:
#   xrun $(XRUN_FLAGS) $(UVM_ARGS) $(IFDIR) \
#        [source files] -top tb_uvm_simple \
#        -log sim_simple.log
#   # xcelium> prompt appears
#   xcelium> source uvm/xcelium/tcl/hier_inspect.tcl
#   xcelium> run 200         ;# advance 200 ns
#   xcelium> bridge_status   ;# call a proc defined below

# ---- hierarchy discovery ----------------------------------------------------

# List all direct children of a scope (modules, interfaces, generates).
proc ls_scope {{scope tb_uvm_simple}} {
    puts "Children of ${scope}:"
    foreach child [describe $scope] {
        puts "  $child"
    }
}

# Recursively list all signals whose name matches a glob pattern.
# Example: find_signals tb_uvm_simple *VALID*
proc find_signals {scope {pattern *}} {
    return [find signals -r "${scope}.${pattern}"]
}

# ---- AXI channel snapshot ---------------------------------------------------

# Print all AXI4 channel signals in a compact one-line-per-channel layout.
proc axi_snapshot {{top tb_uvm_simple}} {
    set i "${top}.axi_if"
    puts "\n=== AXI snapshot @ [time] ==="
    puts [format "  AW: VALID=%-1s READY=%-1s  ADDR=0x%-8s LEN=%-3s BURST=%-1s" \
        [value -radix bin      ${i}.S_AXI_AWVALID] \
        [value -radix bin      ${i}.S_AXI_AWREADY] \
        [value -radix hex      ${i}.S_AXI_AWADDR]  \
        [value -radix unsigned ${i}.S_AXI_AWLEN]   \
        [value -radix unsigned ${i}.S_AXI_AWBURST]]
    puts [format "  W : VALID=%-1s READY=%-1s  DATA=0x%-16s STRB=0x%-2s LAST=%-1s" \
        [value -radix bin ${i}.S_AXI_WVALID] \
        [value -radix bin ${i}.S_AXI_WREADY] \
        [value -radix hex ${i}.S_AXI_WDATA]  \
        [value -radix hex ${i}.S_AXI_WSTRB]  \
        [value -radix bin ${i}.S_AXI_WLAST]]
    puts [format "  B : VALID=%-1s READY=%-1s  RESP=%-1s" \
        [value -radix bin      ${i}.S_AXI_BVALID] \
        [value -radix bin      ${i}.S_AXI_BREADY] \
        [value -radix unsigned ${i}.S_AXI_BRESP]]
    puts [format "  AR: VALID=%-1s READY=%-1s  ADDR=0x%-8s LEN=%-3s BURST=%-1s" \
        [value -radix bin      ${i}.S_AXI_ARVALID] \
        [value -radix bin      ${i}.S_AXI_ARREADY] \
        [value -radix hex      ${i}.S_AXI_ARADDR]  \
        [value -radix unsigned ${i}.S_AXI_ARLEN]   \
        [value -radix unsigned ${i}.S_AXI_ARBURST]]
    puts [format "  R : VALID=%-1s READY=%-1s  DATA=0x%-16s RESP=%-1s LAST=%-1s" \
        [value -radix bin      ${i}.S_AXI_RVALID] \
        [value -radix bin      ${i}.S_AXI_RREADY] \
        [value -radix hex      ${i}.S_AXI_RDATA]  \
        [value -radix unsigned ${i}.S_AXI_RRESP]  \
        [value -radix bin      ${i}.S_AXI_RLAST]]
}

# ---- APB bus snapshot -------------------------------------------------------

# Print both APB ports in a compact table.
proc apb_snapshot {{top tb_uvm_simple}} {
    puts "\n=== APB snapshot @ [time] ==="
    puts "  Port  PSEL PENABLE PWRITE PREADY PSLVERR  PADDR       PWDATA/PRDATA"
    foreach port {0 1} {
        set sel    [value -radix bin      ${top}.PSEL${port}]
        set en     [value -radix bin      ${top}.PENABLE${port}]
        set wr     [value -radix bin      ${top}.PWRITE${port}]
        set rdy    [value -radix bin      ${top}.PREADY${port}]
        set err    [value -radix bin      ${top}.PSLVERR${port}]
        set addr   [value -radix hex      ${top}.PADDR${port}]
        set wdata  [value -radix hex      ${top}.PWDATA${port}]
        set rdata  [value -radix hex      ${top}.PRDATA${port}]
        if { $wr == 1 } {
            set data "W:0x${wdata}"
        } else {
            set data "R:0x${rdata}"
        }
        puts [format "  APB%s  %-4s %-7s %-6s %-6s %-8s 0x%-10s %s" \
              $port $sel $en $wr $rdy $err $addr $data]
    }
}

# ---- combined bridge status -------------------------------------------------

# One-call snapshot of both AXI and APB buses.
proc bridge_status {{top tb_uvm_simple}} {
    axi_snapshot $top
    apb_snapshot $top
}

# ---- APB slave memory dump --------------------------------------------------

# Dump the first N words of an APB slave memory model.
# Works with apb_dual_mem_simple / apb_dual_mem_burst (mem0, mem1 arrays).
proc dump_slv_mem {{top tb_uvm_simple} {port 0} {words 8}} {
    puts "\n=== slv.mem${port}\[0:${words}-1\] @ [time] ==="
    for {set i 0} {$i < $words} {incr i} {
        set val [value -radix hex "${top}.slv.mem${port}(${i})"]
        puts [format "  mem%s\[%2d\] = 0x%s" $port $i $val]
    }
}

# ---- watch loop -------------------------------------------------------------

# Poll a signal every INTERVAL_NS nanoseconds and print when it changes.
# Stop after MAX_POLLS polls.  Useful for tracking slow events.
# Example: watch_signal tb_uvm_simple.PSEL0 20 50
proc watch_signal {sig {interval_ns 10} {max_polls 100}} {
    set prev {}
    for {set n 0} {$n < $max_polls} {incr n} {
        set cur [value -radix hex $sig]
        if { $cur ne $prev } {
            puts "\[[time]\] ${sig} changed: ${prev} -> ${cur}"
            set prev $cur
        }
        run ${interval_ns} ns
    }
    puts "watch_signal: stopped after $max_polls polls."
}

# ---- startup message --------------------------------------------------------
puts "\nhier_inspect.tcl loaded.  Available procs:"
puts "  ls_scope      \[scope\]          -- list scope children"
puts "  find_signals  scope \[pattern\]  -- grep signals by glob"
puts "  axi_snapshot  \[top\]            -- print all AXI channel state"
puts "  apb_snapshot  \[top\]            -- print both APB ports"
puts "  bridge_status \[top\]            -- axi_snapshot + apb_snapshot"
puts "  dump_slv_mem  \[top\] \[port\] \[n\] -- dump first n slave mem words"
puts "  watch_signal  sig \[ns\] \[polls\] -- poll and print changes"
puts ""
