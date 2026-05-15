`ifndef AXI3LITE_IF_SV
`define AXI3LITE_IF_SV

// AXI3-Lite interface for the 32×32-bit register block.
// AXI3 adds WID (write-data ID) to the W channel; all other channels are
// identical to AXI4-Lite.

interface axi3lite_if #(
  parameter int unsigned ID_WIDTH   = 4,
  parameter int unsigned ADDR_WIDTH = 32,
  parameter int unsigned DATA_WIDTH = 32
) (
    input logic clk,
    input logic rst_n
);
  typedef logic [ID_WIDTH-1:0]       id_t;
  typedef logic [ADDR_WIDTH-1:0]     addr_t;
  typedef logic [DATA_WIDTH-1:0]     data_t;
  typedef logic [(DATA_WIDTH/8)-1:0] strb_t;

  // AW channel
  id_t        S_AXI_AWID;
  addr_t      S_AXI_AWADDR;
  logic [2:0] S_AXI_AWPROT;
  logic       S_AXI_AWVALID;
  logic       S_AXI_AWREADY;

  // W channel (AXI3: WID must equal AWID)
  id_t        S_AXI_WID;
  data_t      S_AXI_WDATA;
  strb_t      S_AXI_WSTRB;
  logic       S_AXI_WVALID;
  logic       S_AXI_WREADY;

  // B channel
  id_t        S_AXI_BID;
  logic [1:0] S_AXI_BRESP;
  logic       S_AXI_BVALID;
  logic       S_AXI_BREADY;

  // AR channel
  id_t        S_AXI_ARID;
  addr_t      S_AXI_ARADDR;
  logic [2:0] S_AXI_ARPROT;
  logic       S_AXI_ARVALID;
  logic       S_AXI_ARREADY;

  // R channel
  id_t        S_AXI_RID;
  data_t      S_AXI_RDATA;
  logic [1:0] S_AXI_RRESP;
  logic       S_AXI_RVALID;
  logic       S_AXI_RREADY;

endinterface

`endif
