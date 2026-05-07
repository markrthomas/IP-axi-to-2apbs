`ifndef BRIDGE_SCOREBOARD_SV
`define BRIDGE_SCOREBOARD_SV

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
        bridge_uvm_env_pkg::bridge_aw_txn_decerr(cfg.decode_kind, cfg.data_width, cfg.apb_sel_bit, t.addr[31:0], t.awlen,
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
      aa   = bridge_uvm_env_pkg::bridge_beat_addr(t.addr[31:0], b, t.awsize, t.awburst);
      pidx = bridge_uvm_env_pkg::port_decode(aa, cfg.apb_sel_bit);
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
        bridge_uvm_env_pkg::bridge_ar_txn_decerr(cfg.decode_kind, cfg.data_width, cfg.apb_sel_bit, t.addr[31:0], t.arlen,
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
        wd_sh = t.rdata.size() > b ? bridge_uvm_env_pkg::trunc_64(t.rdata[b]) : bridge_uvm_env_pkg::trunc_64(64'hdeadbeefdeadbeef);
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
      aa   = bridge_uvm_env_pkg::bridge_beat_addr(t.addr[31:0], b, t.arsize, t.arburst);
      pidx = bridge_uvm_env_pkg::port_decode(aa, cfg.apb_sel_bit);
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

`endif
