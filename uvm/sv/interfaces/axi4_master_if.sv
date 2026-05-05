`ifndef AXI4_MASTER_IF_SV
`define AXI4_MASTER_IF_SV

// AXI4 bundle from master toward bridge DUT slave interface (mirrors verilog TB).

interface axi4_master_if #(
  parameter int unsigned ID_WIDTH = 4,
  parameter int unsigned ADDR_WIDTH = 32,
  parameter int unsigned DATA_WIDTH = 64
) (
    input logic clk,
    input logic rst_n
);
  typedef logic [ID_WIDTH - 1:0] id_t;
  typedef logic [ADDR_WIDTH - 1:0] addr_t;
  typedef logic [DATA_WIDTH - 1:0] data_t;
  typedef logic [(DATA_WIDTH / 8) - 1:0] strb_t;

  id_t    S_AXI_AWID;
  addr_t  S_AXI_AWADDR;
  logic [7:0] S_AXI_AWLEN;
  logic [2:0] S_AXI_AWSIZE;
  logic [1:0] S_AXI_AWBURST;
  logic [2:0] S_AXI_AWPROT;
  logic       S_AXI_AWVALID;
  logic       S_AXI_AWREADY;

  data_t  S_AXI_WDATA;
  strb_t  S_AXI_WSTRB;
  logic   S_AXI_WLAST;
  logic   S_AXI_WVALID;
  logic   S_AXI_WREADY;

  id_t        S_AXI_BID;
  logic [1:0] S_AXI_BRESP;
  logic       S_AXI_BVALID;
  logic       S_AXI_BREADY;

  id_t        S_AXI_ARID;
  addr_t      S_AXI_ARADDR;
  logic [7:0] S_AXI_ARLEN;
  logic [2:0] S_AXI_ARSIZE;
  logic [1:0] S_AXI_ARBURST;
  logic [2:0] S_AXI_ARPROT;
  logic       S_AXI_ARVALID;
  logic       S_AXI_ARREADY;

  id_t        S_AXI_RID;
  data_t      S_AXI_RDATA;
  logic [1:0] S_AXI_RRESP;
  logic       S_AXI_RLAST;
  logic       S_AXI_RVALID;
  logic       S_AXI_RREADY;

endinterface

`endif
