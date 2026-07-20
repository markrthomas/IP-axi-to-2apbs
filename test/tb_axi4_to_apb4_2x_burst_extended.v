`timescale 1ns/1ps

`include "wave_macros.v"

module tb_repro_issues;

  localparam ID_WIDTH   = 4;
  localparam ADDR_WIDTH = 32;
  localparam DATA_WIDTH = 64;

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

  integer                   pready_rand_seed;

  axi4_to_apb4_2x_burst #(
    .ID_WIDTH(ID_WIDTH), .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
  ) dut (.*);

`IVL_OPTIONAL_DUMP(tb_repro_issues, "waves_burst_ext.fst")

  initial begin
    ACLK = 0;
    forever #5 ACLK = ~ACLK;
  end

  initial begin
    ARESETn = 0;
    #50 ARESETn = 1;
  end

  // Simple APB memory
  reg [DATA_WIDTH-1:0] mem0 [0:1023];
  reg [DATA_WIDTH-1:0] mem1 [0:1023];

  always @(posedge ACLK) begin
    if (PSEL0 && PENABLE0 && PREADY0 && PWRITE0) mem0[PADDR0[12:3]] <= PWDATA0;
    if (PSEL1 && PENABLE1 && PREADY1 && PWRITE1) mem1[PADDR1[12:3]] <= PWDATA1;
  end
  always @(*) begin
    PRDATA0 = mem0[PADDR0[12:3]];
    PRDATA1 = mem1[PADDR1[12:3]];
  end

  task axi_write_burst(
    input [ADDR_WIDTH-1:0] addr,
    input [7:0]            len,
    input [1:0]            burst,
    input [7:0]            wlast_at,
    input [7:0]            pslverr_at,
    output [1:0]           resp
  );
    integer i;
  begin
    @(posedge ACLK);
    S_AXI_AWADDR <= addr; S_AXI_AWLEN <= len; S_AXI_AWSIZE <= 3'b011; S_AXI_AWBURST <= burst; S_AXI_AWVALID <= 1; S_AXI_BREADY <= 1;
    while (!S_AXI_AWREADY) @(posedge ACLK);
    @(posedge ACLK);
    S_AXI_AWVALID <= 0;
    for (i = 0; i <= len; i = i + 1) begin
      S_AXI_WDATA <= (addr ^ i); S_AXI_WSTRB <= 8'hFF; S_AXI_WVALID <= 1; S_AXI_WLAST <= (i == wlast_at);
      if (addr[31]) PSLVERR1 <= (i == pslverr_at); else PSLVERR0 <= (i == pslverr_at);
      while (!S_AXI_WREADY) @(posedge ACLK);
      @(posedge ACLK);
      S_AXI_WVALID <= 0; S_AXI_WLAST <= 0; PSLVERR0 <= 0; PSLVERR1 <= 0;
      // Compliant AXI master: the write-data phase ends at WLAST.  For a premature
      // WLAST (wlast_at < len) this stops sending further beats, exercising the
      // bridge's WLAST-terminated completion instead of masking a deadlock.
      if (i == wlast_at) i = len + 1;
    end
    while (!S_AXI_BVALID) @(posedge ACLK);
    resp = S_AXI_BRESP;
    @(posedge ACLK);
    S_AXI_BREADY <= 0;
  end
  endtask

  task axi_read_burst(
    input [ADDR_WIDTH-1:0] addr,
    input [7:0]            len,
    input [1:0]            burst,
    output [1:0]           combined_resp
  );
    integer i;
  begin
    @(posedge ACLK);
    S_AXI_ARADDR <= addr; S_AXI_ARLEN <= len; S_AXI_ARSIZE <= 3'b011; S_AXI_ARBURST <= burst; S_AXI_ARVALID <= 1; S_AXI_RREADY <= 1;
    while (!S_AXI_ARREADY) @(posedge ACLK);
    @(posedge ACLK);
    S_AXI_ARVALID <= 0;
    combined_resp = 0;
    for (i = 0; i <= len; i = i + 1) begin
      while (!S_AXI_RVALID) @(posedge ACLK);
      if (S_AXI_RRESP > combined_resp) combined_resp = S_AXI_RRESP;
      if (S_AXI_RLAST != (i == len)) $display("ERROR: RLAST mismatch at beat %0d", i);
      @(posedge ACLK);
    end
    S_AXI_RREADY <= 0;
  end
  endtask

  reg [1:0] res;

  initial begin
    S_AXI_AWID = 0; S_AXI_AWADDR = 0; S_AXI_AWLEN = 0; S_AXI_AWSIZE = 0; S_AXI_AWBURST = 0; S_AXI_AWPROT = 0; S_AXI_AWVALID = 0;
    S_AXI_WDATA = 0; S_AXI_WSTRB = 0; S_AXI_WLAST = 0; S_AXI_WVALID = 0; S_AXI_BREADY = 0;
    S_AXI_ARID = 0; S_AXI_ARADDR = 0; S_AXI_ARLEN = 0; S_AXI_ARSIZE = 0; S_AXI_ARBURST = 0; S_AXI_ARPROT = 0; S_AXI_ARVALID = 0;
    S_AXI_RREADY = 0; PREADY0 = 1; PSLVERR0 = 0; PREADY1 = 1; PSLVERR1 = 0;

    @(posedge ARESETn);
    repeat (5) @(posedge ACLK);

    $display("--- Test 1: PSLVERR accumulation ---");
    axi_write_burst(32'h0000_1000, 2, 2'b01, 2, 1, res);
    if (res !== 2'b10) $display("FAILURE: got %b", res); else $display("SUCCESS");

    $display("--- Test 2: Premature WLAST ---");
    axi_write_burst(32'h0000_2000, 2, 2'b01, 0, 8'hFF, res);
    if (res !== 2'b10) $display("FAILURE: got %b", res); else $display("SUCCESS");

    $display("--- Test 3: Missing WLAST ---");
    axi_write_burst(32'h0000_3000, 1, 2'b01, 8'hFF, 8'hFF, res);
    if (res !== 2'b10) $display("FAILURE: got %b", res); else $display("SUCCESS");

    $display("--- Test 4: FIXED burst ---");
    axi_write_burst(32'h0000_4000, 3, 2'b00, 3, 8'hFF, res);
    if (res !== 2'b00) $display("FAILURE: got %b", res); else $display("SUCCESS");
    axi_read_burst(32'h0000_4000, 3, 2'b00, res);
    if (res !== 2'b00) $display("FAILURE: read got %b", res); else $display("SUCCESS");

    $display("--- Test 5: APB1 target ---");
    axi_write_burst(32'h8000_1000, 1, 2'b01, 1, 8'hFF, res);
    if (res !== 2'b00) $display("FAILURE: got %b", res); else $display("SUCCESS");
    axi_read_burst(32'h8000_1000, 1, 2'b01, res);
    if (res !== 2'b00) $display("FAILURE: read got %b", res); else $display("SUCCESS");

    $display("--- Test 6: DECERR crossing ---");
    axi_write_burst(32'h7FFF_FFF8, 1, 2'b01, 1, 8'hFF, res);
    if (res !== 2'b11) $display("FAILURE: got %b", res); else $display("SUCCESS");

    $display("--- Test 7: Wait states ---");
    fork
      begin
        pready_rand_seed = 32'h6b4d2e19;
        repeat (100) begin
          @(posedge ACLK);
          PREADY0 <= $random(pready_rand_seed);
          PREADY1 <= $random(pready_rand_seed);
        end
        PREADY0 <= 1;
        PREADY1 <= 1;
      end
      begin
        axi_write_burst(32'h0000_5000, 7, 2'b01, 7, 8'hFF, res);
        if (res !== 2'b00) $display("FAILURE: write got %b", res); else $display("SUCCESS");
        axi_read_burst(32'h0000_5000, 7, 2'b01, res);
        if (res !== 2'b00) $display("FAILURE: read got %b", res); else $display("SUCCESS");
      end
    join

    $display("All repro tests complete");
    $finish;
  end

  initial begin
    #20000;
    $display("TIMEOUT");
    $finish;
  end

endmodule
