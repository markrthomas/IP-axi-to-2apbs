`ifndef REGBLOCK_UVM_TESTS_PKG_SV
`define REGBLOCK_UVM_TESTS_PKG_SV

package regblock_uvm_tests_pkg;
  import uvm_pkg::*;
 `include "uvm_macros.svh"
  import regblock_stimulus_pkg::*;
  import regblock_uvm_env_pkg::*;

  // -------------------------------------------------------------------------
  // Base Test: environment setup shared by all regblock tests
  // -------------------------------------------------------------------------
  class regblock_base_test extends uvm_test;
    `uvm_component_utils(regblock_base_test)

    regblock_env      env;
    regblock_env_cfg  env_cfg;
    v_axi3lite_if_t   vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      env_cfg = regblock_env_cfg::type_id::create("env_cfg");
      configure_env(env_cfg);
      uvm_config_db #(regblock_env_cfg)::set(this, "env", "cfg", env_cfg);

      env = regblock_env::type_id::create("env", this);

      if (!uvm_config_db #(v_axi3lite_if_t)::get(this, "", "vif", vif))
        `uvm_fatal(get_type_name(), "vif not found in config_db")

      uvm_config_db #(v_axi3lite_if_t)::set(this, "env.agent.drv", "vif", vif);
      uvm_config_db #(v_axi3lite_if_t)::set(this, "env.agent.mon", "vif", vif);
    endfunction

    virtual function void configure_env(regblock_env_cfg cfg);
      cfg.has_scoreboard = 1;
      cfg.has_coverage   = 1;
    endfunction
  endclass

  // -------------------------------------------------------------------------
  // hw-reset test: verify all 32 registers read back 0x00000000 after reset
  // -------------------------------------------------------------------------
  class test_regblock_hw_reset extends regblock_base_test;
    `uvm_component_utils(test_regblock_hw_reset)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      uvm_reg_hw_reset_seq hw_reset_seq;
      phase.raise_objection(this);
      hw_reset_seq = uvm_reg_hw_reset_seq::type_id::create("hw_reset_seq");
      hw_reset_seq.model = env.model;
      hw_reset_seq.start(env.agent.seqr);
      `uvm_info(get_type_name(), "HW RESET TEST PASSED", UVM_LOW)
      phase.drop_objection(this);
    endtask
  endclass

  // -------------------------------------------------------------------------
  // bit-bash test: toggle every bit of every register 0→1→0
  // -------------------------------------------------------------------------
  class test_regblock_bit_bash extends regblock_base_test;
    `uvm_component_utils(test_regblock_bit_bash)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      uvm_reg_bit_bash_seq bit_bash_seq;
      phase.raise_objection(this);
      bit_bash_seq = uvm_reg_bit_bash_seq::type_id::create("bit_bash_seq");
      bit_bash_seq.model = env.model;
      bit_bash_seq.start(env.agent.seqr);
      `uvm_info(get_type_name(), "BIT BASH TEST PASSED", UVM_LOW)
      phase.drop_objection(this);
    endtask
  endclass

  // -------------------------------------------------------------------------
  // reg-access test: write and read-back every register with a walking pattern
  // -------------------------------------------------------------------------
  class test_regblock_reg_access extends regblock_base_test;
    `uvm_component_utils(test_regblock_reg_access)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      uvm_reg_access_seq reg_access_seq;
      phase.raise_objection(this);
      reg_access_seq = uvm_reg_access_seq::type_id::create("reg_access_seq");
      reg_access_seq.model = env.model;
      reg_access_seq.start(env.agent.seqr);
      `uvm_info(get_type_name(), "REG ACCESS TEST PASSED", UVM_LOW)
      phase.drop_objection(this);
    endtask
  endclass

  // -------------------------------------------------------------------------
  // Directed sequence: out-of-range write → SLVERR
  // -------------------------------------------------------------------------
  class regblock_oor_write_seq extends uvm_sequence #(axi3lite_seq_item);
    `uvm_object_utils(regblock_oor_write_seq)

    function new(string name = "regblock_oor_write_seq");
      super.new(name);
    endfunction

    task body();
      axi3lite_seq_item item;

      // Address 0x80: one beyond REG31 at 0x7C
      item = axi3lite_seq_item::type_id::create("oor_wr_0x80");
      start_item(item);
      item.kind = RB_WRITE;
      item.addr = 32'h0000_0080;
      item.data = 32'hDEAD_BEEF;
      item.strb = 4'hF;
      item.awid = 4'd0;
      item.wid  = 4'd0;
      finish_item(item);
      if (item.resp !== 2'b10)
        `uvm_error("OOR_WRITE", $sformatf("addr=0x80: expected SLVERR, got BRESP=%0b", item.resp))

      // High address
      item = axi3lite_seq_item::type_id::create("oor_wr_hi");
      start_item(item);
      item.kind = RB_WRITE;
      item.addr = 32'hFFFF_FF00;
      item.data = 32'hCAFE_BABE;
      item.strb = 4'hF;
      item.awid = 4'd1;
      item.wid  = 4'd1;
      finish_item(item);
      if (item.resp !== 2'b10)
        `uvm_error("OOR_WRITE", $sformatf("addr=0xFFFFFF00: expected SLVERR, got BRESP=%0b", item.resp))

      `uvm_info("OOR_WRITE", "Out-of-range write SLVERR checks PASSED", UVM_LOW)
    endtask
  endclass

  // -------------------------------------------------------------------------
  // Directed sequence: out-of-range read → SLVERR
  // -------------------------------------------------------------------------
  class regblock_oor_read_seq extends uvm_sequence #(axi3lite_seq_item);
    `uvm_object_utils(regblock_oor_read_seq)

    function new(string name = "regblock_oor_read_seq");
      super.new(name);
    endfunction

    task body();
      axi3lite_seq_item item;

      item = axi3lite_seq_item::type_id::create("oor_rd_0x80");
      start_item(item);
      item.kind = RB_READ;
      item.addr = 32'h0000_0080;
      item.awid = 4'd0;
      item.wid  = 4'd0;
      finish_item(item);
      if (item.resp !== 2'b10)
        `uvm_error("OOR_READ", $sformatf("addr=0x80: expected SLVERR, got RRESP=%0b", item.resp))

      item = axi3lite_seq_item::type_id::create("oor_rd_hi");
      start_item(item);
      item.kind = RB_READ;
      item.addr = 32'h1000_0000;
      item.awid = 4'd0;
      item.wid  = 4'd0;
      finish_item(item);
      if (item.resp !== 2'b10)
        `uvm_error("OOR_READ", $sformatf("addr=0x10000000: expected SLVERR, got RRESP=%0b", item.resp))

      `uvm_info("OOR_READ", "Out-of-range read SLVERR checks PASSED", UVM_LOW)
    endtask
  endclass

  // -------------------------------------------------------------------------
  // Directed sequence: WID ≠ AWID → SLVERR, register unchanged
  // -------------------------------------------------------------------------
  class regblock_wid_mismatch_seq extends uvm_sequence #(axi3lite_seq_item);
    `uvm_object_utils(regblock_wid_mismatch_seq)

    function new(string name = "regblock_wid_mismatch_seq");
      super.new(name);
    endfunction

    task body();
      axi3lite_seq_item item;
      logic [31:0] ref_data = 32'h1234_5678;

      // Prime REG1 with a known value
      item = axi3lite_seq_item::type_id::create("prime_reg1");
      start_item(item);
      item.kind = RB_WRITE;
      item.addr = 32'h0000_0004;
      item.data = ref_data;
      item.strb = 4'hF;
      item.awid = 4'd1;
      item.wid  = 4'd1;
      finish_item(item);
      if (item.resp !== 2'b00)
        `uvm_error("WID_MISMATCH", "Prime write did not return OKAY")

      // WID-mismatch write: AWID=5, WID=6
      item = axi3lite_seq_item::type_id::create("wid_mismatch");
      start_item(item);
      item.kind = RB_WRITE;
      item.addr = 32'h0000_0004;
      item.data = 32'hDEAD_BEEF;
      item.strb = 4'hF;
      item.awid = 4'd5;
      item.wid  = 4'd6;
      finish_item(item);
      if (item.resp !== 2'b10)
        `uvm_error("WID_MISMATCH",
          $sformatf("Expected SLVERR on WID mismatch, got BRESP=%0b", item.resp))

      // Read back: register must be unchanged
      item = axi3lite_seq_item::type_id::create("readback");
      start_item(item);
      item.kind = RB_READ;
      item.addr = 32'h0000_0004;
      item.awid = 4'd0;
      item.wid  = 4'd0;
      finish_item(item);
      if (item.resp !== 2'b00)
        `uvm_error("WID_MISMATCH", "Readback did not return OKAY")
      if (item.data !== ref_data)
        `uvm_error("WID_MISMATCH",
          $sformatf("Register modified by WID-mismatch write: got=0x%08h exp=0x%08h",
                    item.data, ref_data))

      `uvm_info("WID_MISMATCH", "WID-mismatch SLVERR checks PASSED", UVM_LOW)
    endtask
  endclass

  // -------------------------------------------------------------------------
  // Directed test: runs all error-path sequences in sequence
  // -------------------------------------------------------------------------
  class test_regblock_directed extends regblock_base_test;
    `uvm_component_utils(test_regblock_directed)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      regblock_oor_write_seq   oor_wr;
      regblock_oor_read_seq    oor_rd;
      regblock_wid_mismatch_seq wid_mm;

      phase.raise_objection(this);

      oor_wr = regblock_oor_write_seq::type_id::create("oor_wr");
      oor_rd = regblock_oor_read_seq::type_id::create("oor_rd");
      wid_mm = regblock_wid_mismatch_seq::type_id::create("wid_mm");

      oor_wr.start(env.agent.seqr);
      oor_rd.start(env.agent.seqr);
      wid_mm.start(env.agent.seqr);

      `uvm_info(get_type_name(), "DIRECTED TEST PASSED", UVM_LOW)
      phase.drop_objection(this);
    endtask
  endclass

endpackage

`endif
