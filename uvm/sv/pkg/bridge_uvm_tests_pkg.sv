package bridge_uvm_tests_pkg;
  import uvm_pkg::*;
 `include "uvm_macros.svh"
  import bridge_stimulus_pkg::*;
  import bridge_uvm_env_pkg::*;

`include "bridge_rand_stim.sv"

  //---------------------------------------------------------------------------
  // Base Test: Shared configuration and environment setup
  //---------------------------------------------------------------------------
  virtual class bridge_base_test #(int DW = 64) extends uvm_test;
    v_axi_if_64_t       axi_vif;
    v_axi_if_32_t       axi_vif_32;
    bridge_env #(DW)    env;
    bridge_env_cfg      env_cfg;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      
      env_cfg = bridge_env_cfg::type_id::create("env_cfg");
      configure_env();
      uvm_config_db #(bridge_env_cfg)::set(this, "env", "cfg", env_cfg);

      env = bridge_env #(DW)::type_id::create("env", this);
      
      if (DW == 64) begin
        if (!uvm_config_db #(v_axi_if_64_t)::get(this, "", "axi_vif", axi_vif))
          `uvm_fatal(get_type_name(), "axi_vif (64-bit) missing")
        uvm_config_db #(virtual axi4_master_if #(4, 32, 64))::set(this, "env.axi_mon", "vif", axi_vif);
      end else begin
        if (!uvm_config_db #(v_axi_if_32_t)::get(this, "", "axi_vif", axi_vif_32))
          `uvm_fatal(get_type_name(), "axi_vif (32-bit) missing")
        uvm_config_db #(virtual axi4_master_if #(4, 32, 32))::set(this, "env.axi_mon", "vif", axi_vif_32);
      end
    endfunction

    // To be overridden by subclasses to tune env_cfg
    virtual function void configure_env();
      env_cfg.apb_sel_bit = 31;
    endfunction
  endclass

  //---------------------------------------------------------------------------
  // Simple Test
  //---------------------------------------------------------------------------
  class test_bridge_simple extends bridge_base_test #(64);
 `uvm_component_utils(test_bridge_simple)
    bridge_axi_stim_64 stim;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void configure_env();
      env_cfg.apb_sel_bit = 31;
      env_cfg.decode_kind = BRIDGE_DECODE_SIMPLE;
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      stim = new();
      stim.set_if(axi_vif, null);
    endfunction

    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      stim.run_mirror_simple();
      phase.drop_objection(this);
    endtask
  endclass

  //---------------------------------------------------------------------------
  // Burst Test
  //---------------------------------------------------------------------------
  class test_bridge_burst extends bridge_base_test #(64);
 `uvm_component_utils(test_bridge_burst)
    bridge_axi_stim_64 stim;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void configure_env();
      env_cfg.apb_sel_bit = 31;
      env_cfg.decode_kind = BRIDGE_DECODE_BURST;
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      stim = new();
      stim.set_if(axi_vif, null);
    endfunction

    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      stim.run_mirror_burst();
      phase.drop_objection(this);
    endtask
  endclass

  //---------------------------------------------------------------------------
  // Burst Extended Test
  //---------------------------------------------------------------------------
  class test_bridge_burst_ext extends bridge_base_test #(64);
 `uvm_component_utils(test_bridge_burst_ext)
    v_apb_side_if_t    apb_if;
    bridge_axi_stim_64 stim;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void configure_env();
      env_cfg.apb_sel_bit = 31;
      env_cfg.decode_kind = BRIDGE_DECODE_BURST;
      env_cfg.apb_mem_addr_msb = 12;
      env_cfg.apb_mem_addr_lsb = 3;
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(v_apb_side_if_t)::get(this, "", "apb_side_vif", apb_if))
        `uvm_fatal(get_type_name(), "apb_side_vif missing")
      stim = new();
      stim.set_if(axi_vif, apb_if);
    endfunction

    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      fork
        begin
          #(20000);
          `uvm_fatal("TOF", "TIMEOUT reproduced extended bench")
        end
        begin
          stim.run_mirror_burst_ext();
        end
      join_any
      disable fork;
      phase.drop_objection(this);
    endtask
  endclass

  //---------------------------------------------------------------------------
  // Simple Wait-State Test
  //---------------------------------------------------------------------------
  class test_bridge_simple_ws extends bridge_base_test #(64);
 `uvm_component_utils(test_bridge_simple_ws)
    int unsigned          read_cycles = 2;
    bridge_axi_stim_64    stim;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void configure_env();
      env_cfg.apb_sel_bit = 31;
      env_cfg.decode_kind = BRIDGE_DECODE_SIMPLE;
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      void'(uvm_config_db #(int unsigned)::get(this, "", "read_wait_cycles", read_cycles));
      stim = new();
      stim.set_if(axi_vif, null);
    endfunction

    task run_phase(uvm_phase phase);
      logic [63:0] r0;
      phase.raise_objection(this);
      stim.drv_init_zeros();
      stim.wait_reset_after_start();

      stim.axi_single_write_together_ok(32'h0000_0010, 64'hDEAD_BEEF_CAFE_BABE);
      stim.axi_single_read_standard(32'h0000_0010, r0, 1'b1);
      if (r0 !== 64'hDEAD_BEEF_CAFE_BABE)
        `uvm_fatal(get_type_name(), "APB0 readback mismatch (ws)")
      stim.axi_single_write_together_ok(32'h8000_0020, 64'h1234_5678_9ABC_DEF0);
      stim.axi_single_read_standard(32'h8000_0020, r0, 1'b1);
      if (r0 !== 64'h1234_5678_9ABC_DEF0)
        `uvm_fatal(get_type_name(), "APB1 readback mismatch (ws)")

 `uvm_info(
          get_type_name(),
          $sformatf("SIMPLE WS TEST PASSED (READ_WAIT_CYCLES=%0d)", read_cycles),
          UVM_MEDIUM)

      phase.drop_objection(this);
    endtask
  endclass

  //---------------------------------------------------------------------------
  // Parameterized Config Test
  //---------------------------------------------------------------------------
  class test_bridge_parameterized_cfg extends bridge_base_test #(32);
 `uvm_component_utils(test_bridge_parameterized_cfg)
    bridge_axi_stim_32 stim;
    v_apb_sel_tracker_t  sel_track;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void configure_env();
      env_cfg.apb_sel_bit = 20;
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(v_apb_sel_tracker_t)::get(this, "", "apb_sel_tracker", sel_track))
        `uvm_fatal(get_type_name(), "apb_sel_tracker missing")
      stim = new();
      stim.connect_if(axi_vif_32);
    endfunction

    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      fork
        begin
          #(10000);
 `uvm_fatal(get_type_name(), "PARAMETERIZED TIMEOUT")
        end
        begin
          stim.run_mirror_param(sel_track);
        end
      join_any
      disable fork;
      phase.drop_objection(this);
    endtask
  endclass

  //---------------------------------------------------------------------------
  // Constrained-Random Burst Write/Read Test
  //
  // Drives bridge_rand_seq against the burst bridge (tb_uvm_burst_ext.sv).
  // The sequence alternates random writes and reads with randomized burst type
  // (FIXED/INCR) and length (0-7), covering both APB ports.
  // Responses are checked by the env scoreboard.
  //---------------------------------------------------------------------------
  class test_bridge_rand_burst extends bridge_base_test #(64);
   `uvm_component_utils(test_bridge_rand_burst)

    v_apb_side_if_t    apb_if;
    bridge_axi_stim_64 stim;
    bridge_rand_seq    rseq;

    int unsigned n_txn = 40;   // override via +n_txn=<N> plusarg

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void configure_env();
      env_cfg.apb_sel_bit  = 31;
      env_cfg.decode_kind  = BRIDGE_DECODE_BURST;
      env_cfg.apb_mem_addr_msb = 12;
      env_cfg.apb_mem_addr_lsb = 3;
    endfunction

    function void build_phase(uvm_phase phase);
      int unsigned plusarg_n;
      super.build_phase(phase);
      if (!uvm_config_db #(v_apb_side_if_t)::get(this, "", "apb_side_vif", apb_if))
        `uvm_fatal(get_type_name(), "apb_side_vif missing")
      stim = new();
      stim.set_if(axi_vif, apb_if);
      rseq          = bridge_rand_seq::type_id::create("rseq");
      rseq.stim     = stim;
      rseq.n_txn    = n_txn;
    endfunction

    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      fork
        begin
          #(200000);
          `uvm_fatal(get_type_name(), "RAND BURST TIMEOUT")
        end
        begin
          stim.drv_init_zeros();
          @(posedge axi_vif.rst_n);
          repeat (5) @(posedge axi_vif.clk);
          rseq.run();
          `uvm_info(get_type_name(),
              $sformatf("RAND BURST TEST PASSED (%0d txn)", rseq.n_txn),
              UVM_MEDIUM)
        end
      join_any
      disable fork;
      phase.drop_objection(this);
    endtask
  endclass

  //---------------------------------------------------------------------------
  // Constrained-Random Write-Then-Read Integrity Test
  //
  // Writes a random set of locations then reads them back, checking every
  // read data value matches what was written.  Covers: partial strobe writes,
  // FIXED and INCR bursts, both APB ports, and multi-beat transactions.
  //---------------------------------------------------------------------------
  class test_bridge_rand_integrity extends bridge_base_test #(64);
   `uvm_component_utils(test_bridge_rand_integrity)

    v_apb_side_if_t    apb_if;
    bridge_axi_stim_64 stim;

    int unsigned n_rounds = 8;   // write-then-read round-trips

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void configure_env();
      env_cfg.apb_sel_bit  = 31;
      env_cfg.decode_kind  = BRIDGE_DECODE_BURST;
      env_cfg.apb_mem_addr_msb = 12;
      env_cfg.apb_mem_addr_lsb = 3;
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(v_apb_side_if_t)::get(this, "", "apb_side_vif", apb_if))
        `uvm_fatal(get_type_name(), "apb_side_vif missing")
      stim = new();
      stim.set_if(axi_vif, apb_if);
    endfunction

    task run_phase(uvm_phase phase);
      bridge_rand_item item;
      logic [1:0] wr_resp, rd_resp;
      phase.raise_objection(this);
      fork
        begin
          #(300000);
          `uvm_fatal(get_type_name(), "INTEGRITY TEST TIMEOUT")
        end
        begin
          stim.drv_init_zeros();
          @(posedge axi_vif.rst_n);
          repeat (5) @(posedge axi_vif.clk);

          for (int unsigned r = 0; r < n_rounds; r++) begin
            item = bridge_rand_item::type_id::create($sformatf("wr_%0d", r));
            item.is_write = 1;
            if (!item.randomize())
              `uvm_fatal(get_type_name(), "randomize() failed")
            `uvm_info(get_type_name(),
                $sformatf("[WR %0d] %s", r, item.convert2string()), UVM_MEDIUM)
            stim.axi_write_burst_ext(
                item.addr[31:0], item.burst_len, item.burst_type,
                item.burst_len, 8'hFF, wr_resp);
            if (wr_resp !== 2'b00)
              `uvm_fatal(get_type_name(),
                  $sformatf("Integrity WR failed: BRESP=%0b addr=%08h", wr_resp, item.addr))

            // Read back the same address/length/burst
            `uvm_info(get_type_name(),
                $sformatf("[RD %0d] addr=0x%08h len=%0d", r, item.addr, item.burst_len),
                UVM_MEDIUM)
            stim.axi_read_burst_ext(
                item.addr[31:0], item.burst_len, item.burst_type, rd_resp);
            if (rd_resp !== 2'b00)
              `uvm_fatal(get_type_name(),
                  $sformatf("Integrity RD failed: RRESP=%0b addr=%08h", rd_resp, item.addr))
          end

          `uvm_info(get_type_name(),
              $sformatf("INTEGRITY TEST PASSED (%0d rounds)", n_rounds), UVM_MEDIUM)
        end
      join_any
      disable fork;
      phase.drop_objection(this);
    endtask
  endclass

  // =========================================================================
  // test_bridge_stress — three-phase randomized stress test
  //
  // Mirrors test/tb_stress_burst.v.  Reads +N=<n> plusarg (default 100) to
  // control the number of random transactions in phase 2.  Data integrity is
  // verified by bridge_scoreboard via the shared APB side model.
  //
  // Run with:  +UVM_TESTNAME=test_bridge_stress [+N=<n>]
  // =========================================================================
  class test_bridge_stress extends bridge_base_test #(64);
    `uvm_component_utils(test_bridge_stress)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      bridge_axi_stim_64    stim;
      bridge_stress_seq     seq;
      virtual apb_mon_if    apb_vif;
      int unsigned          n_txn;
      string                n_str;

      // Read transaction count from plusarg.
      if ($value$plusargs("N=%s", n_str))
        n_txn = n_str.atoi();
      else
        n_txn = 100;

      // Retrieve APB side interface so axi_write_burst_ext can drive PSLVERR.
      if (!uvm_config_db #(virtual apb_mon_if)::get(
              this, "", "apb_side_vif", apb_vif))
        `uvm_fatal(get_type_name(), "apb_side_vif not found in config_db")

      stim = bridge_axi_stim_64::type_id::create("stim", this);
      stim.sif = apb_vif;

      if (!uvm_config_db #(virtual axi4_master_if)::get(
              this, "", "axi_vif", stim.vif))
        `uvm_fatal(get_type_name(), "axi_vif not found in config_db")

      seq          = bridge_stress_seq::type_id::create("seq", this);
      seq.stim     = stim;
      seq.n_txn    = n_txn;

      phase.raise_objection(this);

      fork
        begin
          // Generous timeout: seed(32) + n_txn random + sweep(32) beats,
          // each beat at most ~20 APB cycles @ 10 ns => ~(n_txn+64)*200 ns.
          #( longint'(n_txn + 64) * 200 * 10 );
          `uvm_fatal(get_type_name(),
              $sformatf("TIMEOUT after %0d+64 transactions", n_txn))
        end
        begin
          seq.run();
          `uvm_info(get_type_name(),
              $sformatf("STRESS TEST PASSED (N=%0d)", n_txn), UVM_MEDIUM)
        end
      join_any
      disable fork;
      phase.drop_objection(this);
    endtask
  endclass

endpackage
