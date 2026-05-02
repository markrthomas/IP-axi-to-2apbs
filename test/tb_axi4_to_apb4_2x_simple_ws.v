`timescale 1ns/1ps

`ifndef READ_WAIT_CYCLES
`define READ_WAIT_CYCLES 2
`endif

module tb_axi4_to_apb4_2x_simple_ws;

  localparam ID_WIDTH   = 4;
  localparam ADDR_WIDTH = 32;
  localparam DATA_WIDTH = 64;
  localparam integer READ_WAIT = `READ_WAIT_CYCLES;

  reg                       ACLK;
  reg                       ARESETn;

  // AXI signals
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

  // APB side
  wire [ADDR_WIDTH-1:0]     PADDR0;
  wire [2:0]                PPROT0;
  wire                      PSEL0;
  wire                      PENABLE0;
  wire                      PWRITE0;
  wire [DATA_WIDTH-1:0]     PWDATA0;
  wire [(DATA_WIDTH/8)-1:0] PSTRB0;
  reg  [DATA_WIDTH-1:0]     PRDATA0;
  reg                       PREADY0;
  wire                      PSLVERR0;

  wire [ADDR_WIDTH-1:0]     PADDR1;
  wire [2:0]                PPROT1;
  wire                      PSEL1;
  wire                      PENABLE1;
  wire                      PWRITE1;
  wire [DATA_WIDTH-1:0]     PWDATA1;
  wire [(DATA_WIDTH/8)-1:0] PSTRB1;
  reg  [DATA_WIDTH-1:0]     PRDATA1;
  reg                       PREADY1;
  wire                      PSLVERR1;

  assign PSLVERR0 = 1'b0;
  assign PSLVERR1 = 1'b0;

  // Simple APB memories
  reg [DATA_WIDTH-1:0] mem0 [0:255];
  reg [DATA_WIDTH-1:0] mem1 [0:255];

  integer rd_count0;
  integer rd_count1;

  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      PREADY0  <= 1'b1;
      PREADY1  <= 1'b1;
      rd_count0 <= 0;
      rd_count1 <= 0;
    end else begin
      PREADY0 <= 1'b1;
      PREADY1 <= 1'b1;

      // APB0 behavior
      if (rd_count0 > 0) begin
        if (rd_count0 == 1) begin
          PREADY0  <= 1'b1;
          rd_count0 <= 0;
        end else begin
          PREADY0  <= 1'b0;
          rd_count0 <= rd_count0 - 1;
        end
      end else if (PSEL0 && PENABLE0) begin
        if (PWRITE0) begin
          mem0[PADDR0[9:2]] <= PWDATA0;
        end else if (READ_WAIT > 0) begin
          PREADY0  <= 1'b0;
          rd_count0 <= READ_WAIT;
        end
      end

      // APB1 behavior
      if (rd_count1 > 0) begin
        if (rd_count1 == 1) begin
          PREADY1  <= 1'b1;
          rd_count1 <= 0;
        end else begin
          PREADY1  <= 1'b0;
          rd_count1 <= rd_count1 - 1;
        end
      end else if (PSEL1 && PENABLE1) begin
        if (PWRITE1) begin
          mem1[PADDR1[9:2]] <= PWDATA1;
        end else if (READ_WAIT > 0) begin
          PREADY1  <= 1'b0;
          rd_count1 <= READ_WAIT;
        end
      end
    end
  end

  always @(*) begin
    PRDATA0 = mem0[PADDR0[9:2]];
    PRDATA1 = mem1[PADDR1[9:2]];
  end

  axi4_to_apb4_2x_simple #(
    .ID_WIDTH(ID_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .ACLK(ACLK),
    .ARESETn(ARESETn),
    .S_AXI_AWID(S_AXI_AWID),
    .S_AXI_AWADDR(S_AXI_AWADDR),
    .S_AXI_AWLEN(S_AXI_AWLEN),
    .S_AXI_AWSIZE(S_AXI_AWSIZE),
    .S_AXI_AWBURST(S_AXI_AWBURST),
    .S_AXI_AWPROT(S_AXI_AWPROT),
    .S_AXI_AWVALID(S_AXI_AWVALID),
    .S_AXI_AWREADY(S_AXI_AWREADY),
    .S_AXI_WDATA(S_AXI_WDATA),
    .S_AXI_WSTRB(S_AXI_WSTRB),
    .S_AXI_WLAST(S_AXI_WLAST),
    .S_AXI_WVALID(S_AXI_WVALID),
    .S_AXI_WREADY(S_AXI_WREADY),
    .S_AXI_BID(S_AXI_BID),
    .S_AXI_BRESP(S_AXI_BRESP),
    .S_AXI_BVALID(S_AXI_BVALID),
    .S_AXI_BREADY(S_AXI_BREADY),
    .S_AXI_ARID(S_AXI_ARID),
    .S_AXI_ARADDR(S_AXI_ARADDR),
    .S_AXI_ARLEN(S_AXI_ARLEN),
    .S_AXI_ARSIZE(S_AXI_ARSIZE),
    .S_AXI_ARBURST(S_AXI_ARBURST),
    .S_AXI_ARPROT(S_AXI_ARPROT),
    .S_AXI_ARVALID(S_AXI_ARVALID),
    .S_AXI_ARREADY(S_AXI_ARREADY),
    .S_AXI_RID(S_AXI_RID),
    .S_AXI_RDATA(S_AXI_RDATA),
    .S_AXI_RRESP(S_AXI_RRESP),
    .S_AXI_RLAST(S_AXI_RLAST),
    .S_AXI_RVALID(S_AXI_RVALID),
    .S_AXI_RREADY(S_AXI_RREADY),
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

  initial begin
    ACLK = 0;
    forever #5 ACLK = ~ACLK;
  end

  initial begin
    ARESETn = 0;
    #40;
    ARESETn = 1;
  end

  task axi_single_write(
    input [ADDR_WIDTH-1:0] addr,
    input [DATA_WIDTH-1:0] data
  );
  begin
    @(posedge ACLK);
    S_AXI_AWID    <= 0;
    S_AXI_AWADDR  <= addr;
    S_AXI_AWLEN   <= 0;
    S_AXI_AWSIZE  <= 3'b011;
    S_AXI_AWBURST <= 2'b01;
    S_AXI_AWPROT  <= 3'b000;
    S_AXI_AWVALID <= 1;

    S_AXI_WDATA   <= data;
    S_AXI_WSTRB   <= {DATA_WIDTH/8{1'b1}};
    S_AXI_WLAST   <= 1;
    S_AXI_WVALID  <= 1;

    S_AXI_BREADY  <= 1;

    wait (S_AXI_AWREADY && S_AXI_WREADY);
    @(posedge ACLK);
    S_AXI_AWVALID <= 0;
    S_AXI_WVALID  <= 0;

    wait (S_AXI_BVALID);
    if (S_AXI_BRESP !== 2'b00) begin
      $display("ERROR: BRESP not OKAY: %0d", S_AXI_BRESP);
      $fatal;
    end
    @(posedge ACLK);
    S_AXI_BREADY <= 0;
  end
  endtask

  task axi_single_read(
    input  [ADDR_WIDTH-1:0] addr,
    output [DATA_WIDTH-1:0] data
  );
  begin
    @(posedge ACLK);
    S_AXI_ARID    <= 0;
    S_AXI_ARADDR  <= addr;
    S_AXI_ARLEN   <= 0;
    S_AXI_ARSIZE  <= 3'b011;
    S_AXI_ARBURST <= 2'b01;
    S_AXI_ARPROT  <= 3'b000;
    S_AXI_ARVALID <= 1;
    S_AXI_RREADY  <= 1;

    wait (S_AXI_ARREADY);
    @(posedge ACLK);
    S_AXI_ARVALID <= 0;

    wait (S_AXI_RVALID);
    if (S_AXI_RRESP !== 2'b00) begin
      $display("ERROR: RRESP not OKAY: %0d", S_AXI_RRESP);
      $fatal;
    end
    data = S_AXI_RDATA;
    if (!S_AXI_RLAST) begin
      $display("ERROR: RLAST not asserted");
      $fatal;
    end
    @(posedge ACLK);
    S_AXI_RREADY <= 0;
  end
  endtask

  reg [DATA_WIDTH-1:0] rdata0;
  reg [DATA_WIDTH-1:0] rdata1;

  initial begin
    S_AXI_AWID    = 0;
    S_AXI_AWADDR  = 0;
    S_AXI_AWLEN   = 0;
    S_AXI_AWSIZE  = 0;
    S_AXI_AWBURST = 0;
    S_AXI_AWPROT  = 0;
    S_AXI_AWVALID = 0;
    S_AXI_WDATA   = 0;
    S_AXI_WSTRB   = 0;
    S_AXI_WLAST   = 0;
    S_AXI_WVALID  = 0;
    S_AXI_BREADY  = 0;
    S_AXI_ARID    = 0;
    S_AXI_ARADDR  = 0;
    S_AXI_ARLEN   = 0;
    S_AXI_ARSIZE  = 0;
    S_AXI_ARBURST = 0;
    S_AXI_ARPROT  = 0;
    S_AXI_ARVALID = 0;
    S_AXI_RREADY  = 0;

    @(posedge ARESETn);
    @(posedge ACLK);

    axi_single_write(32'h0000_0010, 64'hDEAD_BEEF_CAFE_BABE);
    axi_single_read (32'h0000_0010, rdata0);
    if (rdata0 !== 64'hDEAD_BEEF_CAFE_BABE) begin
      $display("ERROR: APB0 readback mismatch. Got %h", rdata0);
      $fatal;
    end

    axi_single_write(32'h8000_0020, 64'h1234_5678_9ABC_DEF0);
    axi_single_read (32'h8000_0020, rdata1);
    if (rdata1 !== 64'h1234_5678_9ABC_DEF0) begin
      $display("ERROR: APB1 readback mismatch. Got %h", rdata1);
      $fatal;
    end

    $display("SIMPLE WS TEST PASSED (READ_WAIT_CYCLES=%0d)", READ_WAIT);
    $finish;
  end

endmodule
