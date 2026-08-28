`ifndef BRIDGE_AXI_MONITOR_SV
`define BRIDGE_AXI_MONITOR_SV

class bridge_axi_monitor #(int DW = 64) extends uvm_component;
  `uvm_component_param_utils(bridge_axi_monitor #(DW))

  bridge_env_cfg                        cfg;
  virtual axi4_master_if #(
      .ID_WIDTH(4),
      .ADDR_WIDTH(32),
      .DATA_WIDTH(DW)
  )
  vif;
  uvm_analysis_port #(bridge_axi_wr_tr) ap_wr;
  uvm_analysis_port #(bridge_axi_rd_tr) ap_rd;

  // Decoupled write-channel capture queues (see wr_aw/w/b_capture): AW
  // descriptors and completed W data-bursts awaiting their B response.
  bridge_axi_wr_tr aw_pend[$];
  bridge_axi_wr_tr wd_pend[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap_wr = new("ap_wr", this);
    ap_rd = new("ap_rd", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg == null)
      void'(uvm_config_db #(bridge_env_cfg)::get(this, "", "cfg", cfg));
    if (cfg == null) cfg = bridge_env_cfg::type_id::create("axi_mon_fallback_cfg");
    if (!uvm_config_db #(virtual axi4_master_if #(4, 32, DW))::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), $sformatf("AXI #(DW=%0d) vif missing", DW))
  endfunction

  function logic [63:0] pack_dw(logic [DW-1:0] din);
    if (DW < 64) return {{(64 - DW) {1'b0}}, din};
    return din;
  endfunction

  function logic [7:0] pack_strb(logic [(DW / 8)-1:0] sin);
    if ((DW / 8) >= 8) return sin;
    return {{(8 - (DW / 8)) {1'b0}}, sin};
  endfunction

  // The write side captures each AXI channel (AW / W / B) in its own always-
  // armed process and reassembles a transaction at the B response.  A single
  // blocking AW->W->B->restart loop can miss a channel event that occurs while
  // it is blocked on another channel — an ordering that VCS and Verilator's
  // --timing scheduler resolve differently — so decoupling keeps the monitor
  // correct on both.  The bridge is single-outstanding, so the pending queues
  // hold at most one entry and in-order pairing is exact.

  task wr_aw_capture;
    forever begin
      bridge_axi_wr_tr d;
      @(posedge vif.clk iff (vif.rst_n && vif.S_AXI_AWVALID && vif.S_AXI_AWREADY));
      d = bridge_axi_wr_tr::type_id::create("aw_desc");
      d.addr    = {32'b0, vif.S_AXI_AWADDR};
      d.awlen   = vif.S_AXI_AWLEN;
      d.awsize  = vif.S_AXI_AWSIZE;
      d.awburst = vif.S_AXI_AWBURST;
      d.id      = vif.S_AXI_AWID;
      aw_pend.push_back(d);
    end
  endtask

  task wr_w_capture;
    forever begin
      bridge_axi_wr_tr d;
      d = bridge_axi_wr_tr::type_id::create("w_burst");
      d.wdata.delete();
      d.wstrb.delete();
      // Accumulate beats until WLAST delimits the burst (length-independent, so
      // it does not need the AW descriptor to have arrived first).
      // The bvalid_arm provides an escape when the bridge terminates early
      // without WLAST (wlast_err path): once at least one beat is captured,
      // a rising BVALID signals that no further WREADY beats will come.
      fork
        begin : wbeat_arm
          forever begin
            @(posedge vif.clk iff (vif.rst_n && vif.S_AXI_WVALID && vif.S_AXI_WREADY));
            d.wdata.push_back(pack_dw(vif.S_AXI_WDATA));
            d.wstrb.push_back(pack_strb(vif.S_AXI_WSTRB));
            if (vif.S_AXI_WLAST) break;
          end
        end
        begin : bvalid_arm
          // Guard: only let BVALID terminate the accumulation after at least
          // one beat has been captured, so a BVALID left over from the
          // previous transaction (before any beat for the new one is seen)
          // does not prematurely close the descriptor.
          @(posedge vif.clk iff (vif.rst_n && vif.S_AXI_BVALID &&
                                 (d.wdata.size() > 0)));
        end
      join_any
      disable fork;
      wd_pend.push_back(d);
    end
  endtask

  task wr_b_capture;
    forever begin
      bridge_axi_wr_tr tr;
      bridge_axi_wr_tr awd;
      bridge_axi_wr_tr wdd;
      @(posedge vif.clk iff (vif.rst_n && vif.S_AXI_BVALID && vif.S_AXI_BREADY));
      // AW/W precede B, so their descriptors are normally already queued; guard
      // against a same-edge delta ordering by advancing until both are present.
      while (aw_pend.size() == 0 || wd_pend.size() == 0)
        @(posedge vif.clk);
      awd = aw_pend.pop_front();
      wdd = wd_pend.pop_front();
      tr  = bridge_axi_wr_tr::type_id::create("wr_collect");
      tr.addr    = awd.addr;
      tr.awlen   = awd.awlen;
      tr.awsize  = awd.awsize;
      tr.awburst = awd.awburst;
      tr.id      = awd.id;
      tr.wdata   = wdd.wdata;
      tr.wstrb   = wdd.wstrb;
      tr.bresp   = vif.S_AXI_BRESP;
      ap_wr.write(tr);
    end
  endtask

  task rd_loop;
    forever begin
      bridge_axi_rd_tr tr;
      logic [31:0] ar_addr;
      logic [ 7:0] ar_len;
      logic [ 2:0] ar_sz;
      logic [ 1:0] ar_br;
      logic [31:0] ar_id_n;
      int unsigned bx;
      @(posedge vif.clk iff (vif.rst_n && vif.S_AXI_ARVALID && vif.S_AXI_ARREADY));
      ar_addr = vif.S_AXI_ARADDR;
      ar_len  = vif.S_AXI_ARLEN;
      ar_sz   = vif.S_AXI_ARSIZE;
      ar_br   = vif.S_AXI_ARBURST;
      ar_id_n = vif.S_AXI_ARID;
      tr      = bridge_axi_rd_tr::type_id::create("rd_collect");
      tr.addr     = {32'b0, ar_addr};
      tr.arlen    = ar_len;
      tr.arsize   = ar_sz;
      tr.arburst  = ar_br;
      tr.id       = ar_id_n;
      tr.rdata.delete();
      for (
          bx = 0;
          bx <= ar_len;
          bx++
        ) begin
        @(posedge vif.clk iff (vif.rst_n && vif.S_AXI_RVALID && vif.S_AXI_RREADY));
        tr.rdata.push_back(pack_dw(vif.S_AXI_RDATA));
        if (vif.S_AXI_RLAST && bx != ar_len)
          `uvm_warning(get_type_name(), "RLAST before final beat");
        if (vif.S_AXI_RLAST) begin
          tr.rresp = vif.S_AXI_RRESP;
          ap_rd.write(tr);
        end
      end
    end
  endtask

  task run_phase(uvm_phase phase);
    if (!cfg.enable_axi_mon) return;
    fork
      wr_aw_capture();
      wr_w_capture();
      wr_b_capture();
      rd_loop();
    join
  endtask
endclass

`endif
