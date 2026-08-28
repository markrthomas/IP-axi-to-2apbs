`ifndef REGBLOCK_UVM_ENV_PKG_SV
`define REGBLOCK_UVM_ENV_PKG_SV

package regblock_uvm_env_pkg;
  import uvm_pkg::*;
`include "uvm_macros.svh"
  import regblock_stimulus_pkg::*;

  // -------------------------------------------------------------------------
  // Sequence item
  // -------------------------------------------------------------------------
  typedef enum logic { RB_READ, RB_WRITE } rb_kind_e;

  class axi3lite_seq_item extends uvm_sequence_item;
    `uvm_object_utils(axi3lite_seq_item)

    rand rb_kind_e        kind;
    rand logic [31:0]     addr;
    rand logic [31:0]     data;
    rand logic [ 3:0]     strb;
    rand logic [ 3:0]     awid;
    rand logic [ 3:0]     wid;   // normally == awid; may differ for mismatch tests
         logic [ 1:0]     resp;

    constraint c_wid_match { wid == awid; }
    constraint c_strb_full { strb == 4'hF; }
    constraint c_in_range  { addr[31:7] == '0; }

    function new(string name = "axi3lite_seq_item");
      super.new(name);
    endfunction

    function string convert2string();
      return $sformatf("%s addr=0x%08h data=0x%08h strb=%0b awid=%0d wid=%0d resp=%0b",
                       kind.name(), addr, data, strb, awid, wid, resp);
    endfunction
  endclass

  // -------------------------------------------------------------------------
  // Sequencer
  // -------------------------------------------------------------------------
  class axi3lite_sequencer extends uvm_sequencer #(axi3lite_seq_item);
    `uvm_component_utils(axi3lite_sequencer)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

  // -------------------------------------------------------------------------
  // Driver
  // -------------------------------------------------------------------------
  class axi3lite_driver extends uvm_driver #(axi3lite_seq_item);
    `uvm_component_utils(axi3lite_driver)

    v_axi3lite_if_t vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(v_axi3lite_if_t)::get(this, "", "vif", vif))
        `uvm_fatal(get_type_name(), "axi3lite driver: vif not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
      axi3lite_seq_item item;
      // Initialise bus to idle
      vif.S_AXI_AWVALID = 0; vif.S_AXI_WVALID = 0; vif.S_AXI_BREADY = 0;
      vif.S_AXI_ARVALID = 0; vif.S_AXI_RREADY = 0;
      @(posedge vif.rst_n);
      @(posedge vif.clk);
      forever begin
        seq_item_port.get_next_item(item);
        if (item.kind == RB_WRITE)
          drive_write(item);
        else
          drive_read(item);
        seq_item_port.item_done();
      end
    endtask

    task drive_write(axi3lite_seq_item item);
      @(posedge vif.clk);
      vif.S_AXI_AWID    <= item.awid;
      vif.S_AXI_AWADDR  <= item.addr;
      vif.S_AXI_AWPROT  <= 3'd0;
      vif.S_AXI_AWVALID <= 1'b1;
      vif.S_AXI_WID     <= item.wid;
      vif.S_AXI_WDATA   <= item.data;
      vif.S_AXI_WSTRB   <= item.strb;
      vif.S_AXI_WVALID  <= 1'b1;
      vif.S_AXI_BREADY  <= 1'b1;

      // AW handshake
      repeat (64) begin
        @(posedge vif.clk);
        if (vif.S_AXI_AWREADY) begin
          vif.S_AXI_AWVALID <= 1'b0;
          break;
        end
      end
      // W handshake
      repeat (64) begin
        @(posedge vif.clk);
        if (vif.S_AXI_WREADY) begin
          vif.S_AXI_WVALID <= 1'b0;
          break;
        end
      end
      // B response
      repeat (64) begin
        @(posedge vif.clk);
        if (vif.S_AXI_BVALID) begin
          item.resp         = vif.S_AXI_BRESP;
          vif.S_AXI_BREADY <= 1'b0;
          break;
        end
      end
    endtask

    task drive_read(axi3lite_seq_item item);
      @(posedge vif.clk);
      vif.S_AXI_ARID    <= item.awid;
      vif.S_AXI_ARADDR  <= item.addr;
      vif.S_AXI_ARPROT  <= 3'd0;
      vif.S_AXI_ARVALID <= 1'b1;
      vif.S_AXI_RREADY  <= 1'b1;

      // AR handshake
      repeat (64) begin
        @(posedge vif.clk);
        if (vif.S_AXI_ARREADY) begin
          vif.S_AXI_ARVALID <= 1'b0;
          break;
        end
      end
      // R response
      repeat (64) begin
        @(posedge vif.clk);
        if (vif.S_AXI_RVALID) begin
          item.data         = vif.S_AXI_RDATA;
          item.resp         = vif.S_AXI_RRESP;
          vif.S_AXI_RREADY <= 1'b0;
          break;
        end
      end
    endtask

  endclass

  // -------------------------------------------------------------------------
  // Monitor — observes completed transactions, broadcasts to analysis port
  // -------------------------------------------------------------------------
  class axi3lite_monitor extends uvm_monitor;
    `uvm_component_utils(axi3lite_monitor)

    uvm_analysis_port #(axi3lite_seq_item) ap;
    v_axi3lite_if_t vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap = new("ap", this);
      if (!uvm_config_db #(v_axi3lite_if_t)::get(this, "", "vif", vif))
        `uvm_fatal(get_type_name(), "axi3lite monitor: vif not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
      @(posedge vif.rst_n);
      forever begin
        fork
          observe_write();
          observe_read();
        join_any
        disable fork;
      end
    endtask

    task observe_write();
      axi3lite_seq_item item;
      logic [3:0]  aw_id;
      logic [31:0] aw_addr;
      logic [3:0]  w_id;
      logic [31:0] w_data;
      logic [3:0]  w_strb;

      // Wait for AW handshake
      forever begin
        @(posedge vif.clk);
        if (vif.S_AXI_AWVALID && vif.S_AXI_AWREADY) begin
          aw_id   = vif.S_AXI_AWID;
          aw_addr = vif.S_AXI_AWADDR;
          break;
        end
      end
      // Wait for W handshake
      forever begin
        @(posedge vif.clk);
        if (vif.S_AXI_WVALID && vif.S_AXI_WREADY) begin
          w_id   = vif.S_AXI_WID;
          w_data = vif.S_AXI_WDATA;
          w_strb = vif.S_AXI_WSTRB;
          break;
        end
      end
      // Wait for B handshake
      forever begin
        @(posedge vif.clk);
        if (vif.S_AXI_BVALID && vif.S_AXI_BREADY) begin
          item      = axi3lite_seq_item::type_id::create("mon_wr");
          item.kind = RB_WRITE;
          item.awid = aw_id;
          item.wid  = w_id;
          item.addr = aw_addr;
          item.data = w_data;
          item.strb = w_strb;
          item.resp = vif.S_AXI_BRESP;
          ap.write(item);
          break;
        end
      end
    endtask

    task observe_read();
      axi3lite_seq_item item;
      logic [3:0]  ar_id;
      logic [31:0] ar_addr;

      // Wait for AR handshake
      forever begin
        @(posedge vif.clk);
        if (vif.S_AXI_ARVALID && vif.S_AXI_ARREADY) begin
          ar_id   = vif.S_AXI_ARID;
          ar_addr = vif.S_AXI_ARADDR;
          break;
        end
      end
      // Wait for R handshake
      forever begin
        @(posedge vif.clk);
        if (vif.S_AXI_RVALID && vif.S_AXI_RREADY) begin
          item      = axi3lite_seq_item::type_id::create("mon_rd");
          item.kind = RB_READ;
          item.awid = ar_id;
          item.wid  = ar_id;
          item.addr = ar_addr;
          item.data = vif.S_AXI_RDATA;
          item.resp = vif.S_AXI_RRESP;
          ap.write(item);
          break;
        end
      end
    endtask

  endclass

  // -------------------------------------------------------------------------
  // Agent
  // -------------------------------------------------------------------------
  class axi3lite_agent extends uvm_agent;
    `uvm_component_utils(axi3lite_agent)

    axi3lite_sequencer  seqr;
    axi3lite_driver     drv;
    axi3lite_monitor    mon;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      mon  = axi3lite_monitor::type_id::create("mon", this);
      if (get_is_active() == UVM_ACTIVE) begin
        seqr = axi3lite_sequencer::type_id::create("seqr", this);
        drv  = axi3lite_driver::type_id::create("drv", this);
      end
    endfunction

    function void connect_phase(uvm_phase phase);
      if (get_is_active() == UVM_ACTIVE)
        drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction

  endclass

  // -------------------------------------------------------------------------
  // RAL model — 32 RW registers at offsets 0x00–0x7C
  // -------------------------------------------------------------------------
  class regblock_rw_reg extends uvm_reg;
    `uvm_object_utils(regblock_rw_reg)
    rand uvm_reg_field value;

    function new(string name = "regblock_rw_reg");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    function void build();
      value = uvm_reg_field::type_id::create("value");
      value.configure(this, 32, 0, "RW", 0, 32'h0, 1, 1, 1);
    endfunction
  endclass

  class regblock_ral_model extends uvm_reg_block;
    `uvm_object_utils(regblock_ral_model)

    rand regblock_rw_reg regs[32];

    function new(string name = "regblock_ral_model");
      super.new(name, UVM_NO_COVERAGE);
    endfunction

    function void build();
      uvm_reg_map default_map;
      default_map = create_map("default_map", 0, 4, UVM_LITTLE_ENDIAN, 1);
      for (int i = 0; i < 32; i++) begin
        string rname;
        rname = $sformatf("reg%0d", i);
        regs[i] = regblock_rw_reg::type_id::create(rname);
        regs[i].build();
        regs[i].configure(this);
        default_map.add_reg(regs[i], i * 4, "RW");
      end
      lock_model();
    endfunction
  endclass

  // -------------------------------------------------------------------------
  // RAL adapter: translates RAL rw → seq_item and back
  // -------------------------------------------------------------------------
  class regblock_axi3lite_adapter extends uvm_reg_adapter;
    `uvm_object_utils(regblock_axi3lite_adapter)

    function new(string name = "regblock_axi3lite_adapter");
      super.new(name);
      provides_responses = 1;
    endfunction

    function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
      axi3lite_seq_item item = axi3lite_seq_item::type_id::create("reg2bus");
      item.addr = rw.addr;
      item.strb = 4'hF;
      item.awid = 4'd0;
      item.wid  = 4'd0;
      if (rw.kind == UVM_READ) begin
        item.kind = RB_READ;
        item.data = '0;
      end else begin
        item.kind = RB_WRITE;
        item.data = rw.data[31:0];
      end
      return item;
    endfunction

    function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
      axi3lite_seq_item item;
      if (!$cast(item, bus_item))
        `uvm_fatal("CAST", "bus2reg: cannot cast to axi3lite_seq_item")
      rw.addr   = item.addr;
      rw.data   = item.data;
      rw.byte_en = 4'hF;
      rw.status = (item.resp == 2'b00) ? UVM_IS_OK : UVM_NOT_OK;
      rw.kind   = (item.kind == RB_READ) ? UVM_READ : UVM_WRITE;
    endfunction
  endclass

  // -------------------------------------------------------------------------
  // Environment config
  // -------------------------------------------------------------------------
  class regblock_env_cfg extends uvm_object;
    `uvm_object_utils(regblock_env_cfg)
    bit has_scoreboard = 1;
    bit has_coverage   = 1;
    logic [31:0] reg_base_addr = 32'h0;

    function new(string name = "regblock_env_cfg");
      super.new(name);
    endfunction
  endclass

  // -------------------------------------------------------------------------
  // Scoreboard — shadow memory; checks read-back against written values
  // -------------------------------------------------------------------------
  class regblock_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(regblock_scoreboard)

    uvm_analysis_imp #(axi3lite_seq_item, regblock_scoreboard) mon_export;

    // 32-entry shadow; initialised to 0 at reset
    logic [31:0] shadow [0:31];
    logic [31:0] shadow_valid;  // bitmask of initialised entries

    int unsigned errors = 0;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      mon_export  = new("mon_export", this);
      shadow_valid = '0;
    endfunction

    function void write(axi3lite_seq_item item);
      logic [4:0] idx;
      if (item.addr[31:7] != '0) return;  // out-of-range: SLVERR, nothing to track
      if (item.awid != item.wid  && item.kind == RB_WRITE) return; // WID mismatch: SLVERR
      idx = item.addr[6:2];

      if (item.kind == RB_WRITE && item.resp == 2'b00) begin
        // Update shadow with byte-lane masking
        for (int b = 0; b < 4; b++) begin
          if (item.strb[b])
            shadow[idx][b*8 +: 8] = item.data[b*8 +: 8];
        end
        shadow_valid[idx] = 1'b1;
      end else if (item.kind == RB_READ && item.resp == 2'b00) begin
        if (shadow_valid[idx]) begin
          if (item.data !== shadow[idx]) begin
            `uvm_error("SCOREBOARD",
              $sformatf("READ MISMATCH reg[%0d] addr=0x%08h got=0x%08h exp=0x%08h",
                        idx, item.addr, item.data, shadow[idx]))
            errors++;
          end
        end
      end
    endfunction

    function void report_phase(uvm_phase phase);
      if (errors == 0)
        `uvm_info(get_type_name(), "Scoreboard PASSED — no mismatches", UVM_LOW)
      else
        `uvm_error(get_type_name(),
          $sformatf("Scoreboard FAILED — %0d mismatch(es)", errors))
    endfunction

  endclass

  // -------------------------------------------------------------------------
  // Coverage collector
  // -------------------------------------------------------------------------
`ifndef VERILATOR
  // Covergroups are not supported by the open-source Verilator UVM flow;
  // excluded under Verilator (see regblock_env below).  VCS/Xcelium build it.
  class regblock_cov_collector extends uvm_subscriber #(axi3lite_seq_item);
    `uvm_component_utils(regblock_cov_collector)

    axi3lite_seq_item item_q;

    covergroup cg_write;
      cp_addr: coverpoint item_q.addr[6:2] { bins regs[] = {[0:31]}; }
      cp_strb: coverpoint item_q.strb      { bins full = {4'hF}; bins partial = {[1:14]}; }
    endgroup

    covergroup cg_read;
      cp_addr: coverpoint item_q.addr[6:2] { bins regs[] = {[0:31]}; }
    endgroup

    covergroup cg_resp;
      cp_bresp: coverpoint item_q.resp { bins okay = {2'b00}; bins slverr = {2'b10}; }
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      cg_write = new();
      cg_read  = new();
      cg_resp  = new();
    endfunction

    function void write(axi3lite_seq_item t);
      item_q = t;
      cg_resp.sample();
      if (t.kind == RB_WRITE) cg_write.sample();
      else                    cg_read.sample();
    endfunction

  endclass
`endif

  // -------------------------------------------------------------------------
  // Environment
  // -------------------------------------------------------------------------
  class regblock_env extends uvm_env;
    `uvm_component_utils(regblock_env)

    axi3lite_agent                         agent;
    regblock_ral_model                     model;
    regblock_axi3lite_adapter              adapter;
    uvm_reg_predictor #(axi3lite_seq_item) predictor;
    regblock_scoreboard                    scoreboard;
`ifndef VERILATOR
    regblock_cov_collector                 cov;
`endif
    regblock_env_cfg                       cfg;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      if (!uvm_config_db #(regblock_env_cfg)::get(this, "", "cfg", cfg)) begin
        cfg = regblock_env_cfg::type_id::create("cfg");
      end

      agent     = axi3lite_agent::type_id::create("agent", this);
      model     = regblock_ral_model::type_id::create("model");
      model.build();
      adapter   = regblock_axi3lite_adapter::type_id::create("adapter");
      predictor = uvm_reg_predictor #(axi3lite_seq_item)::type_id::create("predictor", this);

      if (cfg.has_scoreboard)
        scoreboard = regblock_scoreboard::type_id::create("scoreboard", this);
`ifndef VERILATOR
      if (cfg.has_coverage)
        cov = regblock_cov_collector::type_id::create("cov", this);
`endif
    endfunction

    function void connect_phase(uvm_phase phase);
      uvm_reg_map rmap = model.get_default_map();

      // Wire RAL map to sequencer via adapter
      rmap.set_sequencer(agent.seqr, adapter);

      // Predictor: observe monitor output → update RAL shadow
      predictor.map     = rmap;
      predictor.adapter = adapter;
      agent.mon.ap.connect(predictor.bus_in);

      if (cfg.has_scoreboard)
        agent.mon.ap.connect(scoreboard.mon_export);
`ifndef VERILATOR
      if (cfg.has_coverage)
        agent.mon.ap.connect(cov.analysis_export);
`endif
    endfunction

  endclass

endpackage

`endif
