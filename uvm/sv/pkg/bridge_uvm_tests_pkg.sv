package bridge_uvm_tests_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import bridge_stimulus_pkg::*;

  class test_bridge_simple extends uvm_test;
    `uvm_component_utils(test_bridge_simple)
    v_axi_if_64_t axi_vif;
    bridge_axi_stim_64 stim;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(v_axi_if_64_t)::get(this, "", "axi_vif", axi_vif))
        `uvm_fatal(get_type_name(), "config_db axi_vif missing")
      stim = new();
      stim.set_if(axi_vif, null);
    endfunction

    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      stim.run_mirror_simple();
      phase.drop_objection(this);
    endtask
  endclass

  class test_bridge_burst extends uvm_test;
    `uvm_component_utils(test_bridge_burst)
    v_axi_if_64_t axi_vif;
    bridge_axi_stim_64 stim;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(v_axi_if_64_t)::get(this, "", "axi_vif", axi_vif))
        `uvm_fatal(get_type_name(), "axi_vif missing")
      stim = new();
      stim.set_if(axi_vif, null);
    endfunction

    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      stim.run_mirror_burst();
      phase.drop_objection(this);
    endtask
  endclass

  class test_bridge_burst_ext extends uvm_test;
    `uvm_component_utils(test_bridge_burst_ext)
    v_axi_if_64_t      axi_vif;
    v_apb_side_if_t    apb_if;
    bridge_axi_stim_64 stim;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(v_axi_if_64_t)::get(this, "", "axi_vif", axi_vif))
        `uvm_fatal(get_type_name(), "axi_vif missing")
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

  class test_bridge_simple_ws extends uvm_test;
    `uvm_component_utils(test_bridge_simple_ws)

    int unsigned           read_cycles = 2;
    v_axi_if_64_t axi_vif;
    bridge_axi_stim_64     stim;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(v_axi_if_64_t)::get(this, "", "axi_vif", axi_vif))
        `uvm_fatal(get_type_name(), "axi_vif missing")
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

  class test_bridge_parameterized_cfg extends uvm_test;
    `uvm_component_utils(test_bridge_parameterized_cfg)
    bridge_axi_stim_32 stim;
    v_axi_if_32_t        axi_vif;
    v_apb_sel_tracker_t  sel_track;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(v_axi_if_32_t)::get(this, "", "axi_vif", axi_vif))
        `uvm_fatal(get_type_name(), "axi_vif (32-bit) missing")
      if (!uvm_config_db #(v_apb_sel_tracker_t)::get(this, "", "apb_sel_tracker", sel_track))
        `uvm_fatal(get_type_name(), "apb_sel_tracker missing")

      stim = new();
      stim.connect_if(axi_vif);
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
