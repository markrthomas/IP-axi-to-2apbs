`timescale 1ns/1ps

`include "wave_macros.v"

module tb_parameterized_config;

  localparam ID_WIDTH     = 4;
  localparam ADDR_WIDTH   = 32;
  localparam DATA_WIDTH   = 32;
  localparam APB_ADDR_BIT = 20;

  reg                       ACLK;
  reg                       ARESETn;

  reg  [ID_WIDTH-1:0]       S_AXI_AWID;
  reg  [ADDR_WIDTH-1:0]     S_AXI_AWADDR;
  reg  [7:0]                S_AXI_AWLEN;
  reg  [2:0]                S_AXI_AWSIZE;
  reg  [1:0]                S_AXI_AWBURST;
  reg  [2:0]                S_AXI_AWPROT;
  reg                       S_AXI_AWVALID;
  wire                      S_AXI_AWREADY;
  reg  [DATA_WIDTH-1:0]     S_AXI_WDATA;
  reg  [(DATA_WIDTH/8)-1:0] S_AXI_WSTRB;
  reg                       S_AXI_WLAST;
  reg                       S_AXI_WVALID;
  wire                      S_AXI_WREADY;
  wire [ID_WIDTH-1:0]       S_AXI_BID;
  wire [1:0]                S_AXI_BRESP;
  wire                      S_AXI_BVALID;
  reg                       S_AXI_BREADY;
  reg  [ID_WIDTH-1:0]       S_AXI_ARID;
  reg  [ADDR_WIDTH-1:0]     S_AXI_ARADDR;
  reg  [7:0]                S_AXI_ARLEN;
  reg  [2:0]                S_AXI_ARSIZE;
  reg  [1:0]                S_AXI_ARBURST;
  reg  [2:0]                S_AXI_ARPROT;
  reg                       S_AXI_ARVALID;
  wire                      S_AXI_ARREADY;
  wire [ID_WIDTH-1:0]       S_AXI_RID;
  wire [DATA_WIDTH-1:0]     S_AXI_RDATA;
  wire [1:0]                S_AXI_RRESP;
  wire                      S_AXI_RLAST;
  wire                      S_AXI_RVALID;
  reg                       S_AXI_RREADY;

  wire [ADDR_WIDTH-1:0]     PADDR0, PADDR1;
  wire [2:0]                PPROT0, PPROT1;
  wire                      PSEL0, PENABLE0, PWRITE0, PSEL1, PENABLE1, PWRITE1;
  wire [DATA_WIDTH-1:0]     PWDATA0, PWDATA1;
  wire [(DATA_WIDTH/8)-1:0] PSTRB0, PSTRB1;
  reg  [DATA_WIDTH-1:0]     PRDATA0, PRDATA1;
  reg                       PREADY0, PSLVERR0, PREADY1, PSLVERR1;

  axi4_to_apb4_2x_burst #(
    .ID_WIDTH(ID_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .APB_ADDR_BIT(APB_ADDR_BIT)
  ) dut (.*);

`IVL_OPTIONAL_DUMP(tb_parameterized_config, "waves_param.fst")

  initial begin
    ACLK = 0;
    forever #5 ACLK = ~ACLK;
  end

  initial begin
    ARESETn = 0;
    #50 ARESETn = 1;
  end

  initial begin
    #10000;
    $display("TIMEOUT");
    $finish;
  end

  task axi_write_32(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] data);
  begin
    @(posedge ACLK);
    S_AXI_AWADDR <= addr; S_AXI_AWLEN <= 0; S_AXI_AWSIZE <= 3'b010; S_AXI_AWBURST <= 2'b01; S_AXI_AWVALID <= 1; S_AXI_BREADY <= 1;
    S_AXI_WDATA <= data; S_AXI_WSTRB <= 4'hF; S_AXI_WVALID <= 1; S_AXI_WLAST <= 1;
    $display("AXI Write started: addr=%h, data=%h", addr, data);
    
    fork
      begin
        while (!S_AXI_AWREADY) @(posedge ACLK);
        $display("AW Handshake");
        @(posedge ACLK);
        S_AXI_AWVALID <= 0;
      end
      begin
        while (!S_AXI_WREADY) @(posedge ACLK);
        $display("W Handshake");
        @(posedge ACLK);
        S_AXI_WVALID <= 0;
      end
    join

    while (!S_AXI_BVALID) @(posedge ACLK);
    $display("AXI Response received: %b", S_AXI_BRESP);
    @(posedge ACLK);
    S_AXI_BREADY <= 0;
  end
  endtask

  reg psel0_seen, psel1_seen;
  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      psel0_seen <= 0;
      psel1_seen <= 0;
    end else begin
      if (PSEL0) psel0_seen <= 1;
      if (PSEL1) psel1_seen <= 1;
    end
  end

  initial begin
    S_AXI_AWID = 0; S_AXI_AWADDR = 0; S_AXI_AWLEN = 0; S_AXI_AWSIZE = 0; S_AXI_AWBURST = 0; S_AXI_AWPROT = 0; S_AXI_AWVALID = 0;
    S_AXI_WDATA = 0; S_AXI_WSTRB = 0; S_AXI_WLAST = 0; S_AXI_WVALID = 0; S_AXI_BREADY = 0;
    S_AXI_ARID = 0; S_AXI_ARADDR = 0; S_AXI_ARLEN = 0; S_AXI_ARSIZE = 0; S_AXI_ARBURST = 0; S_AXI_ARPROT = 0; S_AXI_ARVALID = 0;
    S_AXI_RREADY = 0; PREADY0 = 1; PSLVERR0 = 0; PREADY1 = 1; PSLVERR1 = 0;
    PRDATA0 = 0; PRDATA1 = 0;

    @(posedge ARESETn);
    repeat (5) @(posedge ACLK);

    $display("Test Parameterized: APB0 (bit 20=0)");
    psel0_seen = 0; psel1_seen = 0;
    axi_write_32(32'h0000_0000, 32'hAAAA_BBBB);
    if (!psel0_seen) $display("FAILURE: Expected PSEL0"); else $display("SUCCESS: PSEL0 asserted");

    $display("Test Parameterized: APB1 (bit 20=1)");
    psel0_seen = 0; psel1_seen = 0;
    axi_write_32(32'h0010_0000, 32'hCCCC_DDDD);
    if (!psel1_seen) $display("FAILURE: Expected PSEL1"); else $display("SUCCESS: PSEL1 asserted");

    $display("Test Parameterized: Wrong Size (expect DECERR)");
    @(posedge ACLK);
    S_AXI_AWADDR <= 32'h0; S_AXI_AWLEN <= 0; S_AXI_AWSIZE <= 3'b011; S_AXI_AWBURST <= 2'b01; S_AXI_AWVALID <= 1; S_AXI_BREADY <= 1;
    S_AXI_WDATA <= 0; S_AXI_WSTRB <= 4'hF; S_AXI_WVALID <= 1; S_AXI_WLAST <= 1;
    fork
      begin while (!S_AXI_AWREADY) @(posedge ACLK); @(posedge ACLK) S_AXI_AWVALID <= 0; end
      begin while (!S_AXI_WREADY) @(posedge ACLK); @(posedge ACLK) S_AXI_WVALID <= 0; end
    join
    while (!S_AXI_BVALID) @(posedge ACLK);
    if (S_AXI_BRESP !== 2'b11) $display("FAILURE: Expected DECERR for 64-bit size on 32-bit bridge, got %b", S_AXI_BRESP);
    else $display("SUCCESS: DECERR for wrong size");

    $display("Parameterized test complete");
    $finish;
  end

endmodule
