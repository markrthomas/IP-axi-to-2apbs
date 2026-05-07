`ifndef BRIDGE_APB_MONITOR_SV
`define BRIDGE_APB_MONITOR_SV

class bridge_apb_monitor #(int DW = 64, int AW = 32) extends uvm_component;
  `uvm_component_param_utils(bridge_apb_monitor #(DW, AW))

  int unsigned                                       port_ix;
  bridge_env_cfg                                     cfg;
  virtual apb_mon_if #(
    .ADDR_WIDTH(AW),
    .DATA_WIDTH(DW)
  )                                                      vif;
  uvm_analysis_port #(bridge_apb_tr) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg == null)
      `uvm_fatal(get_type_name(), "apb_monitor requires env cfg (set parent before build)")
    if (!uvm_config_db #(
            virtual apb_mon_if #(
              .ADDR_WIDTH(AW),
              .DATA_WIDTH(DW)
            ))::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "apb_monitor vif missing")
  endfunction

  function logic [63:0] pb_pack(logic [DW-1:0] din);
    if (DW < 64) return {{(64 - DW) {1'b0}}, din};
    return din;
  endfunction

  function logic [7:0] pb_strb_pack(logic [(DW / 8)-1:0] sin);
    if ((DW / 8) >= 8) return sin;
    return {{(8 - (DW / 8)) {1'b0}}, sin};
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      bridge_apb_tr t;
      @(posedge vif.clk iff (vif.rst_n && vif.PSEL && vif.PENABLE && vif.PREADY));
      if (!cfg.enable_apb_mons) continue;
      t = bridge_apb_tr::type_id::create($sformatf("apb_evt_%t", $time));
      t.port         = port_ix;
      t.paddr        = 64'h0;
      if (AW > 0) t.paddr[AW-1:0] = vif.PADDR;
      t.pwrite        = vif.PWRITE;
      t.pwdata        = pb_pack(vif.PWDATA);
      t.pstrb         = pb_strb_pack(vif.PSTRB);
      t.prdata        = pb_pack(vif.PRDATA);
      t.pslverr       = vif.PSLVERR;
      ap.write(t);
    end
  endtask
endclass

`endif
