`ifndef BRIDGE_UVM_ENV_PKG_SV
`define BRIDGE_UVM_ENV_PKG_SV

package bridge_uvm_env_pkg;
  import uvm_pkg::*;
`include "uvm_macros.svh"
  import bridge_stimulus_pkg::*;

  // Helper functions for prediction
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

  // Simple truncation helper
  function automatic logic [63:0] trunc_64(logic [63:0] val);
    return val;
  endfunction

`include "../env/bridge_env_cfg.sv"
`include "../transactions/bridge_transactions.sv"

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

`include "bridge_axi_monitor.sv"
`include "bridge_apb_monitor.sv"
`include "bridge_scoreboard.sv"
`ifndef VERILATOR
// Coverage collector uses covergroups the open-source flow can't elaborate;
// excluded under Verilator (see bridge_env.sv).  VCS/Xcelium build it.
`include "bridge_cov_collector.sv"
`endif
`include "bridge_env.sv"

endpackage

`endif
