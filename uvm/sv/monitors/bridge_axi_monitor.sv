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

  task wr_loop;
    forever begin
      bridge_axi_wr_tr tr;
      logic [31:0] aw_addr;
      logic [ 7:0] aw_len;
      logic [ 2:0] aw_sz;
      logic [ 1:0] aw_br;
      logic [31:0] aw_id_n;
      int unsigned ix;
      @(posedge vif.clk iff (vif.rst_n && vif.S_AXI_AWVALID && vif.S_AXI_AWREADY));
      aw_addr = vif.S_AXI_AWADDR;
      aw_len  = vif.S_AXI_AWLEN;
      aw_sz   = vif.S_AXI_AWSIZE;
      aw_br   = vif.S_AXI_AWBURST;
      aw_id_n = vif.S_AXI_AWID;
      tr      = bridge_axi_wr_tr::type_id::create("wr_collect");
      ix      = 0;
      tr.addr    = {32'b0, aw_addr};
      tr.awlen   = aw_len;
      tr.awsize  = aw_sz;
      tr.awburst = aw_br;
      tr.id      = aw_id_n;
      tr.wdata.delete();
      tr.wstrb.delete();
      repeat (aw_len + 1) begin
        @(posedge vif.clk iff (vif.rst_n && vif.S_AXI_WVALID && vif.S_AXI_WREADY));
        tr.wdata.push_back(pack_dw(vif.S_AXI_WDATA));
        tr.wstrb.push_back(pack_strb(vif.S_AXI_WSTRB));
        ix++;
      end
      @(posedge vif.clk iff (vif.rst_n && vif.S_AXI_BVALID && vif.S_AXI_BREADY));
      tr.bresp = vif.S_AXI_BRESP;
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
      wr_loop();
      rd_loop();
    join
  endtask
endclass

`endif
