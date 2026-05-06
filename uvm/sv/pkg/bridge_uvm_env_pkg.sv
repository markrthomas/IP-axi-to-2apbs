`ifndef BRIDGE_UVM_ENV_PKG_SV
`define BRIDGE_UVM_ENV_PKG_SV

package bridge_uvm_env_pkg;
  import uvm_pkg::*;
`include "uvm_macros.svh"
  import bridge_stimulus_pkg::*;

  typedef enum int {BRIDGE_DECODE_SIMPLE = 0, BRIDGE_DECODE_BURST = 1} bridge_decode_kind_e;

  //---------------------------------------------------------------------------
  // Config
  //---------------------------------------------------------------------------
  class bridge_env_cfg extends uvm_object;
    `uvm_object_utils(bridge_env_cfg)

    int unsigned           data_width         = 64;
    int unsigned           addr_width         = 32;
    int unsigned           apb_sel_bit        = 31;
    bridge_decode_kind_e decode_kind           = BRIDGE_DECODE_BURST;
    int unsigned           apb_mem_addr_msb   = 9;
    int unsigned           apb_mem_addr_lsb = 2;
    bit                    has_scoreboard     = 1;
    bit                    enable_axi_mon     = 1;
    bit                    enable_apb_mons    = 1;

    function new(string name = "bridge_env_cfg");
      super.new(name);
    endfunction
  endclass

  //---------------------------------------------------------------------------
  // Burst / SIMPLE illegal-transaction predicts (mirror axi4 RTL)
  //---------------------------------------------------------------------------
  function automatic logic [2:0] bridge_expected_axsize(int unsigned dw);
    unique case (dw)
      1024:    return 3'b111;
      512:     return 3'b110;
      256:     return 3'b101;
      128:     return 3'b100;
      64:      return 3'b011;
      32:      return 3'b010;
      16:      return 3'b001;
      default: return 3'b000;
    endcase
  endfunction

  function automatic bit bridge_burst_crosses_apb_sel(
      logic [31:0] first_addr,
      logic [31:0] last_addr,
      int unsigned sel_bit);
    return first_addr[sel_bit] !== last_addr[sel_bit];
  endfunction

  function automatic bit bridge_aw_txn_decerr(
      bridge_decode_kind_e k,
      int unsigned          dw,
      int unsigned          sel_bit,
      logic [31:0]           addr,
      logic [          7:0] len,
      logic [          2:0] sz,
      logic [          1:0] burst);
    logic [31:0] max_off;
    logic [31:0] last_addr;
    max_off   = {24'b0, len} << sz;
    last_addr = addr + max_off;
    unique case (k)
      BRIDGE_DECODE_SIMPLE: begin
        return (len != 8'd0) || (sz != bridge_expected_axsize(dw));
      end
      BRIDGE_DECODE_BURST: begin
        return (sz != bridge_expected_axsize(dw)) || (burst > 2'b01) ||
            ((burst == 2'b01) && bridge_burst_crosses_apb_sel(addr, last_addr, sel_bit));
      end
      default: return 1;
    endcase
  endfunction

  function automatic bit bridge_ar_txn_decerr(
      bridge_decode_kind_e k,
      int unsigned          dw,
      int unsigned          sel_bit,
      logic [31:0]           addr,
      logic [          7:0] len,
      logic [          2:0] sz,
      logic [          1:0] burst);
    logic [31:0] max_off;
    logic [31:0] last_addr;
    max_off   = {24'b0, len} << sz;
    last_addr = addr + max_off;
    unique case (k)
      BRIDGE_DECODE_SIMPLE: begin
        return (len != 8'd0) || (sz != bridge_expected_axsize(dw));
      end
      BRIDGE_DECODE_BURST: begin
        return (sz != bridge_expected_axsize(dw)) || (burst > 2'b01) ||
            ((burst == 2'b01) && bridge_burst_crosses_apb_sel(addr, last_addr, sel_bit));
      end
      default: return 1;
    endcase
  endfunction

  //---------------------------------------------------------------------------
  // Transactions
  //---------------------------------------------------------------------------
  class bridge_axi_wr_tr extends uvm_sequence_item;
    `uvm_object_utils(bridge_axi_wr_tr)

    logic [63:0] addr;
    logic [ 7:0] awlen;
    logic [ 2:0] awsize;
    logic [ 1:0] awburst;
    logic [31:0] id;
    logic [ 1:0] bresp;
    logic [63:0] wdata[$];
    logic [ 7:0] wstrb[$];

    function new(string name = "bridge_axi_wr_tr");
      super.new(name);
    endfunction
  endclass

  class bridge_axi_rd_tr extends uvm_sequence_item;
    `uvm_object_utils(bridge_axi_rd_tr)

    logic [63:0] addr;
    logic [ 7:0] arlen;
    logic [ 2:0] arsize;
    logic [ 1:0] arburst;
    logic [31:0] id;
    logic [ 1:0] rresp;
    logic [63:0] rdata[$];

    function new(string name = "bridge_axi_rd_tr");
      super.new(name);
    endfunction
  endclass

  class bridge_apb_tr extends uvm_sequence_item;
    `uvm_object_utils(bridge_apb_tr)

    int          port;
    logic [63:0] paddr;
    bit          pwrite;
    logic [63:0] pwdata;
    logic [ 7:0] pstrb;
    logic [63:0] prdata;
    bit          pslverr;

    function new(string name = "bridge_apb_tr");
      super.new(name);
    endfunction

    function string convert2string();
      return $sformatf(
          "APB port=%0d %s addr=%016h wd=%016h rd=%016h err=%0b", port, (pwrite ? "W" : "R"),
          paddr, pwdata, prdata, pslverr);
    endfunction
  endclass

  function automatic logic [31:0] bridge_beat_addr(
      logic [31:0] start,
      int unsigned beat,
      logic [ 2:0] axsize,
      logic [ 1:0] axburst);
    logic [31:0] step;
    step = 32'(1 << axsize);
    if (axburst == 2'b00) return start;
    return start + beat * step;
  endfunction

  function automatic int unsigned port_decode(logic [31:0] addr, int unsigned sel_bit);
    return addr[sel_bit] ? 1 : 0;
  endfunction

  //---------------------------------------------------------------------------
  // AXI slave-side monitor (#(DATA_WIDTH)). TB drives AXI toward DUT.
  //---------------------------------------------------------------------------
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

  //---------------------------------------------------------------------------
  // APB passive UVC (#(DW, AW))
  //---------------------------------------------------------------------------
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

  //---------------------------------------------------------------------------
  // Scoreboard: expand AXI to expected APB beats, compare APB UVC observes
  //---------------------------------------------------------------------------
 `uvm_analysis_imp_decl(_axi_wr)
 `uvm_analysis_imp_decl(_axi_rd)
 `uvm_analysis_imp_decl(_apb0)
 `uvm_analysis_imp_decl(_apb1)

  class bridge_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(bridge_scoreboard)

    bridge_env_cfg                                                                   cfg;

    //-------------------------------------------------------------------------
    // Predict APB ordering from AXI; buffer observations when APB wins the race.
    // Dual shadow memory keyed by APB word index (mirror apb_dual_mem_*).
    //-------------------------------------------------------------------------
    bridge_apb_tr                                                                     pred_wr[2][$];
    bridge_apb_tr                                                                     pred_rd[2][$];
    bridge_apb_tr                                                                     buf_wr_obs[2][$];
    bridge_apb_tr                                                                     buf_rd_obs[2][$];
    logic [63:0]                                                                      slv_shadow[int unsigned];

    uvm_analysis_imp_axi_wr #(bridge_axi_wr_tr, bridge_scoreboard)                 axi_wr_imp;
    uvm_analysis_imp_axi_rd #(bridge_axi_rd_tr, bridge_scoreboard)                   axi_rd_imp;
    uvm_analysis_imp_apb0 #(bridge_apb_tr, bridge_scoreboard)                       apb0_imp;
    uvm_analysis_imp_apb1 #(bridge_apb_tr, bridge_scoreboard)                       apb1_imp;

    int unsigned axi_wr_seen, axi_rd_seen, apb_seen[2], mismatch;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      axi_wr_imp = new("axi_wr_imp", this);
      axi_rd_imp = new("axi_rd_imp", this);
      apb0_imp   = new("apb0_imp", this);
      apb1_imp   = new("apb1_imp", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(bridge_env_cfg)::get(this, "", "cfg", cfg))
        cfg = bridge_env_cfg::type_id::create("sb_cfg");
    endfunction

    function int unsigned ram_key_of(int unsigned port_ix, logic [31:0] aa);
      int unsigned wd_ix;
      wd_ix = aa[cfg.apb_mem_addr_msb : cfg.apb_mem_addr_lsb];
      return (port_ix << 20) | wd_ix;
    endfunction

    function logic [63:0] trunc_dw(logic [63:0] d);
      case (cfg.data_width)
        32:       return {{32{1'b0}}, d[31:0]};
        default: return d;
      endcase
    endfunction

    function logic [63:0] shadow_peek_rd(int unsigned port_ix, logic [31:0] aa);
      int unsigned k;
      k = ram_key_of(port_ix, aa);
      return slv_shadow.exists(k) ? trunc_dw(slv_shadow[k]) : trunc_dw(64'h0);
    endfunction

    function void shadow_commit_wr(int unsigned port_ix, logic [31:0] aa, logic [63:0] pw);
      slv_shadow[ram_key_of(port_ix, aa)] = trunc_dw(pw);
    endfunction

    function logic [7:0] pb_mask_rd(int unsigned dwbits);
      unique case (dwbits)
        32: return 8'h0F;
        64: return 8'hFF;
        default: return 8'hFF;
      endcase
    endfunction

    function automatic bit byte_match(logic [63:0] we, logic [7:0] spe, logic [63:0] wo, logic [7:0] spo,
                                       int                                                       dw);
      int nb;
      int i;
      nb = dw / 8;
      for (i = 0; i < nb; i++) begin
        if (spe[i] && spo[i] && (we[8*i+:8] !== wo[8*i+:8])) return 0;
      end
      return 1;
    endfunction

    //-------------------------------------------------------------------------
    function void reconcile_wr_port(int unsigned p);
      while (pred_wr[p].size() > 0 && buf_wr_obs[p].size() > 0) begin
        one_wr_hit(p);
      end
    endfunction

    function void reconcile_rd_port(int unsigned p);
      while (pred_rd[p].size() > 0 && buf_rd_obs[p].size() > 0) begin
        one_rd_hit(p);
      end
    endfunction

    function void reconcile_wr_ports;
      reconcile_wr_port(0);
      reconcile_wr_port(1);
    endfunction

    function void reconcile_rd_ports;
      reconcile_rd_port(0);
      reconcile_rd_port(1);
    endfunction

    function void one_wr_hit(int unsigned p);
      bridge_apb_tr pred;
      bridge_apb_tr obs;
      pred = pred_wr[p].pop_front();
      obs  = buf_wr_obs[p].pop_front();
      if (pred.port !== obs.port || pred.port !== int'(p) || obs.pwrite !== 1'b1) begin
        `uvm_error(get_name(), $sformatf("WR meta p%u pred.port=%0d obs.port=%0d PW=%b (%s)", p, pred.port,
                                         obs.port, obs.pwrite, obs.convert2string()))
        mismatch++;
      end
      if (pred.paddr[31:0] !== obs.paddr[31:0]) begin
        `uvm_error(get_name(),
                   $sformatf("WR ADDR p%u exp=%08h obs=%08h (%s)", p, pred.paddr[31:0], obs.paddr[31:0],
                             obs.convert2string()))
        mismatch++;
      end
      if (!byte_match(pred.pwdata, pred.pstrb, obs.pwdata, obs.pstrb, cfg.data_width)) begin
        `uvm_error(get_name(),
                   $sformatf("WR WDATA p%u exp=%016h wb=%02h obs=%016h wb=%02h", p, pred.pwdata, pred.pstrb,
                             obs.pwdata, obs.pstrb))
        mismatch++;
      end
      // Mirrored APB slaves latch full PWDATA on successful completions.
      if (!obs.pslverr)
        shadow_commit_wr(obs.port, obs.paddr[31:0], obs.pwdata);
    endfunction

    function void one_rd_hit(int unsigned p);
      bridge_apb_tr pred;
      bridge_apb_tr obs;
      pred = pred_rd[p].pop_front();
      obs  = buf_rd_obs[p].pop_front();
      if (pred.port !== obs.port || pred.port !== int'(p) || obs.pwrite !== 1'b0) begin
        `uvm_error(get_name(), $sformatf("RD meta p%u pred.port=%0d obs.port=%0d PW=%b (%s)", p, pred.port,
                                         obs.port, obs.pwrite, obs.convert2string()))
        mismatch++;
      end
      if (pred.paddr[31:0] !== obs.paddr[31:0]) begin
        `uvm_error(get_name(),
                   $sformatf("RD ADDR p%u exp=%08h obs=%08h %s", p, pred.paddr[31:0], obs.paddr[31:0],
                             obs.convert2string()))
        mismatch++;
      end
      if (!obs.pslverr && trunc_dw(pred.prdata) !== trunc_dw(obs.prdata)) begin
        `uvm_error(get_name(),
                   $sformatf("RD PRDATA p%u exp(shadow)=%016h obs(APB)=%016h %s", p, pred.prdata, obs.prdata,
                             obs.convert2string()))
        mismatch++;
      end
    endfunction

    //-------------------------------------------------------------------------
    function void ingest_apb(int unsigned phy_port, bridge_apb_tr obs);
      if (!cfg.has_scoreboard) return;
      apb_seen[phy_port]++;
      if (obs.pwrite) begin
        buf_wr_obs[phy_port].push_back(obs);
        reconcile_wr_port(phy_port);
      end else begin
        buf_rd_obs[phy_port].push_back(obs);
        reconcile_rd_port(phy_port);
      end
    endfunction

    function void write_apb0(bridge_apb_tr obs);
      ingest_apb(0, obs);
    endfunction

    function void write_apb1(bridge_apb_tr obs);
      ingest_apb(1, obs);
    endfunction

    //-------------------------------------------------------------------------
    function void write_axi_wr(bridge_axi_wr_tr t);
      int b;
      logic [31:0] aa;
      int pidx;
      bridge_apb_tr pred;
      bit txn_illegal;
      if (!cfg.has_scoreboard) return;
      axi_wr_seen++;
      txn_illegal =
          bridge_aw_txn_decerr(cfg.decode_kind, cfg.data_width, cfg.apb_sel_bit, t.addr[31:0], t.awlen,
                               t.awsize, t.awburst);
      if (txn_illegal && t.bresp !== 2'b11) begin
        `uvm_error(get_name(), $sformatf("Illegal AW burst but BRESP not DECERR (%b)", t.bresp))
        mismatch++;
      end else if (!txn_illegal && t.bresp === 2'b11) begin
        `uvm_error(get_name(), $sformatf("Legal-looking AW txn got DECERR at BRESP"))
        mismatch++;
      end
      if (txn_illegal) return;

      if (int'(t.awlen + 1) !== t.wdata.size() || t.wdata.size() != t.wstrb.size()) begin
        `uvm_error(get_name(), $sformatf("AW len vs W beats mismatch awlen=%0d wbeats=%0d/strb%d", t.awlen,
                                         t.wdata.size(), t.wstrb.size()))
        mismatch++;
        return;
      end

      for (b = 0; b <= t.awlen; b++) begin
        aa   = bridge_beat_addr(t.addr[31:0], b, t.awsize, t.awburst);
        pidx = port_decode(aa, cfg.apb_sel_bit);
        pred = bridge_apb_tr::type_id::create($sformatf("exp_apb_wr_%0d", b));
        pred.port    = pidx;
        pred.paddr   = {32'b0, aa};
        pred.pwrite  = 1'b1;
        pred.pwdata  = t.wdata[b];
        pred.pstrb   = t.wstrb[b];
        pred.pslverr = 1'b0;
        pred_wr[pidx].push_back(pred);
      end

      reconcile_wr_ports();
    endfunction

    //-------------------------------------------------------------------------
    function void write_axi_rd(bridge_axi_rd_tr t);
      int                                                               b;
      logic [                                                             31:0] aa;
      int                                                                   pidx;
      bridge_apb_tr                                                         pred;
      bit                                                                   txn_illegal;
      logic [                                                              63:0] wd_sh;
      if (!cfg.has_scoreboard) return;
      axi_rd_seen++;
      txn_illegal =
          bridge_ar_txn_decerr(cfg.decode_kind, cfg.data_width, cfg.apb_sel_bit, t.addr[31:0], t.arlen,
                               t.arsize, t.arburst);
      if (txn_illegal && t.rresp !== 2'b11) begin
        `uvm_error(get_name(), $sformatf("Illegal AR burst but RRESP not DECERR (%b)", t.rresp))
        mismatch++;
      end else if (!txn_illegal && t.rresp === 2'b11) begin
        `uvm_error(get_name(), $sformatf("Legal-looking AR txn got DECERR on RRESP"))
        mismatch++;
      end

      if (txn_illegal) begin
        for (b = 0; b <= t.arlen; b++) begin
          wd_sh = t.rdata.size() > b ? trunc_dw(t.rdata[b]) : trunc_dw(64'hdeadbeefdeadbeef);
          if (wd_sh !== 64'h0) begin
            `uvm_error(get_name(), $sformatf("DECERR read beat %0d: expected zero RDATA, got %016h", b, wd_sh))
            mismatch++;
          end
        end
        return;
      end

      if (int'(t.arlen + 1) !== t.rdata.size()) begin
        `uvm_error(get_name(), $sformatf("AR len vs R beats mismatch arlen=%0d rbeats=%0d", t.arlen,
                                         t.rdata.size()))
        mismatch++;
        return;
      end

      for (b = 0; b <= t.arlen; b++) begin
        aa   = bridge_beat_addr(t.addr[31:0], b, t.arsize, t.arburst);
        pidx = port_decode(aa, cfg.apb_sel_bit);
        wd_sh             = shadow_peek_rd(pidx, aa);
        if (trunc_dw(t.rdata[b]) !== wd_sh) begin
          `uvm_error(get_name(),
                     $sformatf("RD AXI_rdata beat %0d addr=%08h mismatches shadow predictor %016h vs %016h", b,
                               aa, wd_sh, trunc_dw(t.rdata[b])))
          mismatch++;
        end
        pred              = bridge_apb_tr::type_id::create($sformatf("exp_apb_rd_%0d", b));
        pred.port         = pidx;
        pred.paddr        = {32'b0, aa};
        pred.pwrite       = 1'b0;
        pred.pstrb        = pb_mask_rd(cfg.data_width);
        pred.prdata       = wd_sh;
        pred.pslverr      = 1'b0;
        pred_rd[pidx].push_back(pred);
      end

      reconcile_rd_ports();
    endfunction

    function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      if (!cfg.has_scoreboard)
        return;
      `uvm_info(get_name(),
                $sformatf(
             "SB summary: axi_wr=%0d axi_rd=%0d apb0=%0d apb1=%0d mism=%0d | pred_wr rem p0=%0d p1=%0d pred_rd rem p0=%0d "
                    "p1=%0d | buf_wr p0=%0d p1=%0d buf_rd p0=%0d p1=%0d",
                    axi_wr_seen, axi_rd_seen, apb_seen[0], apb_seen[1], mismatch,
                    pred_wr[0].size(), pred_wr[1].size(), pred_rd[0].size(), pred_rd[1].size(),
                    buf_wr_obs[0].size(), buf_wr_obs[1].size(),
                    buf_rd_obs[0].size(), buf_rd_obs[1].size()), UVM_MEDIUM)
      if (pred_wr[0].size() !== 0 || pred_wr[1].size() !== 0 ||
          buf_wr_obs[0].size() !== 0 || buf_wr_obs[1].size() !== 0) begin
        `uvm_error(get_name(),
                   "Outstanding WR-related APB scoreboard queues (ordering / missing beats / DECERR skew)")
        mismatch++;
      end
      if (pred_rd[0].size() !== 0 || pred_rd[1].size() !== 0 ||
          buf_rd_obs[0].size() !== 0 || buf_rd_obs[1].size() !== 0) begin
        `uvm_error(get_name(),
                   "Outstanding RD-related APB scoreboard queues (ordering / missing beats / DECERR skew)")
        mismatch++;
      end
      if (mismatch !== 0)
        `uvm_error(get_name(), "Scoreboard saw mismatches")
    endfunction
  endclass

  //---------------------------------------------------------------------------
  // Top-level verification environment (#(DW) / 64 or 32)
  //---------------------------------------------------------------------------
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

endpackage

`endif
