`timescale 1ns/1ps

module tb_axi3lite_regblock;

  localparam ID_WIDTH   = 4;
  localparam ADDR_WIDTH = 32;
  localparam DATA_WIDTH = 32;

  reg                       ACLK;
  reg                       ARESETn;

  // AW channel
  reg  [ID_WIDTH-1:0]       S_AXI_AWID;
  reg  [ADDR_WIDTH-1:0]     S_AXI_AWADDR;
  reg  [2:0]                S_AXI_AWPROT;
  reg                       S_AXI_AWVALID;
  wire                      S_AXI_AWREADY;

  // W channel (AXI3: includes WID)
  reg  [ID_WIDTH-1:0]       S_AXI_WID;
  reg  [DATA_WIDTH-1:0]     S_AXI_WDATA;
  reg  [(DATA_WIDTH/8)-1:0] S_AXI_WSTRB;
  reg                       S_AXI_WVALID;
  wire                      S_AXI_WREADY;

  // B channel
  wire [ID_WIDTH-1:0]       S_AXI_BID;
  wire [1:0]                S_AXI_BRESP;
  wire                      S_AXI_BVALID;
  reg                       S_AXI_BREADY;

  // AR channel
  reg  [ID_WIDTH-1:0]       S_AXI_ARID;
  reg  [ADDR_WIDTH-1:0]     S_AXI_ARADDR;
  reg  [2:0]                S_AXI_ARPROT;
  reg                       S_AXI_ARVALID;
  wire                      S_AXI_ARREADY;

  // R channel
  wire [ID_WIDTH-1:0]       S_AXI_RID;
  wire [DATA_WIDTH-1:0]     S_AXI_RDATA;
  wire [1:0]                S_AXI_RRESP;
  wire                      S_AXI_RVALID;
  reg                       S_AXI_RREADY;

  axi3lite_regblock #(
    .ID_WIDTH(ID_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .ACLK(ACLK),
    .ARESETn(ARESETn),
    .S_AXI_AWID(S_AXI_AWID),
    .S_AXI_AWADDR(S_AXI_AWADDR),
    .S_AXI_AWPROT(S_AXI_AWPROT),
    .S_AXI_AWVALID(S_AXI_AWVALID),
    .S_AXI_AWREADY(S_AXI_AWREADY),
    .S_AXI_WID(S_AXI_WID),
    .S_AXI_WDATA(S_AXI_WDATA),
    .S_AXI_WSTRB(S_AXI_WSTRB),
    .S_AXI_WVALID(S_AXI_WVALID),
    .S_AXI_WREADY(S_AXI_WREADY),
    .S_AXI_BID(S_AXI_BID),
    .S_AXI_BRESP(S_AXI_BRESP),
    .S_AXI_BVALID(S_AXI_BVALID),
    .S_AXI_BREADY(S_AXI_BREADY),
    .S_AXI_ARID(S_AXI_ARID),
    .S_AXI_ARADDR(S_AXI_ARADDR),
    .S_AXI_ARPROT(S_AXI_ARPROT),
    .S_AXI_ARVALID(S_AXI_ARVALID),
    .S_AXI_ARREADY(S_AXI_ARREADY),
    .S_AXI_RID(S_AXI_RID),
    .S_AXI_RDATA(S_AXI_RDATA),
    .S_AXI_RRESP(S_AXI_RRESP),
    .S_AXI_RVALID(S_AXI_RVALID),
    .S_AXI_RREADY(S_AXI_RREADY)
  );

  // Clock: 10 ns period
  initial begin
    ACLK = 0;
    forever #5 ACLK = ~ACLK;
  end

  // Reset: 40 ns low then release
  initial begin
    ARESETn       = 0;
    S_AXI_AWVALID = 0; S_AXI_WVALID  = 0; S_AXI_BREADY  = 0;
    S_AXI_ARVALID = 0; S_AXI_RREADY  = 0;
    S_AXI_AWID    = 0; S_AXI_AWADDR  = 0; S_AXI_AWPROT  = 0;
    S_AXI_WID     = 0; S_AXI_WDATA   = 0; S_AXI_WSTRB   = 0;
    S_AXI_ARID    = 0; S_AXI_ARADDR  = 0; S_AXI_ARPROT  = 0;
    #40;
    @(posedge ACLK);
    ARESETn = 1;
  end

  // AXI3-Lite write task: issues AW+W and expects BRESP.
  // exp_resp: 2'b00=OKAY, 2'b10=SLVERR
  task axi3lite_write(
    input [ID_WIDTH-1:0]       id,
    input [ADDR_WIDTH-1:0]     addr,
    input [ID_WIDTH-1:0]       wid,
    input [DATA_WIDTH-1:0]     data,
    input [(DATA_WIDTH/8)-1:0] strb,
    input [1:0]                exp_resp
  );
  begin
    @(posedge ACLK);
    S_AXI_AWID    <= id;
    S_AXI_AWADDR  <= addr;
    S_AXI_AWPROT  <= 3'b000;
    S_AXI_AWVALID <= 1;
    S_AXI_WID     <= wid;
    S_AXI_WDATA   <= data;
    S_AXI_WSTRB   <= strb;
    S_AXI_WVALID  <= 1;
    S_AXI_BREADY  <= 1;
    // Wait for AW handshake
    wait (S_AXI_AWREADY);
    @(posedge ACLK);
    S_AXI_AWVALID <= 0;
    // Wait for W handshake
    wait (S_AXI_WREADY);
    @(posedge ACLK);
    S_AXI_WVALID <= 0;
    // Wait for B response
    wait (S_AXI_BVALID);
    if (S_AXI_BRESP !== exp_resp) begin
      $display("WRITE ERROR at addr 0x%08h: BRESP=%b expected=%b",
               addr, S_AXI_BRESP, exp_resp);
      $fatal;
    end
    @(posedge ACLK);
    S_AXI_BREADY <= 0;
  end
  endtask

  // AXI3-Lite read task: issues AR and expects RRESP + data.
  // Pass exp_data=0 and check_data=0 to skip data check (for SLVERR reads).
  task axi3lite_read(
    input  [ID_WIDTH-1:0]   id,
    input  [ADDR_WIDTH-1:0] addr,
    input  [1:0]            exp_resp,
    input  [DATA_WIDTH-1:0] exp_data,
    input                   check_data
  );
  begin
    @(posedge ACLK);
    S_AXI_ARID    <= id;
    S_AXI_ARADDR  <= addr;
    S_AXI_ARPROT  <= 3'b000;
    S_AXI_ARVALID <= 1;
    S_AXI_RREADY  <= 1;
    wait (S_AXI_ARREADY);
    @(posedge ACLK);
    S_AXI_ARVALID <= 0;
    wait (S_AXI_RVALID);
    if (S_AXI_RRESP !== exp_resp) begin
      $display("READ ERROR at addr 0x%08h: RRESP=%b expected=%b",
               addr, S_AXI_RRESP, exp_resp);
      $fatal;
    end
    if (check_data && (S_AXI_RDATA !== exp_data)) begin
      $display("READ DATA ERROR at addr 0x%08h: got 0x%08h expected 0x%08h",
               addr, S_AXI_RDATA, exp_data);
      $fatal;
    end
    @(posedge ACLK);
    S_AXI_RREADY <= 0;
  end
  endtask

  integer idx;
  reg [31:0] rd_data;

  initial begin
    // Wait for reset deassertion then 2 idle cycles
    wait (ARESETn);
    @(posedge ACLK);
    @(posedge ACLK);

    // 1. Write all 32 registers and read back
    for (idx = 0; idx < 32; idx = idx + 1) begin
      axi3lite_write(4'd1, idx * 4, 4'd1, 32'hA0000000 | idx, 4'hF, 2'b00);
    end
    for (idx = 0; idx < 32; idx = idx + 1) begin
      axi3lite_read(4'd2, idx * 4, 2'b00, 32'hA0000000 | idx, 1'b1);
    end

    // 2. Byte-strobe write: modify only byte 1 (bits [15:8]) of REG0.
    // REG0 = 0xA0000000; write 0xDE into bits [15:8] via strb[1].
    axi3lite_write(4'd1, 32'h00, 4'd1, 32'h0000DE00, 4'b0010, 2'b00);
    axi3lite_read(4'd2, 32'h00, 2'b00, 32'hA000DE00, 1'b1);

    // 3. Out-of-range write → SLVERR (address 0x80 is beyond REG31 at 0x7C)
    axi3lite_write(4'd3, 32'h80, 4'd3, 32'hDEADBEEF, 4'hF, 2'b10);

    // 4. Out-of-range read → SLVERR
    axi3lite_read(4'd4, 32'h80, 2'b10, 32'h0, 1'b0);

    // 5. WID ≠ AWID → SLVERR (id=5 but wid=6)
    axi3lite_write(4'd5, 32'h04, 4'd6, 32'hCAFEBABE, 4'hF, 2'b10);
    // REG1 should be unchanged (SLVERR discards the write)
    axi3lite_read(4'd5, 32'h04, 2'b00, 32'hA0000001, 1'b1);

    // 6. Verify AWID is reflected in BID (write with id=7)
    axi3lite_write(4'd7, 32'h08, 4'd7, 32'h12345678, 4'hF, 2'b00);
    if (S_AXI_BID !== 4'd7) begin
      $display("BID ERROR: got %0d expected 7", S_AXI_BID);
      $fatal;
    end
    axi3lite_read(4'd7, 32'h08, 2'b00, 32'h12345678, 1'b1);

    @(posedge ACLK);
    @(posedge ACLK);
    $display("PASSED");
    $finish;
  end

endmodule
