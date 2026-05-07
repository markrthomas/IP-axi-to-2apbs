package bridge_uvm_tests_pkg;
  import uvm_pkg::*;
 `include "uvm_macros.svh"
  import bridge_stimulus_pkg::*;
  import bridge_uvm_env_pkg::*;

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

endpackage
