# debug_axi.tcl
#
# Event-driven breakpoints for AXI and APB signal monitoring.
# Each breakpoint prints key channel state then resumes automatically.
#
# Usage (from uvm/xcelium/):
#   xrun $(XRUN_FLAGS) $(UVM_ARGS) $(IFDIR) \
#        [source files] -top tb_uvm_simple \
#        -log sim_simple.log \
#        -input tcl/debug_axi.tcl
#
# Expected output (one block per AXI/APB event, timestamped):
#
#   [105 ns] AXI AW accepted:
#     AWADDR=0x00000010  AWLEN=0  AWSIZE=3  AWBURST=1(INCR)
#   [115 ns] APB0 setup phase:
#     PADDR=0x00000010  PWRITE=1  PWDATA=0xdeadbeefcafebabe
#   [120 ns] APB0 completed (PREADY=1):
#     PSLVERR=0
#   [125 ns] AXI B response:
#     BRESP=0(OKAY)

# ----- configuration ---------------------------------------------------------
set TOP tb_uvm_simple
set AXI_IF "${TOP}.axi_if"
# -----------------------------------------------------------------------------

# Helper: burst type name
proc burst_name {b} {
    switch $b {
        0 { return "FIXED" }
        1 { return "INCR"  }
        2 { return "WRAP"  }
        default { return "?" }
    }
}

# Helper: BRESP name
proc bresp_name {r} {
    switch $r {
        0 { return "OKAY"   }
        1 { return "EXOKAY" }
        2 { return "SLVERR" }
        3 { return "DECERR" }
        default { return "?" }
    }
}

# ---- AXI write address accepted (AWVALID & AWREADY both high) ---------------
proc on_aw_accepted {} {
    global TOP AXI_IF
    set addr   [value -radix hex  ${AXI_IF}.S_AXI_AWADDR]
    set len    [value -radix unsigned ${AXI_IF}.S_AXI_AWLEN]
    set sz     [value -radix unsigned ${AXI_IF}.S_AXI_AWSIZE]
    set burst  [value -radix unsigned ${AXI_IF}.S_AXI_AWBURST]
    puts "\n\[[time]\] AXI AW accepted:"
    puts "  AWADDR=0x${addr}  AWLEN=${len}  AWSIZE=${sz}  AWBURST=${burst}([burst_name $burst])"
}

# ---- AXI write data beat accepted (WVALID & WREADY) -------------------------
proc on_w_beat {} {
    global AXI_IF
    set data  [value -radix hex     ${AXI_IF}.S_AXI_WDATA]
    set strb  [value -radix hex     ${AXI_IF}.S_AXI_WSTRB]
    set last  [value -radix unsigned ${AXI_IF}.S_AXI_WLAST]
    puts "\[[time]\] AXI W beat: WDATA=0x${data}  WSTRB=0x${strb}  WLAST=${last}"
}

# ---- APB port event ---------------------------------------------------------
proc on_apb_setup {port} {
    global TOP
    set addr  [value -radix hex     ${TOP}.PADDR${port}]
    set wr    [value -radix unsigned ${TOP}.PWRITE${port}]
    set wdata [value -radix hex     ${TOP}.PWDATA${port}]
    puts "\n\[[time]\] APB${port} setup phase:"
    puts "  PADDR=0x${addr}  PWRITE=${wr}  PWDATA=0x${wdata}"
}

proc on_apb_complete {port} {
    global TOP
    set slverr [value -radix unsigned ${TOP}.PSLVERR${port}]
    set rdata  [value -radix hex     ${TOP}.PRDATA${port}]
    set wr     [value -radix unsigned ${TOP}.PWRITE${port}]
    if { $wr == 0 } {
        puts "\[[time]\] APB${port} completed: PSLVERR=${slverr}  PRDATA=0x${rdata}"
    } else {
        puts "\[[time]\] APB${port} completed: PSLVERR=${slverr}"
    }
}

# ---- AXI B response ---------------------------------------------------------
proc on_b_response {} {
    global AXI_IF
    set resp [value -radix unsigned ${AXI_IF}.S_AXI_BRESP]
    puts "\n\[[time]\] AXI B response: BRESP=${resp}([bresp_name $resp])"
}

# ---- AXI R beat -------------------------------------------------------------
proc on_r_beat {} {
    global AXI_IF
    set rdata [value -radix hex     ${AXI_IF}.S_AXI_RDATA]
    set rresp [value -radix unsigned ${AXI_IF}.S_AXI_RRESP]
    set rlast [value -radix unsigned ${AXI_IF}.S_AXI_RLAST]
    puts "\[[time]\] AXI R beat: RDATA=0x${rdata}  RRESP=${rresp}([bresp_name $rresp])  RLAST=${rlast}"
}

# ---- register breakpoints ---------------------------------------------------

# AXI write address handshake: fire when AWREADY goes high while AWVALID is high
stop -name aw_accept \
     -signal  ${AXI_IF}.S_AXI_AWREADY \
     -posedge \
     -command { if {[value -radix unsigned ${AXI_IF}.S_AXI_AWVALID] == 1} \
                    { on_aw_accepted }; run }

# AXI write data beat
stop -name w_beat \
     -signal  ${AXI_IF}.S_AXI_WREADY \
     -posedge \
     -command { if {[value -radix unsigned ${AXI_IF}.S_AXI_WVALID] == 1} \
                    { on_w_beat }; run }

# APB0 setup (PSEL asserts, PENABLE deasserted = setup phase)
stop -name apb0_setup \
     -signal  ${TOP}.PSEL0 \
     -posedge \
     -command { on_apb_setup 0; run }

# APB0 complete (PREADY asserts during access phase)
stop -name apb0_done \
     -signal  ${TOP}.PREADY0 \
     -posedge \
     -command { if {[value -radix unsigned ${TOP}.PENABLE0] == 1} \
                    { on_apb_complete 0 }; run }

# APB1 setup
stop -name apb1_setup \
     -signal  ${TOP}.PSEL1 \
     -posedge \
     -command { on_apb_setup 1; run }

# APB1 complete
stop -name apb1_done \
     -signal  ${TOP}.PREADY1 \
     -posedge \
     -command { if {[value -radix unsigned ${TOP}.PENABLE1] == 1} \
                    { on_apb_complete 1 }; run }

# AXI B response
stop -name b_resp \
     -signal  ${AXI_IF}.S_AXI_BVALID \
     -posedge \
     -command { on_b_response; run }

# AXI R beat
stop -name r_beat \
     -signal  ${AXI_IF}.S_AXI_RVALID \
     -posedge \
     -command { on_r_beat; run }

puts "debug_axi.tcl loaded: 8 breakpoints active on ${TOP}"
puts "Running simulation...\n"
run
exit
