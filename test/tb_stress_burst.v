`timescale 1ns/1ps
`include "wave_macros.v"

// Randomised stress test for axi4_to_apb4_2x_burst.
//
// Plusargs:
//   +N=<n>       number of random transactions after seed writes (default 200)
//   +SEED=<s>    $random seed (default 0)
//   +WAIT0=<w>   fixed APB0 wait cycles per transfer (default 1)
//   +WAIT1=<w>   fixed APB1 wait cycles per transfer (default 1)
//   +BP=<b>      max BREADY/RREADY back-pressure cycles (default 3)
//
// Run length is driven by N; total sim cycles ≈ N * (burst_len * apb_cycles + overhead).
// Waveform: vvp sim_stress +N=50 +wave +wavefile=waves_stress.fst
//           (add -fst to vvp for FST output; omit for VCD)

module tb_stress_burst;

  localparam ID_W   = 4;
  localparam ADDR_W = 32;
  localparam DATA_W = 64;
  localparam STRB_W = 8;

  // -----------------------------------------------------------------------
  // Plusarg-configurable knobs
  // -----------------------------------------------------------------------
  integer N     = 200;
  integer WAIT0 = 1;
  integer WAIT1 = 1;
  integer BP    = 3;   // max back-pressure cycles on BREADY / per-beat RREADY
  integer SEED  = 0;

  // -----------------------------------------------------------------------
  // DUT interface registers / wires
  // -----------------------------------------------------------------------
  reg ACLK, ARESETn;

  reg  [ID_W-1:0]   S_AXI_AWID;
  reg  [ADDR_W-1:0] S_AXI_AWADDR;
  reg  [7:0]        S_AXI_AWLEN;
  reg  [2:0]        S_AXI_AWSIZE;
  reg  [1:0]        S_AXI_AWBURST;
  reg  [2:0]        S_AXI_AWPROT;
  reg               S_AXI_AWVALID;
  wire              S_AXI_AWREADY;

  reg  [DATA_W-1:0] S_AXI_WDATA;
  reg  [STRB_W-1:0] S_AXI_WSTRB;
  reg               S_AXI_WLAST;
  reg               S_AXI_WVALID;
  wire              S_AXI_WREADY;

  wire [ID_W-1:0]   S_AXI_BID;
  wire [1:0]        S_AXI_BRESP;
  wire              S_AXI_BVALID;
  reg               S_AXI_BREADY;

  reg  [ID_W-1:0]   S_AXI_ARID;
  reg  [ADDR_W-1:0] S_AXI_ARADDR;
  reg  [7:0]        S_AXI_ARLEN;
  reg  [2:0]        S_AXI_ARSIZE;
  reg  [1:0]        S_AXI_ARBURST;
  reg  [2:0]        S_AXI_ARPROT;
  reg               S_AXI_ARVALID;
  wire              S_AXI_ARREADY;

  wire [ID_W-1:0]   S_AXI_RID;
  wire [DATA_W-1:0] S_AXI_RDATA;
  wire [1:0]        S_AXI_RRESP;
  wire              S_AXI_RLAST;
  wire              S_AXI_RVALID;
  reg               S_AXI_RREADY;

  wire [ADDR_W-1:0] PADDR0;
  wire [2:0]        PPROT0;
  wire              PSEL0, PENABLE0, PWRITE0;
  wire [DATA_W-1:0] PWDATA0;
  wire [STRB_W-1:0] PSTRB0;
  reg  [DATA_W-1:0] PRDATA0;
  reg               PREADY0, PSLVERR0;

  wire [ADDR_W-1:0] PADDR1;
  wire [2:0]        PPROT1;
  wire              PSEL1, PENABLE1, PWRITE1;
  wire [DATA_W-1:0] PWDATA1;
  wire [STRB_W-1:0] PSTRB1;
  reg  [DATA_W-1:0] PRDATA1;
  reg               PREADY1, PSLVERR1;

  // -----------------------------------------------------------------------
  // DUT
  // -----------------------------------------------------------------------
  axi4_to_apb4_2x_burst #(
    .ID_WIDTH(ID_W), .ADDR_WIDTH(ADDR_W), .DATA_WIDTH(DATA_W)
  ) dut (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .S_AXI_AWID(S_AXI_AWID),   .S_AXI_AWADDR(S_AXI_AWADDR),
    .S_AXI_AWLEN(S_AXI_AWLEN), .S_AXI_AWSIZE(S_AXI_AWSIZE),
    .S_AXI_AWBURST(S_AXI_AWBURST), .S_AXI_AWPROT(S_AXI_AWPROT),
    .S_AXI_AWVALID(S_AXI_AWVALID), .S_AXI_AWREADY(S_AXI_AWREADY),
    .S_AXI_WDATA(S_AXI_WDATA),   .S_AXI_WSTRB(S_AXI_WSTRB),
    .S_AXI_WLAST(S_AXI_WLAST),   .S_AXI_WVALID(S_AXI_WVALID),
    .S_AXI_WREADY(S_AXI_WREADY),
    .S_AXI_BID(S_AXI_BID),   .S_AXI_BRESP(S_AXI_BRESP),
    .S_AXI_BVALID(S_AXI_BVALID), .S_AXI_BREADY(S_AXI_BREADY),
    .S_AXI_ARID(S_AXI_ARID),   .S_AXI_ARADDR(S_AXI_ARADDR),
    .S_AXI_ARLEN(S_AXI_ARLEN), .S_AXI_ARSIZE(S_AXI_ARSIZE),
    .S_AXI_ARBURST(S_AXI_ARBURST), .S_AXI_ARPROT(S_AXI_ARPROT),
    .S_AXI_ARVALID(S_AXI_ARVALID), .S_AXI_ARREADY(S_AXI_ARREADY),
    .S_AXI_RID(S_AXI_RID),   .S_AXI_RDATA(S_AXI_RDATA),
    .S_AXI_RRESP(S_AXI_RRESP), .S_AXI_RLAST(S_AXI_RLAST),
    .S_AXI_RVALID(S_AXI_RVALID), .S_AXI_RREADY(S_AXI_RREADY),
    .PADDR0(PADDR0), .PPROT0(PPROT0), .PSEL0(PSEL0),
    .PENABLE0(PENABLE0), .PWRITE0(PWRITE0), .PWDATA0(PWDATA0), .PSTRB0(PSTRB0),
    .PRDATA0(PRDATA0), .PREADY0(PREADY0), .PSLVERR0(PSLVERR0),
    .PADDR1(PADDR1), .PPROT1(PPROT1), .PSEL1(PSEL1),
    .PENABLE1(PENABLE1), .PWRITE1(PWRITE1), .PWDATA1(PWDATA1), .PSTRB1(PSTRB1),
    .PRDATA1(PRDATA1), .PREADY1(PREADY1), .PSLVERR1(PSLVERR1)
  );

  // -----------------------------------------------------------------------
  // Clock
  // -----------------------------------------------------------------------
  initial ACLK = 0;
  always  #5 ACLK = ~ACLK;  // 100 MHz

  // -----------------------------------------------------------------------
  // Waveform dump (triggered by +wave / +wavefile= on vvp command line)
  // -----------------------------------------------------------------------
  `IVL_OPTIONAL_DUMP(tb_stress_burst, "waves_stress.fst")

  // -----------------------------------------------------------------------
  // APB slave memories: 256 × 64-bit words per slave
  // Word index = PADDR[10:3]  (8-byte-aligned, 2 KB per slave window)
  // APB0 base: 0x0000_0000   APB1 base: 0x8000_0000
  // -----------------------------------------------------------------------
  reg [DATA_W-1:0] mem0 [0:255];
  reg [DATA_W-1:0] mem1 [0:255];

  // Shadow model for read-back checking
  reg [DATA_W-1:0] shadow0 [0:255];
  reg [DATA_W-1:0] shadow1 [0:255];
  reg              valid0  [0:255];
  reg              valid1  [0:255];

  // Apply byte strobes helper (used by slave model and shadow update)
  function [DATA_W-1:0] apply_strobe;
    input [DATA_W-1:0] old_val;
    input [DATA_W-1:0] new_val;
    input [STRB_W-1:0] strb;
    integer b;
    begin
      apply_strobe = old_val;
      for (b = 0; b < STRB_W; b = b + 1)
        if (strb[b])
          apply_strobe[b*8 +: 8] = new_val[b*8 +: 8];
    end
  endfunction

  // -----------------------------------------------------------------------
  // APB slave 0 — synchronous, configurable wait states
  // -----------------------------------------------------------------------
  integer apb0_wait_rem;
  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      PRDATA0 <= 0; PREADY0 <= 1; PSLVERR0 <= 0; apb0_wait_rem <= 0;
    end else if (!PSEL0) begin
      PREADY0 <= 1; apb0_wait_rem <= 0;
    end else if (!PENABLE0) begin
      // Setup phase: pre-load read data, arm wait counter
      if (!PWRITE0) PRDATA0 <= mem0[PADDR0[10:3]];
      apb0_wait_rem <= WAIT0;
      PREADY0 <= (WAIT0 == 0) ? 1 : 0;
    end else begin
      // Access phase
      if (apb0_wait_rem > 0) begin
        apb0_wait_rem <= apb0_wait_rem - 1;
        PREADY0 <= (apb0_wait_rem == 1) ? 1 : 0;
      end else begin
        PREADY0 <= 1;
        if (PWRITE0)
          mem0[PADDR0[10:3]] <= apply_strobe(mem0[PADDR0[10:3]], PWDATA0, PSTRB0);
      end
    end
  end

  // -----------------------------------------------------------------------
  // APB slave 1 — same structure
  // -----------------------------------------------------------------------
  integer apb1_wait_rem;
  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      PRDATA1 <= 0; PREADY1 <= 1; PSLVERR1 <= 0; apb1_wait_rem <= 0;
    end else if (!PSEL1) begin
      PREADY1 <= 1; apb1_wait_rem <= 0;
    end else if (!PENABLE1) begin
      if (!PWRITE1) PRDATA1 <= mem1[PADDR1[10:3]];
      apb1_wait_rem <= WAIT1;
      PREADY1 <= (WAIT1 == 0) ? 1 : 0;
    end else begin
      if (apb1_wait_rem > 0) begin
        apb1_wait_rem <= apb1_wait_rem - 1;
        PREADY1 <= (apb1_wait_rem == 1) ? 1 : 0;
      end else begin
        PREADY1 <= 1;
        if (PWRITE1)
          mem1[PADDR1[10:3]] <= apply_strobe(mem1[PADDR1[10:3]], PWDATA1, PSTRB1);
      end
    end
  end

  // -----------------------------------------------------------------------
  // Scratch storage for burst data (max 16 beats)
  // -----------------------------------------------------------------------
  reg [DATA_W-1:0] burst_wr_data [0:15];
  reg [DATA_W-1:0] burst_rd_data [0:15];

  // -----------------------------------------------------------------------
  // AXI driver tasks
  // -----------------------------------------------------------------------

  // Single-beat write.  bresp_out captures BRESP.
  // bp_cycles: extra cycles to hold BREADY low after issuing the beat.
  task do_write;
    input [ADDR_W-1:0] addr;
    input [DATA_W-1:0] data;
    input [ID_W-1:0]   awid;
    input [STRB_W-1:0] strb;
    input integer      bp_cycles;
    output [1:0]       bresp_out;
    integer k;
    begin
      @(posedge ACLK);
      S_AXI_AWID    <= awid;
      S_AXI_AWADDR  <= addr;
      S_AXI_AWLEN   <= 8'd0;
      S_AXI_AWSIZE  <= 3'b011;
      S_AXI_AWBURST <= 2'b01;
      S_AXI_AWPROT  <= 3'b000;
      S_AXI_AWVALID <= 1;
      S_AXI_WDATA   <= data;
      S_AXI_WSTRB   <= strb;
      S_AXI_WLAST   <= 1;
      S_AXI_WVALID  <= 1;
      S_AXI_BREADY  <= (bp_cycles == 0) ? 1 : 0;

      // Wait for AW handshake
      @(posedge ACLK);
      while (!S_AXI_AWREADY) @(posedge ACLK);
      S_AXI_AWVALID <= 0;

      // Wait for W handshake (may have already happened)
      while (!S_AXI_WREADY) @(posedge ACLK);
      S_AXI_WVALID <= 0;
      S_AXI_WLAST  <= 0;

      // Back-pressure: hold BREADY low for bp_cycles extra cycles
      for (k = 0; k < bp_cycles; k = k + 1)
        @(posedge ACLK);
      S_AXI_BREADY <= 1;

      // Wait for BVALID
      while (!S_AXI_BVALID) @(posedge ACLK);
      bresp_out    = S_AXI_BRESP;
      @(posedge ACLK);
      S_AXI_BREADY <= 0;
    end
  endtask

  // Multi-beat write (INCR or FIXED, len = AWLEN+1).
  task do_burst_write;
    input [ADDR_W-1:0] addr;
    input integer      len;       // number of beats (1..16)
    input [1:0]        burst_type; // 2'b01=INCR, 2'b00=FIXED
    input [ID_W-1:0]   awid;
    input [STRB_W-1:0] strb;
    input integer      bp_cycles;
    output [1:0]       bresp_out;
    integer i, k;
    begin
      @(posedge ACLK);
      S_AXI_AWID    <= awid;
      S_AXI_AWADDR  <= addr;
      S_AXI_AWLEN   <= len - 1;
      S_AXI_AWSIZE  <= 3'b011;
      S_AXI_AWBURST <= burst_type;
      S_AXI_AWPROT  <= 3'b000;
      S_AXI_AWVALID <= 1;
      S_AXI_BREADY  <= 0;

      @(posedge ACLK);
      while (!S_AXI_AWREADY) @(posedge ACLK);
      S_AXI_AWVALID <= 0;

      for (i = 0; i < len; i = i + 1) begin
        S_AXI_WDATA  <= burst_wr_data[i];
        S_AXI_WSTRB  <= strb;
        S_AXI_WLAST  <= (i == len - 1) ? 1 : 0;
        S_AXI_WVALID <= 1;
        @(posedge ACLK);
        while (!S_AXI_WREADY) @(posedge ACLK);
      end
      S_AXI_WVALID <= 0;
      S_AXI_WLAST  <= 0;

      // Back-pressure on BREADY
      for (k = 0; k < bp_cycles; k = k + 1)
        @(posedge ACLK);
      S_AXI_BREADY <= 1;

      while (!S_AXI_BVALID) @(posedge ACLK);
      bresp_out    = S_AXI_BRESP;
      @(posedge ACLK);
      S_AXI_BREADY <= 0;
    end
  endtask

  // Single-beat read.  bp_cycles: extra stall on RREADY before accepting.
  task do_read;
    input [ADDR_W-1:0] addr;
    input [ID_W-1:0]   arid;
    input integer      bp_cycles;
    output [DATA_W-1:0] rdata_out;
    output [1:0]        rresp_out;
    integer k;
    begin
      @(posedge ACLK);
      S_AXI_ARID    <= arid;
      S_AXI_ARADDR  <= addr;
      S_AXI_ARLEN   <= 8'd0;
      S_AXI_ARSIZE  <= 3'b011;
      S_AXI_ARBURST <= 2'b01;
      S_AXI_ARPROT  <= 3'b000;
      S_AXI_ARVALID <= 1;
      S_AXI_RREADY  <= 0;

      @(posedge ACLK);
      while (!S_AXI_ARREADY) @(posedge ACLK);
      S_AXI_ARVALID <= 0;

      for (k = 0; k < bp_cycles; k = k + 1)
        @(posedge ACLK);
      S_AXI_RREADY <= 1;
      // One mandatory posedge so RREADY=1 is committed before we sample RVALID.
      // Without this, the NBA for RREADY=1 and the immediately-following
      // RREADY=0 (below) can race and cancel each other in the same timestep.
      @(posedge ACLK);
      while (!S_AXI_RVALID) @(posedge ACLK);
      rdata_out = S_AXI_RDATA;
      rresp_out = S_AXI_RRESP;
      S_AXI_RREADY <= 0;
      @(posedge ACLK);
    end
  endtask

  // Multi-beat read (INCR or FIXED).  Back-pressure applied per beat.
  task do_burst_read;
    input [ADDR_W-1:0] addr;
    input integer      len;
    input [1:0]        burst_type;
    input [ID_W-1:0]   arid;
    input integer      bp_cycles;  // max stall per beat
    output [1:0]       rresp_out;
    integer i, k, rng;
    begin
      @(posedge ACLK);
      S_AXI_ARID    <= arid;
      S_AXI_ARADDR  <= addr;
      S_AXI_ARLEN   <= len - 1;
      S_AXI_ARSIZE  <= 3'b011;
      S_AXI_ARBURST <= burst_type;
      S_AXI_ARPROT  <= 3'b000;
      S_AXI_ARVALID <= 1;
      S_AXI_RREADY  <= 0;

      @(posedge ACLK);
      while (!S_AXI_ARREADY) @(posedge ACLK);
      S_AXI_ARVALID <= 0;

      rresp_out = 2'b00;
      for (i = 0; i < len; i = i + 1) begin
        // Random per-beat stall (0..bp_cycles)
        rng = (bp_cycles > 0) ? ($random % (bp_cycles + 1)) : 0;
        if (rng < 0) rng = -rng;
        for (k = 0; k < rng; k = k + 1)
          @(posedge ACLK);
        S_AXI_RREADY <= 1;
        @(posedge ACLK);                          // commit RREADY=1 before sampling RVALID
        while (!S_AXI_RVALID) @(posedge ACLK);
        burst_rd_data[i] = S_AXI_RDATA;
        if (S_AXI_RRESP > rresp_out) rresp_out = S_AXI_RRESP;
        if (S_AXI_RLAST != (i == len - 1))
          $display("[STRESS] RLAST wrong at beat %0d/%0d addr=0x%08x", i, len-1, addr);
        // Deassert RREADY before advancing so the DUT cannot silently consume
        // the next beat while RREADY is still asserted.
        S_AXI_RREADY <= 0;
        @(posedge ACLK);
      end
    end
  endtask

  // -----------------------------------------------------------------------
  // Shadow model update helpers (call after confirmed OKAY write)
  // -----------------------------------------------------------------------
  task shadow_write;
    input        slave;        // 0 or 1
    input [7:0]  widx;
    input [DATA_W-1:0] data;
    input [STRB_W-1:0] strb;
    reg [DATA_W-1:0] old;
    begin
      if (slave == 0) begin
        old = valid0[widx] ? shadow0[widx] : {DATA_W{1'b0}};
        shadow0[widx] = apply_strobe(old, data, strb);
        valid0[widx]  = 1;
      end else begin
        old = valid1[widx] ? shadow1[widx] : {DATA_W{1'b0}};
        shadow1[widx] = apply_strobe(old, data, strb);
        valid1[widx]  = 1;
      end
    end
  endtask

  // -----------------------------------------------------------------------
  // Main test
  // -----------------------------------------------------------------------
  integer    i, j, k;
  integer    txn_cnt, err_cnt, warn_cnt;
  integer    rng, len_choices [0:3];
  reg        slave_sel;
  reg [7:0]  widx;
  reg [ADDR_W-1:0] addr;
  reg [DATA_W-1:0] wdata, rdata;
  reg [STRB_W-1:0] wstrb;
  reg [1:0]        burst_type;
  reg [ID_W-1:0]   tid;
  reg [1:0]        bresp, rresp;
  integer          bp_cyc;
  integer          txn_type; // 0=single wr, 1=burst wr, 2=single rd, 3=burst rd

  // Timeout watchdog (scales with N and max burst + wait overhead)
  integer TIMEOUT_CYCLES;

  initial begin
    // ---- parse plusargs ------------------------------------------------
    if ($test$plusargs("N"))     $value$plusargs("N=%d",     N);
    if ($test$plusargs("SEED"))  $value$plusargs("SEED=%d",  SEED);
    if ($test$plusargs("WAIT0")) $value$plusargs("WAIT0=%d", WAIT0);
    if ($test$plusargs("WAIT1")) $value$plusargs("WAIT1=%d", WAIT1);
    if ($test$plusargs("BP"))    $value$plusargs("BP=%d",    BP);

    TIMEOUT_CYCLES = (N + 32) * (16 * (WAIT0 + WAIT1 + 4) + BP + 20);

    // Seed $random
    rng = $random(SEED);

    // ---- initialise AXI outputs ----------------------------------------
    ARESETn         = 0;
    S_AXI_AWID      = 0; S_AXI_AWADDR = 0; S_AXI_AWLEN = 0;
    S_AXI_AWSIZE    = 0; S_AXI_AWBURST = 0; S_AXI_AWPROT = 0;
    S_AXI_AWVALID   = 0;
    S_AXI_WDATA     = 0; S_AXI_WSTRB = 0; S_AXI_WLAST = 0; S_AXI_WVALID = 0;
    S_AXI_BREADY    = 0;
    S_AXI_ARID      = 0; S_AXI_ARADDR = 0; S_AXI_ARLEN = 0;
    S_AXI_ARSIZE    = 0; S_AXI_ARBURST = 0; S_AXI_ARPROT = 0;
    S_AXI_ARVALID   = 0;
    S_AXI_RREADY    = 0;

    // ---- initialise shadow model ----------------------------------------
    for (i = 0; i < 256; i = i + 1) begin
      valid0[i] = 0; valid1[i] = 0;
      mem0[i]   = 0; mem1[i]   = 0;
      shadow0[i]= 0; shadow1[i]= 0;
    end

    // ---- reset ----------------------------------------------------------
    repeat (8) @(posedge ACLK);
    ARESETn = 1;
    repeat (4) @(posedge ACLK);

    err_cnt  = 0;
    warn_cnt = 0;

    // ---- Phase 1: seed writes (32 words per slave, deterministic) -------
    // Ensures shadow model is populated before any reads are attempted.
    $display("[STRESS] Phase 1: seeding 32 words per slave (N=%0d WAIT0=%0d WAIT1=%0d BP=%0d SEED=%0d)",
             N, WAIT0, WAIT1, BP, SEED);
    for (i = 0; i < 32; i = i + 1) begin
      // APB0
      wdata     = {$random, $random};
      wstrb     = 8'hFF;
      addr      = {1'b0, 20'b0, i[7:0], 3'b000};
      do_write(addr, wdata, 4'd0, wstrb, 0, bresp);
      if (bresp == 2'b00) begin
        shadow_write(0, i[7:0], wdata, wstrb);
      end else begin
        $display("[STRESS] SEED WR FAIL slave=0 widx=%0d bresp=%0b", i, bresp);
        err_cnt = err_cnt + 1;
      end
      // APB1
      wdata     = {$random, $random};
      addr      = {1'b1, 20'b0, i[7:0], 3'b000};
      do_write(addr, wdata, 4'd1, wstrb, 0, bresp);
      if (bresp == 2'b00) begin
        shadow_write(1, i[7:0], wdata, wstrb);
      end else begin
        $display("[STRESS] SEED WR FAIL slave=1 widx=%0d bresp=%0b", i, bresp);
        err_cnt = err_cnt + 1;
      end
    end

    // ---- Phase 2: randomised transactions --------------------------------
    $display("[STRESS] Phase 2: %0d random transactions", N);

    txn_cnt = 0;
    while (txn_cnt < N) begin

      // Pick random transaction type: 0=single-wr, 1=burst-wr, 2=single-rd, 3=burst-rd
      txn_type  = $random % 4; if (txn_type < 0) txn_type = -txn_type;
      slave_sel = $random % 2;
      tid       = $random % 8;
      bp_cyc    = $random % (BP + 1); if (bp_cyc < 0) bp_cyc = -bp_cyc;

      // Burst length: choose from {1,2,4,8}
      rng = $random % 4; if (rng < 0) rng = -rng;
      case (rng)
        0: len_choices[0] = 1;
        1: len_choices[0] = 2;
        2: len_choices[0] = 4;
        3: len_choices[0] = 8;
      endcase

      // Burst type: INCR (01) ~70%, FIXED (00) ~30%
      rng        = $random % 10; if (rng < 0) rng = -rng;
      burst_type = (rng < 7) ? 2'b01 : 2'b00;

      // Word index: for INCR ensure all beats stay within [0,255]
      rng = $random % (256 - (burst_type == 2'b01 ? len_choices[0] : 1) + 1);
      if (rng < 0) rng = -rng;
      widx = rng[7:0];

      // Full 32-bit AXI address
      addr = {slave_sel, 20'b0, widx, 3'b000};

      // Partial strobe ~20% of writes
      rng = $random % 5; if (rng < 0) rng = -rng;
      if (rng == 0) begin
        rng   = $random;
        wstrb = rng[7:0];
        if (wstrb == 8'h00) wstrb = 8'hFF; // avoid all-zero (no-op write)
      end else begin
        wstrb = 8'hFF;
      end

      case (txn_type)

        // ---- single write ------------------------------------------------
        0: begin
          wdata = {$random, $random};
          do_write(addr, wdata, tid, wstrb, bp_cyc, bresp);
          if (bresp == 2'b00)
            shadow_write(slave_sel, widx, wdata, wstrb);
          else begin
            $display("[STRESS] txn=%0d SINGLE WR ERR slave=%0d widx=%0d bresp=%0b",
                     txn_cnt, slave_sel, widx, bresp);
            err_cnt = err_cnt + 1;
          end
          txn_cnt = txn_cnt + 1;
        end

        // ---- burst write -------------------------------------------------
        1: begin
          for (j = 0; j < len_choices[0]; j = j + 1)
            burst_wr_data[j] = {$random, $random};
          do_burst_write(addr, len_choices[0], burst_type, tid, wstrb, bp_cyc, bresp);
          if (bresp == 2'b00) begin
            for (j = 0; j < len_choices[0]; j = j + 1) begin
              // FIXED: all beats to same widx; INCR: sequential
              rng = (burst_type == 2'b00) ? 0 : j;
              shadow_write(slave_sel, widx + rng[7:0], burst_wr_data[j], wstrb);
            end
          end else begin
            $display("[STRESS] txn=%0d BURST WR ERR slave=%0d widx=%0d len=%0d bresp=%0b",
                     txn_cnt, slave_sel, widx, len_choices[0], bresp);
            err_cnt = err_cnt + 1;
          end
          txn_cnt = txn_cnt + 1;
        end

        // ---- single read -------------------------------------------------
        2: begin
          // Only read addresses that have been written (guaranteed by phase 1 for widx<32)
          if (!((slave_sel == 0) ? valid0[widx] : valid1[widx])) begin
            // Fall back to a seeded address
            widx = $random % 32; if ($signed(widx) < 0) widx = -widx;
            addr = {slave_sel, 20'b0, widx, 3'b000};
          end
          do_read(addr, tid, bp_cyc, rdata, rresp);
          if (rresp != 2'b00) begin
            $display("[STRESS] txn=%0d SINGLE RD RRESP slave=%0d widx=%0d rresp=%0b",
                     txn_cnt, slave_sel, widx, rresp);
            err_cnt = err_cnt + 1;
          end else begin
            wdata = (slave_sel == 0) ? shadow0[widx] : shadow1[widx];
            if (rdata !== wdata) begin
              $display("[STRESS] txn=%0d MISMATCH slave=%0d widx=%0d got=0x%016x exp=0x%016x",
                       txn_cnt, slave_sel, widx, rdata, wdata);
              err_cnt = err_cnt + 1;
            end
          end
          txn_cnt = txn_cnt + 1;
        end

        // ---- burst read --------------------------------------------------
        3: begin
          // Ensure all beats have valid shadow data (use low widx range)
          rng = 32 - len_choices[0]; if (rng < 1) rng = 1;
          widx = $random % rng; if ($signed(widx) < 0) widx = -widx;
          addr = {slave_sel, 20'b0, widx, 3'b000};
          do_burst_read(addr, len_choices[0], burst_type, tid, bp_cyc, rresp);
          if (rresp != 2'b00) begin
            $display("[STRESS] txn=%0d BURST RD RRESP slave=%0d widx=%0d len=%0d rresp=%0b",
                     txn_cnt, slave_sel, widx, len_choices[0], rresp);
            err_cnt = err_cnt + 1;
          end else begin
            for (j = 0; j < len_choices[0]; j = j + 1) begin
              rng = (burst_type == 2'b00) ? 0 : j;
              wdata = (slave_sel == 0) ? shadow0[widx + rng[7:0]]
                                       : shadow1[widx + rng[7:0]];
              if (burst_rd_data[j] !== wdata) begin
                $display("[STRESS] txn=%0d BURST MISMATCH slave=%0d widx=%0d beat=%0d got=0x%016x exp=0x%016x",
                         txn_cnt, slave_sel, widx + rng, j, burst_rd_data[j], wdata);
                err_cnt = err_cnt + 1;
              end
            end
          end
          txn_cnt = txn_cnt + 1;
        end

      endcase
    end

    // ---- Final read-back sweep: verify all seeded words -----------------
    $display("[STRESS] Phase 3: read-back sweep of 32 seeded words per slave");
    for (i = 0; i < 32; i = i + 1) begin
      addr = {1'b0, 20'b0, i[7:0], 3'b000};
      do_read(addr, 4'd0, 0, rdata, rresp);
      if (rresp != 2'b00 || rdata !== shadow0[i]) begin
        $display("[STRESS] SWEEP FAIL slave=0 widx=%0d rdata=0x%016x exp=0x%016x rresp=%0b",
                 i, rdata, shadow0[i], rresp);
        err_cnt = err_cnt + 1;
      end
      addr = {1'b1, 20'b0, i[7:0], 3'b000};
      do_read(addr, 4'd1, 0, rdata, rresp);
      if (rresp != 2'b00 || rdata !== shadow1[i]) begin
        $display("[STRESS] SWEEP FAIL slave=1 widx=%0d rdata=0x%016x exp=0x%016x rresp=%0b",
                 i, rdata, shadow1[i], rresp);
        err_cnt = err_cnt + 1;
      end
    end

    // ---- Result ---------------------------------------------------------
    repeat (4) @(posedge ACLK);
    if (err_cnt == 0)
      $display("STRESS PASS: N=%0d WAIT0=%0d WAIT1=%0d BP=%0d SEED=%0d — 0 errors",
               N, WAIT0, WAIT1, BP, SEED);
    else
      $display("STRESS FAIL: %0d errors in %0d transactions (N=%0d SEED=%0d)",
               err_cnt, txn_cnt, N, SEED);
    $finish;
  end

  // ---- Timeout watchdog ------------------------------------------------
  initial begin
    // Evaluated after plusargs are parsed; use a safe upper bound.
    // The TIMEOUT_CYCLES integer is set in main initial block but that races;
    // use a generous fixed upper bound here: 1M cycles covers N=200 easily.
    #10000000;
    $display("[STRESS] TIMEOUT after 10 000 000 ns");
    $finish;
  end

endmodule
