`ifndef BRIDGE_ENV_SV
`define BRIDGE_ENV_SV

class bridge_env #(int DW = 64) extends uvm_env;
  `uvm_component_param_utils(bridge_env #(DW))

  bridge_env_cfg                   cfg;
  bridge_axi_monitor         #(DW) axi_mon;
  bridge_apb_monitor         #(DW, 32) apb_mon0;
  bridge_apb_monitor         #(DW, 32) apb_mon1;
  bridge_scoreboard                sb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(bridge_env_cfg)::get(this, "", "cfg", cfg))
      cfg = bridge_env_cfg::type_id::create("cfg");
    cfg.data_width = DW;
    cfg.addr_width = 32;

    axi_mon                = bridge_axi_monitor #(DW)::type_id::create("axi_mon", this);
    apb_mon0               = bridge_apb_monitor #(DW, 32)::type_id::create("apb_mon0", this);
    apb_mon1               = bridge_apb_monitor #(DW, 32)::type_id::create("apb_mon1", this);
    sb                     = null;
    if (cfg.has_scoreboard) sb = bridge_scoreboard::type_id::create("sb", this);

    axi_mon.cfg            = cfg;
    apb_mon0.cfg           = cfg;
    apb_mon1.cfg           = cfg;
    if (sb != null) sb.cfg = cfg;
    apb_mon0.port_ix = 0;
    apb_mon1.port_ix = 1;
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (sb != null) begin
      axi_mon.ap_wr.connect(sb.axi_wr_imp);
      axi_mon.ap_rd.connect(sb.axi_rd_imp);
      apb_mon0.ap.connect(sb.apb0_imp);
      apb_mon1.ap.connect(sb.apb1_imp);
    end
  endfunction
endclass

`endif
