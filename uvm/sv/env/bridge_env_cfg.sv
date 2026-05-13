`ifndef BRIDGE_ENV_CFG_SV
`define BRIDGE_ENV_CFG_SV

typedef enum int {BRIDGE_DECODE_SIMPLE = 0, BRIDGE_DECODE_BURST = 1} bridge_decode_kind_e;

class bridge_env_cfg extends uvm_object;
  `uvm_object_utils(bridge_env_cfg)

  int unsigned           data_width         = 64;
  int unsigned           addr_width         = 32;
  int unsigned           apb_sel_bit        = 31;
  bridge_decode_kind_e   decode_kind        = BRIDGE_DECODE_BURST;
  int unsigned           apb_mem_addr_msb   = 9;
  int unsigned           apb_mem_addr_lsb   = 2;
  bit                    has_scoreboard     = 1;
  bit                    has_coverage       = 1;
  bit                    enable_axi_mon     = 1;
  bit                    enable_apb_mons    = 1;

  function new(string name = "bridge_env_cfg");
    super.new(name);
  endfunction
endclass

`endif
