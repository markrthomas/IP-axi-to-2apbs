`timescale 1ns/1ps

module tb_uvm_regblock;

  import uvm_pkg::*;
  import regblock_stimulus_pkg::*;
  import regblock_uvm_env_pkg::*;
  import regblock_uvm_tests_pkg::*;

  localparam ID_WIDTH   = 4;
  localparam ADDR_WIDTH = 32;
  localparam DATA_WIDTH = 32;

  logic clk;
  logic rst_n;

  axi3lite_if #(
      .ID_WIDTH  (ID_WIDTH),
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_WIDTH(DATA_WIDTH)
  ) axi_if (
      .clk  (clk),
      .rst_n(rst_n)
  );

  axi3lite_regblock #(
      .ID_WIDTH  (ID_WIDTH),
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_WIDTH(DATA_WIDTH)
  ) dut (
      .ACLK         (clk),
      .ARESETn       (rst_n),
      .S_AXI_AWID   (axi_if.S_AXI_AWID),
      .S_AXI_AWADDR (axi_if.S_AXI_AWADDR),
      .S_AXI_AWPROT (axi_if.S_AXI_AWPROT),
      .S_AXI_AWVALID(axi_if.S_AXI_AWVALID),
      .S_AXI_AWREADY(axi_if.S_AXI_AWREADY),
      .S_AXI_WID    (axi_if.S_AXI_WID),
      .S_AXI_WDATA  (axi_if.S_AXI_WDATA),
      .S_AXI_WSTRB  (axi_if.S_AXI_WSTRB),
      .S_AXI_WVALID (axi_if.S_AXI_WVALID),
      .S_AXI_WREADY (axi_if.S_AXI_WREADY),
      .S_AXI_BID    (axi_if.S_AXI_BID),
      .S_AXI_BRESP  (axi_if.S_AXI_BRESP),
      .S_AXI_BVALID (axi_if.S_AXI_BVALID),
      .S_AXI_BREADY (axi_if.S_AXI_BREADY),
      .S_AXI_ARID   (axi_if.S_AXI_ARID),
      .S_AXI_ARADDR (axi_if.S_AXI_ARADDR),
      .S_AXI_ARPROT (axi_if.S_AXI_ARPROT),
      .S_AXI_ARVALID(axi_if.S_AXI_ARVALID),
      .S_AXI_ARREADY(axi_if.S_AXI_ARREADY),
      .S_AXI_RID    (axi_if.S_AXI_RID),
      .S_AXI_RDATA  (axi_if.S_AXI_RDATA),
      .S_AXI_RRESP  (axi_if.S_AXI_RRESP),
      .S_AXI_RVALID (axi_if.S_AXI_RVALID),
      .S_AXI_RREADY (axi_if.S_AXI_RREADY)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    rst_n = 1'b0;
    #40 rst_n = 1'b1;
  end

  initial begin
    uvm_config_db #(v_axi3lite_if_t)::set(null, "uvm_test_top", "vif", axi_if);
    run_test();
  end

endmodule : tb_uvm_regblock
