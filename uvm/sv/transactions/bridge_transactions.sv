`ifndef BRIDGE_TRANSACTIONS_SV
`define BRIDGE_TRANSACTIONS_SV

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

`endif
