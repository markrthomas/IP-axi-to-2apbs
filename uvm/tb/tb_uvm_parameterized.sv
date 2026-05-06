`timescale 1ns/1ps

module tb_uvm_parameterized;

  import uvm_pkg::*;
  import bridge_stimulus_pkg::*;
  import bridge_uvm_tests_pkg::*;
  import bridge_uvm_env_pkg::*;

  localparam ID_WIDTH     = 4;
  localparam ADDR_WIDTH   = 32;
  localparam DATA_WIDTH   = 32;
  localparam APB_ADDR_BIT = 20;

  logic clk;
  logic rst_n;

  axi4_master_if #(
      .DATA_WIDTH(DATA_WIDTH),
      .ADDR_WIDTH(ADDR_WIDTH),
      .ID_WIDTH(ID_WIDTH)
  ) axi_if (
      clk,
      rst_n
  );

  apb_sel_tracker_if sel_seen (
      clk,
      rst_n
  );

  wire [ADDR_WIDTH-1:0]     PADDR0, PADDR1;
  wire [2:0]                PPROT0, PPROT1;
  wire                      PSEL0, PENABLE0, PWRITE0, PSEL1, PENABLE1, PWRITE1;
  wire [DATA_WIDTH-1:0]     PWDATA0, PWDATA1;
  wire [(DATA_WIDTH/8)-1:0] PSTRB0, PSTRB1;
  logic [DATA_WIDTH-1:0]    PRDATA0, PRDATA1;
  wire                      PREADY0, PREADY1;
  wire                      PSLVERR0, PSLVERR1;

  assign sel_seen.PSEL0 = PSEL0;
  assign sel_seen.PSEL1 = PSEL1;

  axi4_to_apb4_2x_burst #(
      .ID_WIDTH(ID_WIDTH),
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_WIDTH(DATA_WIDTH),
      .APB_ADDR_BIT(APB_ADDR_BIT)
  ) dut (
      .ACLK(clk),
      .ARESETn(rst_n),
      .S_AXI_AWID(axi_if.S_AXI_AWID),
      .S_AXI_AWADDR(axi_if.S_AXI_AWADDR),
      .S_AXI_AWLEN(axi_if.S_AXI_AWLEN),
      .S_AXI_AWSIZE(axi_if.S_AXI_AWSIZE),
      .S_AXI_AWBURST(axi_if.S_AXI_AWBURST),
      .S_AXI_AWPROT(axi_if.S_AXI_AWPROT),
      .S_AXI_AWVALID(axi_if.S_AXI_AWVALID),
      .S_AXI_AWREADY(axi_if.S_AXI_AWREADY),
      .S_AXI_WDATA(axi_if.S_AXI_WDATA),
      .S_AXI_WSTRB(axi_if.S_AXI_WSTRB),
      .S_AXI_WLAST(axi_if.S_AXI_WLAST),
      .S_AXI_WVALID(axi_if.S_AXI_WVALID),
      .S_AXI_WREADY(axi_if.S_AXI_WREADY),
      .S_AXI_BID(axi_if.S_AXI_BID),
      .S_AXI_BRESP(axi_if.S_AXI_BRESP),
      .S_AXI_BVALID(axi_if.S_AXI_BVALID),
      .S_AXI_BREADY(axi_if.S_AXI_BREADY),
      .S_AXI_ARID(axi_if.S_AXI_ARID),
      .S_AXI_ARADDR(axi_if.S_AXI_ARADDR),
      .S_AXI_ARLEN(axi_if.S_AXI_ARLEN),
      .S_AXI_ARSIZE(axi_if.S_AXI_ARSIZE),
      .S_AXI_ARBURST(axi_if.S_AXI_ARBURST),
      .S_AXI_ARPROT(axi_if.S_AXI_ARPROT),
      .S_AXI_ARVALID(axi_if.S_AXI_ARVALID),
      .S_AXI_ARREADY(axi_if.S_AXI_ARREADY),
      .S_AXI_RID(axi_if.S_AXI_RID),
      .S_AXI_RDATA(axi_if.S_AXI_RDATA),
      .S_AXI_RRESP(axi_if.S_AXI_RRESP),
      .S_AXI_RLAST(axi_if.S_AXI_RLAST),
      .S_AXI_RVALID(axi_if.S_AXI_RVALID),
      .S_AXI_RREADY(axi_if.S_AXI_RREADY),
      .PADDR0(PADDR0),
      .PPROT0(PPROT0),
      .PSEL0(PSEL0),
      .PENABLE0(PENABLE0),
      .PWRITE0(PWRITE0),
      .PWDATA0(PWDATA0),
      .PSTRB0(PSTRB0),
      .PRDATA0(PRDATA0),
      .PREADY0(PREADY0),
      .PSLVERR0(PSLVERR0),
      .PADDR1(PADDR1),
      .PPROT1(PPROT1),
      .PSEL1(PSEL1),
      .PENABLE1(PENABLE1),
      .PWRITE1(PWRITE1),
      .PWDATA1(PWDATA1),
      .PSTRB1(PSTRB1),
      .PRDATA1(PRDATA1),
      .PREADY1(PREADY1),
      .PSLVERR1(PSLVERR1)
  );

  apb_dual_mem_param #(
      .ADDR_WIDTH (ADDR_WIDTH),
      .DATA_WIDTH (DATA_WIDTH)
  ) slv (
      .clk     (clk),
      .PADDR0  (PADDR0),
      .PADDR1  (PADDR1),
      .PSEL0   (PSEL0),
      .PENABLE0(PENABLE0),
      .PWRITE0 (PWRITE0),
      .PSEL1   (PSEL1),
      .PENABLE1(PENABLE1),
      .PWRITE1 (PWRITE1),
      .PWDATA0 (PWDATA0),
      .PWDATA1 (PWDATA1),
      .PRDATA0 (PRDATA0),
      .PRDATA1 (PRDATA1),
      .PREADY0 (PREADY0),
      .PREADY1 (PREADY1),
      .PSLVERR0(PSLVERR0),
      .PSLVERR1(PSLVERR1)
  );

  apb_mon_if #(
      .ADDR_WIDTH (ADDR_WIDTH),
      .DATA_WIDTH (DATA_WIDTH)
  ) ap_m0 (
      .clk(clk),
      .rst_n(rst_n),
      .PADDR(PADDR0),
      .PPROT(PPROT0),
      .PSEL(PSEL0),
      .PENABLE(PENABLE0),
      .PWRITE(PWRITE0),
      .PWDATA(PWDATA0),
      .PSTRB(PSTRB0),
      .PRDATA(PRDATA0),
      .PREADY(PREADY0),
      .PSLVERR(PSLVERR0)
  );

  apb_mon_if #(
      .ADDR_WIDTH (ADDR_WIDTH),
      .DATA_WIDTH (DATA_WIDTH)
  ) ap_m1 (
      .clk(clk),
      .rst_n(rst_n),
      .PADDR(PADDR1),
      .PPROT(PPROT1),
      .PSEL(PSEL1),
      .PENABLE(PENABLE1),
      .PWRITE(PWRITE1),
      .PWDATA(PWDATA1),
      .PSTRB(PSTRB1),
      .PRDATA(PRDATA1),
      .PREADY(PREADY1),
      .PSLVERR(PSLVERR1)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    rst_n = 1'b0;
    #50 rst_n = 1'b1;
  end

  initial begin
    uvm_config_db #(bridge_stimulus_pkg::v_axi_if_32_t)::set(null, "uvm_test_top",
                                                            "axi_vif", axi_if);
    uvm_config_db #(bridge_stimulus_pkg::v_apb_sel_tracker_t)::set(null, "uvm_test_top",
                                                                 "apb_sel_tracker",
                                                                 sel_seen);
    uvm_config_db #(
        virtual apb_mon_if #(
            .ADDR_WIDTH(ADDR_WIDTH),
            .DATA_WIDTH(DATA_WIDTH)
        )
    )::
        set(null, "uvm_test_top.env.apb_mon0", "vif", ap_m0);
    uvm_config_db #(
        virtual apb_mon_if #(
            .ADDR_WIDTH(ADDR_WIDTH),
            .DATA_WIDTH(DATA_WIDTH)
        )
    )::
        set(null, "uvm_test_top.env.apb_mon1", "vif", ap_m1);
    run_test("test_bridge_parameterized_cfg");
  end

endmodule
