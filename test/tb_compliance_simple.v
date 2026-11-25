`timescale 1ns/1ps

`include "wave_macros.v"

// AXI4 / APB4 compliance regressions for axi4_to_apb4_2x_simple.
// Each test drives a spec-legal AXI manager: VALID is held, payload stable,
// until the handshake ([AXI] IHI0022E A3.2.1). Contract refs: doc/design_contract.md §T0.4.
//
//   O1a  AWVALID + WVALID + ARVALID in the same cycle      -> no deadlock, write wins
//   O1b  WVALID + ARVALID together, AW three cycles later  -> no deadlock, write wins
//   O2   PSTRB is all-zero on every APB read ([APB] IHI0024C 3.2), checked continuously
//   O3a  AWLEN=3 DECERR write: all 4 W beats accepted before B, and none
//        leaks into the next write
//   O3b  AWLEN=1 DECERR write with AW before W           -> no deadlock
//
// A deadlock trips the per-test watchdog and ends the sim with $fatal.
module tb_compliance_simple;

  localparam ID_WIDTH   = 4;
  localparam ADDR_WIDTH = 32;
  localparam DATA_WIDTH = 64;
  localparam STRB_WIDTH = DATA_WIDTH/8;
  localparam TEST_TIMEOUT_CYCLES = 2000;

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
  reg  [STRB_WIDTH-1:0]     S_AXI_WSTRB;
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
  wire [STRB_WIDTH-1:0]     PSTRB0, PSTRB1;
  reg  [DATA_WIDTH-1:0]     PRDATA0, PRDATA1;
  reg                       PREADY0, PSLVERR0, PREADY1, PSLVERR1;

  axi4_to_apb4_2x_simple #(
    .ID_WIDTH(ID_WIDTH), .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
  ) dut (.*);

`IVL_OPTIONAL_DUMP(tb_compliance_simple, "waves_compliance_simple.fst")

  initial begin
    ACLK = 0;
    forever #5 ACLK = ~ACLK;
  end

  // ---------------------------------------------------------------- APB completers
  // Zero-wait, no-error memories, indexed by the 8-byte word address.
  reg [DATA_WIDTH-1:0] mem0 [0:1023];
  reg [DATA_WIDTH-1:0] mem1 [0:1023];
  integer k;
  initial for (k = 0; k < 1024; k = k + 1) begin mem0[k] = 0; mem1[k] = 0; end

  initial begin
    PREADY0 = 1; PREADY1 = 1; PSLVERR0 = 0; PSLVERR1 = 0;
  end
  always @(posedge ACLK) begin
    if (PSEL0 && PENABLE0 && PREADY0 && PWRITE0) mem0[PADDR0[12:3]] <= PWDATA0;
    if (PSEL1 && PENABLE1 && PREADY1 && PWRITE1) mem1[PADDR1[12:3]] <= PWDATA1;
  end
  always @(*) begin
    PRDATA0 = mem0[PADDR0[12:3]];
    PRDATA1 = mem1[PADDR1[12:3]];
  end

  // ---------------------------------------------------------------- checkers
  integer errors = 0;
  reg [8*48-1:0] test_name = "reset";
  integer test_cycles = 0;

  // O2: PSTRB must be LOW for the whole of every APB read transfer.
  always @(posedge ACLK) if (ARESETn) begin
    if (PSEL0 && !PWRITE0 && (PSTRB0 !== {STRB_WIDTH{1'b0}})) begin
      $display("ERROR [%0s] APB0 read with PSTRB0=%h (must be 0, APB 3.2) @%0t", test_name, PSTRB0, $time);
      errors = errors + 1;
    end
    if (PSEL1 && !PWRITE1 && (PSTRB1 !== {STRB_WIDTH{1'b0}})) begin
      $display("ERROR [%0s] APB1 read with PSTRB1=%h (must be 0, APB 3.2) @%0t", test_name, PSTRB1, $time);
      errors = errors + 1;
    end
  end

  // Per-test deadlock watchdog.
  always @(posedge ACLK) begin
    test_cycles = test_cycles + 1;
    if (test_cycles > TEST_TIMEOUT_CYCLES) begin
      $display("FAIL [%0s] no progress in %0d cycles: bridge deadlocked", test_name, TEST_TIMEOUT_CYCLES);
      $fatal(1, "tb_compliance_simple: deadlock");
    end
  end

  // W handshake counter (for "B only after the last W beat").
  integer w_hs = 0;
  always @(posedge ACLK) if (S_AXI_WVALID && S_AXI_WREADY) w_hs = w_hs + 1;

  task automatic start_test(input [8*48-1:0] name);
  begin
    test_name   = name;
    test_cycles = 0;
    w_hs        = 0;
    $display("[TEST] %0s", name);
  end
  endtask

  task automatic check(input cond, input [8*64-1:0] what);
  begin
    if (!cond) begin
      $display("ERROR [%0s] %0s", test_name, what);
      errors = errors + 1;
    end
  end
  endtask

  // ---------------------------------------------------------------- manager drivers
  // VALID is set with an NBA after a clock edge and sampled with READY at the
  // next edge, so every handshake is seen exactly as the DUT sees it.
  task automatic drive_aw(input [ADDR_WIDTH-1:0] addr, input [7:0] len, input [ID_WIDTH-1:0] id);
  begin
    S_AXI_AWID <= id; S_AXI_AWADDR <= addr; S_AXI_AWLEN <= len; S_AXI_AWSIZE <= 3'b011;
    S_AXI_AWBURST <= 2'b01; S_AXI_AWPROT <= 3'b000; S_AXI_AWVALID <= 1'b1;
    @(posedge ACLK);
    while (!S_AXI_AWREADY) @(posedge ACLK);
    S_AXI_AWVALID <= 1'b0;
  end
  endtask

  // Sends len+1 beats back-to-back (VALID held), WLAST on the final beat.
  task automatic drive_w(input [DATA_WIDTH-1:0] data0, input [7:0] len, input [STRB_WIDTH-1:0] strb);
    integer i;
  begin
    for (i = 0; i <= len; i = i + 1) begin
      S_AXI_WDATA <= data0 + i; S_AXI_WSTRB <= strb; S_AXI_WLAST <= (i == len); S_AXI_WVALID <= 1'b1;
      @(posedge ACLK);
      while (!S_AXI_WREADY) @(posedge ACLK);
    end
    S_AXI_WVALID <= 1'b0; S_AXI_WLAST <= 1'b0;
  end
  endtask

  task automatic drive_ar(input [ADDR_WIDTH-1:0] addr, input [ID_WIDTH-1:0] id);
  begin
    S_AXI_ARID <= id; S_AXI_ARADDR <= addr; S_AXI_ARLEN <= 8'd0; S_AXI_ARSIZE <= 3'b011;
    S_AXI_ARBURST <= 2'b01; S_AXI_ARPROT <= 3'b000; S_AXI_ARVALID <= 1'b1;
    @(posedge ACLK);
    while (!S_AXI_ARREADY) @(posedge ACLK);
    S_AXI_ARVALID <= 1'b0;
  end
  endtask

  // BREADY/RREADY are held high, so the handshake is the first edge with VALID.
  task automatic wait_b(output [1:0] resp, output [ID_WIDTH-1:0] id, output integer w_at_b);
  begin
    @(posedge ACLK);
    while (!S_AXI_BVALID) @(posedge ACLK);
    resp = S_AXI_BRESP; id = S_AXI_BID; w_at_b = w_hs;
  end
  endtask

  task automatic wait_r(output [DATA_WIDTH-1:0] data, output [1:0] resp, output last);
  begin
    @(posedge ACLK);
    while (!S_AXI_RVALID) @(posedge ACLK);
    data = S_AXI_RDATA; resp = S_AXI_RRESP; last = S_AXI_RLAST;
  end
  endtask

  task automatic idle(input integer n);
    integer j;
  begin
    for (j = 0; j < n; j = j + 1) @(posedge ACLK);
  end
  endtask

  // ---------------------------------------------------------------- tests
  reg [1:0]            bresp, rresp;
  reg [ID_WIDTH-1:0]   bid;
  reg [DATA_WIDTH-1:0] rdata;
  reg                  rlast;
  integer              w_at_b;

  initial begin
    ARESETn = 0;
    S_AXI_AWVALID = 0; S_AXI_WVALID = 0; S_AXI_WLAST = 0; S_AXI_ARVALID = 0;
    S_AXI_AWID = 0; S_AXI_AWADDR = 0; S_AXI_AWLEN = 0; S_AXI_AWSIZE = 0; S_AXI_AWBURST = 0; S_AXI_AWPROT = 0;
    S_AXI_WDATA = 0; S_AXI_WSTRB = 0;
    S_AXI_ARID = 0; S_AXI_ARADDR = 0; S_AXI_ARLEN = 0; S_AXI_ARSIZE = 0; S_AXI_ARBURST = 0; S_AXI_ARPROT = 0;
    S_AXI_BREADY = 1; S_AXI_RREADY = 1;
    repeat (5) @(posedge ACLK);
    ARESETn <= 1;
    repeat (2) @(posedge ACLK);

    // O1a: AW + W + AR presented in the same cycle.
    start_test("O1a AW+W+AR same cycle");
    fork
      drive_aw(32'h0000_0040, 8'd0, 4'h1);
      drive_w (64'hA1A1_0000_0000_0000, 8'd0, 8'hFF);
      drive_ar(32'h0000_0040, 4'h2);
      begin
        wait_b(bresp, bid, w_at_b);
        check(bresp == 2'b00, "O1a BRESP != OKAY");
        check(bid == 4'h1,    "O1a BID != AWID");
      end
      begin
        wait_r(rdata, rresp, rlast);
        check(rresp == 2'b00, "O1a RRESP != OKAY");
        check(rlast,          "O1a RLAST not set on single beat");
        check(rdata == 64'hA1A1_0000_0000_0000, "O1a read did not see the write (write must win)");
      end
    join
    idle(4);

    // O1b: W + AR together, AW three cycles later (W-before-AW is legal).
    start_test("O1b W+AR together, AW late");
    fork
      drive_w (64'hB2B2_0000_0000_0000, 8'd0, 8'hFF);
      drive_ar(32'h0000_0048, 4'h4);
      begin idle(3); drive_aw(32'h0000_0048, 8'd0, 4'h3); end
      begin
        wait_b(bresp, bid, w_at_b);
        check(bresp == 2'b00, "O1b BRESP != OKAY");
        check(bid == 4'h3,    "O1b BID != AWID");
      end
      begin
        wait_r(rdata, rresp, rlast);
        check(rresp == 2'b00, "O1b RRESP != OKAY");
        check(rdata == 64'hB2B2_0000_0000_0000, "O1b read did not see the write (write must win)");
      end
    join
    idle(4);

    // O2: write with a partial strobe on APB1, then read it. The PSTRB monitor
    // flags any read that still carries the write's strobes.
    start_test("O2 PSTRB low on read (APB1)");
    fork
      drive_aw(32'h8000_0010, 8'd0, 4'h5);
      drive_w (64'hC3C3_C3C3_C3C3_C3C3, 8'd0, 8'hA5);
      wait_b(bresp, bid, w_at_b);
    join
    fork
      drive_ar(32'h8000_0010, 4'h6);
      wait_r(rdata, rresp, rlast);
    join
    check(rresp == 2'b00, "O2 RRESP != OKAY");
    idle(4);

    // O3a: AWLEN=3 is unsupported by the simple top -> DECERR. A compliant
    // manager still sends all 4 beats; the bridge must take all of them before B
    // ([AXI] A3.3.1), and none may be attributed to the next write.
    start_test("O3a AWLEN=3 DECERR drains all W");
    fork
      drive_aw(32'h0000_0100, 8'd3, 4'h7);
      drive_w (64'hD400_0000_0000_0000, 8'd3, 8'hFF);
      begin
        wait_b(bresp, bid, w_at_b);
        check(bresp == 2'b11, "O3a BRESP != DECERR");
        check(bid == 4'h7,    "O3a BID != AWID");
        check(w_at_b == 4,    "O3a B issued before all 4 W beats were accepted");
      end
    join
    idle(2);
    // Next, legal single-beat write: must land at its own address with its own data.
    fork
      drive_aw(32'h0000_0200, 8'd0, 4'h8);
      drive_w (64'hE5E5_0000_0000_0000, 8'd0, 8'hFF);
      begin
        wait_b(bresp, bid, w_at_b);
        check(bresp == 2'b00, "O3a follow-up BRESP != OKAY");
      end
    join
    fork
      drive_ar(32'h0000_0200, 4'h9);
      wait_r(rdata, rresp, rlast);
    join
    check(rdata == 64'hE5E5_0000_0000_0000, "O3a follow-up write got stale W data from the DECERR burst");
    check(mem0[32'h0000_0100 >> 3] == 64'h0,  "O3a DECERR burst wrote to APB");
    idle(4);

    // O3b: unsupported AWLEN with AW accepted before any W beat arrives.
    start_test("O3b DECERR AW-before-W");
    fork
      drive_aw(32'h0000_0300, 8'd1, 4'hA);
      begin idle(3); drive_w(64'hF600_0000_0000_0000, 8'd1, 8'hFF); end
      begin
        wait_b(bresp, bid, w_at_b);
        check(bresp == 2'b11, "O3b BRESP != DECERR");
        check(w_at_b == 2,    "O3b B issued before both W beats were accepted");
      end
    join
    idle(4);

    if (errors != 0) begin
      $display("COMPLIANCE SIMPLE FAILED: %0d error(s)", errors);
      $fatal(1, "tb_compliance_simple: %0d error(s)", errors);
    end
    $display("COMPLIANCE SIMPLE PASSED");
    $finish;
  end

endmodule
