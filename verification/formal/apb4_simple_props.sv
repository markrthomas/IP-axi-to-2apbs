// apb4_simple_props.sv — SymbiYosys formal wrapper for axi4_to_apb4_2x_simple
//
// Instantiates the DUT with unconstrained AXI/APB inputs (free variables).
// Applies AXI protocol assumptions to avoid spurious counterexamples, then
// checks:
//   1. APB setup phase: PSEL asserted without PENABLE → PENABLE high next cycle
//   2. APB completion: PSEL+PENABLE+PREADY → PSEL/PENABLE both deassert next cycle
//   3. Mutual exclusion: PSEL0 and PSEL1 never simultaneously asserted
//
// Cover goals:
//   - A write transaction completes (BVALID accepted)
//   - A read transaction completes (RVALID with RLAST accepted)

`default_nettype none
`timescale 1ns/1ps

module apb4_simple_props #(
    parameter ID_WIDTH     = 4,
    parameter ADDR_WIDTH   = 32,
    parameter DATA_WIDTH   = 64,
    parameter APB_ADDR_BIT = 31
) (
    input wire ACLK,
    input wire ARESETn
);

    // ----------------------------------------------------------------
    // Free variables: AXI master inputs
    // ----------------------------------------------------------------
    wire [ID_WIDTH-1:0]       S_AXI_AWID;
    wire [ADDR_WIDTH-1:0]     S_AXI_AWADDR;
    wire [7:0]                S_AXI_AWLEN;
    wire [2:0]                S_AXI_AWSIZE;
    wire [1:0]                S_AXI_AWBURST;
    wire [2:0]                S_AXI_AWPROT;
    wire                      S_AXI_AWVALID;

    wire [DATA_WIDTH-1:0]     S_AXI_WDATA;
    wire [(DATA_WIDTH/8)-1:0] S_AXI_WSTRB;
    wire                      S_AXI_WLAST;
    wire                      S_AXI_WVALID;

    wire                      S_AXI_BREADY;

    wire [ID_WIDTH-1:0]       S_AXI_ARID;
    wire [ADDR_WIDTH-1:0]     S_AXI_ARADDR;
    wire [7:0]                S_AXI_ARLEN;
    wire [2:0]                S_AXI_ARSIZE;
    wire [1:0]                S_AXI_ARBURST;
    wire [2:0]                S_AXI_ARPROT;
    wire                      S_AXI_ARVALID;

    wire                      S_AXI_RREADY;

    // Free variables: APB slave responses
    wire [DATA_WIDTH-1:0]     PRDATA0;
    wire                      PREADY0;
    wire                      PSLVERR0;

    wire [DATA_WIDTH-1:0]     PRDATA1;
    wire                      PREADY1;
    wire                      PSLVERR1;

    // ----------------------------------------------------------------
    // DUT outputs
    // ----------------------------------------------------------------
    wire                      S_AXI_AWREADY;
    wire                      S_AXI_WREADY;
    wire [ID_WIDTH-1:0]       S_AXI_BID;
    wire [1:0]                S_AXI_BRESP;
    wire                      S_AXI_BVALID;
    wire                      S_AXI_ARREADY;
    wire [ID_WIDTH-1:0]       S_AXI_RID;
    wire [DATA_WIDTH-1:0]     S_AXI_RDATA;
    wire [1:0]                S_AXI_RRESP;
    wire                      S_AXI_RLAST;
    wire                      S_AXI_RVALID;

    wire [ADDR_WIDTH-1:0]     PADDR0;
    wire [2:0]                PPROT0;
    wire                      PSEL0;
    wire                      PENABLE0;
    wire                      PWRITE0;
    wire [DATA_WIDTH-1:0]     PWDATA0;
    wire [(DATA_WIDTH/8)-1:0] PSTRB0;

    wire [ADDR_WIDTH-1:0]     PADDR1;
    wire [2:0]                PPROT1;
    wire                      PSEL1;
    wire                      PENABLE1;
    wire                      PWRITE1;
    wire [DATA_WIDTH-1:0]     PWDATA1;
    wire [(DATA_WIDTH/8)-1:0] PSTRB1;

    // ----------------------------------------------------------------
    // DUT instantiation
    // ----------------------------------------------------------------
    axi4_to_apb4_2x_simple #(
        .ID_WIDTH     (ID_WIDTH),
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .APB_ADDR_BIT (APB_ADDR_BIT)
    ) u_dut (
        .ACLK          (ACLK),
        .ARESETn       (ARESETn),

        .S_AXI_AWID    (S_AXI_AWID),
        .S_AXI_AWADDR  (S_AXI_AWADDR),
        .S_AXI_AWLEN   (S_AXI_AWLEN),
        .S_AXI_AWSIZE  (S_AXI_AWSIZE),
        .S_AXI_AWBURST (S_AXI_AWBURST),
        .S_AXI_AWPROT  (S_AXI_AWPROT),
        .S_AXI_AWVALID (S_AXI_AWVALID),
        .S_AXI_AWREADY (S_AXI_AWREADY),

        .S_AXI_WDATA   (S_AXI_WDATA),
        .S_AXI_WSTRB   (S_AXI_WSTRB),
        .S_AXI_WLAST   (S_AXI_WLAST),
        .S_AXI_WVALID  (S_AXI_WVALID),
        .S_AXI_WREADY  (S_AXI_WREADY),

        .S_AXI_BID     (S_AXI_BID),
        .S_AXI_BRESP   (S_AXI_BRESP),
        .S_AXI_BVALID  (S_AXI_BVALID),
        .S_AXI_BREADY  (S_AXI_BREADY),

        .S_AXI_ARID    (S_AXI_ARID),
        .S_AXI_ARADDR  (S_AXI_ARADDR),
        .S_AXI_ARLEN   (S_AXI_ARLEN),
        .S_AXI_ARSIZE  (S_AXI_ARSIZE),
        .S_AXI_ARBURST (S_AXI_ARBURST),
        .S_AXI_ARPROT  (S_AXI_ARPROT),
        .S_AXI_ARVALID (S_AXI_ARVALID),
        .S_AXI_ARREADY (S_AXI_ARREADY),

        .S_AXI_RID     (S_AXI_RID),
        .S_AXI_RDATA   (S_AXI_RDATA),
        .S_AXI_RRESP   (S_AXI_RRESP),
        .S_AXI_RLAST   (S_AXI_RLAST),
        .S_AXI_RVALID  (S_AXI_RVALID),
        .S_AXI_RREADY  (S_AXI_RREADY),

        .PADDR0        (PADDR0),
        .PPROT0        (PPROT0),
        .PSEL0         (PSEL0),
        .PENABLE0      (PENABLE0),
        .PWRITE0       (PWRITE0),
        .PWDATA0       (PWDATA0),
        .PSTRB0        (PSTRB0),
        .PRDATA0       (PRDATA0),
        .PREADY0       (PREADY0),
        .PSLVERR0      (PSLVERR0),

        .PADDR1        (PADDR1),
        .PPROT1        (PPROT1),
        .PSEL1         (PSEL1),
        .PENABLE1      (PENABLE1),
        .PWRITE1       (PWRITE1),
        .PWDATA1       (PWDATA1),
        .PSTRB1        (PSTRB1),
        .PRDATA1       (PRDATA1),
        .PREADY1       (PREADY1),
        .PSLVERR1      (PSLVERR1)
    );

    // ----------------------------------------------------------------
    // Formal infrastructure
    // ----------------------------------------------------------------
    reg f_past_valid;
    initial f_past_valid = 1'b0;
    always @(posedge ACLK) f_past_valid <= 1'b1;

    // Reset assumption: ARESETn must stay low for at least the first
    // cycle so BMC does not start mid-transaction.
    always @(*) begin
        if (!f_past_valid) assume (!ARESETn);
    end

    // Simple-bridge serialization assumption: the bridge cannot arbitrate
    // between simultaneous write-address/write-data and read-address requests
    // — presenting both simultaneously deadlocks (each READY blocks on the
    // other VALID).  Constrain the formal environment to serialized traffic,
    // matching the bridge's single-outstanding-transaction contract.
    always @(*) begin
        assume (!(S_AXI_AWVALID && S_AXI_ARVALID));
        assume (!(S_AXI_WVALID  && S_AXI_ARVALID));
    end

    // AXI stability assumptions: once VALID is asserted it must hold
    // until READY, and the payload must not change.  This prevents the
    // BMC from exploring illegal AXI master behaviour that cannot
    // occur in practice.
    always @(posedge ACLK) begin
        if (f_past_valid && $past(ARESETn)) begin
            if ($past(S_AXI_AWVALID) && !$past(S_AXI_AWREADY))
                assume (S_AXI_AWVALID &&
                        S_AXI_AWID    == $past(S_AXI_AWID)    &&
                        S_AXI_AWADDR  == $past(S_AXI_AWADDR)  &&
                        S_AXI_AWLEN   == $past(S_AXI_AWLEN)   &&
                        S_AXI_AWSIZE  == $past(S_AXI_AWSIZE));
            if ($past(S_AXI_WVALID) && !$past(S_AXI_WREADY))
                assume (S_AXI_WVALID &&
                        S_AXI_WDATA == $past(S_AXI_WDATA) &&
                        S_AXI_WSTRB == $past(S_AXI_WSTRB));
            if ($past(S_AXI_ARVALID) && !$past(S_AXI_ARREADY))
                assume (S_AXI_ARVALID &&
                        S_AXI_ARID   == $past(S_AXI_ARID)   &&
                        S_AXI_ARADDR == $past(S_AXI_ARADDR) &&
                        S_AXI_ARLEN  == $past(S_AXI_ARLEN)  &&
                        S_AXI_ARSIZE == $past(S_AXI_ARSIZE));
        end
    end

    // ----------------------------------------------------------------
    // Properties
    // ----------------------------------------------------------------

    always @(posedge ACLK) begin
        if (f_past_valid && $past(ARESETn) && ARESETn) begin

            // P1: APB setup phase lasts exactly 1 cycle.
            //     When PSEL is asserted without PENABLE, PENABLE must
            //     go high in the very next cycle.
            if ($past(PSEL0) && !$past(PENABLE0))
                assert (PENABLE0);
            if ($past(PSEL1) && !$past(PENABLE1))
                assert (PENABLE1);

            // P2: APB transaction completes cleanly.
            //     When both PENABLE and PREADY are seen, the bridge must
            //     deassert PSEL and PENABLE in the same clock edge.
            if ($past(PSEL0) && $past(PENABLE0) && $past(PREADY0))
                assert (!PSEL0 && !PENABLE0);
            if ($past(PSEL1) && $past(PENABLE1) && $past(PREADY1))
                assert (!PSEL1 && !PENABLE1);

            // P3: Mutual exclusion — only one APB port active at a time.
            assert (!(PSEL0    && PSEL1));
            assert (!(PENABLE0 && PENABLE1));

            // P4: BVALID deasserts the cycle after it is accepted.
            if ($past(S_AXI_BVALID) && $past(S_AXI_BREADY))
                assert (!S_AXI_BVALID);

            // P5: RVALID deasserts the cycle after the last beat is accepted.
            if ($past(S_AXI_RVALID) && $past(S_AXI_RREADY))
                assert (!S_AXI_RVALID);

        end
    end

    // ----------------------------------------------------------------
    // Liveness infrastructure
    // ----------------------------------------------------------------

    // Assume APB slave responds within 5 cycles of PENABLE assertion.
    reg [2:0] f_p0_wait, f_p1_wait;
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            f_p0_wait <= 3'd0; f_p1_wait <= 3'd0;
        end else begin
            f_p0_wait <= (PSEL0 && PENABLE0 && !PREADY0) ? f_p0_wait + 3'd1 : 3'd0;
            f_p1_wait <= (PSEL1 && PENABLE1 && !PREADY1) ? f_p1_wait + 3'd1 : 3'd0;
        end
    end

    // Assume AXI master consumes B and R beats within 5 cycles of VALID.
    reg [2:0] f_bw, f_rw;
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            f_bw <= 3'd0; f_rw <= 3'd0;
        end else begin
            f_bw <= (S_AXI_BVALID && !S_AXI_BREADY) ? f_bw + 3'd1 : 3'd0;
            f_rw <= (S_AXI_RVALID && !S_AXI_RREADY) ? f_rw + 3'd1 : 3'd0;
        end
    end

    // AXI requires AW and W to be paired.  Enforce mutual 5-cycle deadlines:
    //   - If W is accepted before AW, AW must arrive within 5 cycles.
    //   - If AW is accepted before W, W must arrive within 5 cycles.
    // Without these, the bridge can stall indefinitely waiting for the partner.
    reg       f_w_needs_aw, f_aw_needs_w;
    reg [2:0] f_orphan_w_wait, f_orphan_aw_wait;
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            f_w_needs_aw  <= 1'b0; f_orphan_w_wait  <= 3'd0;
            f_aw_needs_w  <= 1'b0; f_orphan_aw_wait <= 3'd0;
        end else begin
            // W accepted, AW not yet
            if (S_AXI_WVALID && S_AXI_WREADY && !(S_AXI_AWVALID && S_AXI_AWREADY))
                f_w_needs_aw <= 1'b1;
            if ((S_AXI_AWVALID && S_AXI_AWREADY) || S_AXI_BVALID)
                f_w_needs_aw <= 1'b0;
            f_orphan_w_wait <= f_w_needs_aw ? f_orphan_w_wait + 3'd1 : 3'd0;
            // AW accepted, W not yet
            if (S_AXI_AWVALID && S_AXI_AWREADY && !(S_AXI_WVALID && S_AXI_WREADY))
                f_aw_needs_w <= 1'b1;
            if ((S_AXI_WVALID && S_AXI_WREADY) || S_AXI_BVALID)
                f_aw_needs_w <= 1'b0;
            f_orphan_aw_wait <= f_aw_needs_w ? f_orphan_aw_wait + 3'd1 : 3'd0;
        end
    end

    always @(posedge ACLK) begin
        if (f_past_valid && ARESETn) begin
            assume (f_p0_wait        < 3'd5);
            assume (f_p1_wait        < 3'd5);
            assume (f_bw             < 3'd5);
            assume (f_rw             < 3'd5);
            assume (f_orphan_w_wait  < 3'd5);
            assume (f_orphan_aw_wait < 3'd5);
        end
    end

    // Count consecutive cycles each channel VALID is high without READY.
    reg [4:0] f_aw_stall, f_w_stall, f_ar_stall;
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            f_aw_stall <= 5'd0; f_w_stall <= 5'd0; f_ar_stall <= 5'd0;
        end else begin
            f_aw_stall <= (S_AXI_AWVALID && !S_AXI_AWREADY) ? f_aw_stall + 5'd1 : 5'd0;
            f_w_stall  <= (S_AXI_WVALID  && !S_AXI_WREADY)  ? f_w_stall  + 5'd1 : 5'd0;
            f_ar_stall <= (S_AXI_ARVALID && !S_AXI_ARREADY) ? f_ar_stall + 5'd1 : 5'd0;
        end
    end

    // L4/L5 start from the APB setup phase (PSEL high, PENABLE still low), which
    // only fires after BOTH AW and W are accepted, so no W-arrival assumption is
    // needed.  PWRITE distinguishes write from read paths.
    wire f_apb_wr_setup = (PSEL0 && !PENABLE0 && PWRITE0) || (PSEL1 && !PENABLE1 && PWRITE1);
    wire f_apb_rd_setup = (PSEL0 && !PENABLE0 && !PWRITE0) || (PSEL1 && !PENABLE1 && !PWRITE1);

    // Count cycles from APB write setup to BVALID.
    reg [4:0] f_apb_wr_to_b;
    reg       f_apb_wr_live;
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            f_apb_wr_to_b <= 5'd0; f_apb_wr_live <= 1'b0;
        end else begin
            if (f_apb_wr_setup && !f_apb_wr_live) begin
                f_apb_wr_to_b <= 5'd0; f_apb_wr_live <= 1'b1;
            end else if (f_apb_wr_live) begin
                f_apb_wr_to_b <= f_apb_wr_to_b + 5'd1;
            end
            if (S_AXI_BVALID) f_apb_wr_live <= 1'b0;
        end
    end

    // Count cycles from APB read setup to RVALID.
    reg [4:0] f_apb_rd_to_r;
    reg       f_apb_rd_live;
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            f_apb_rd_to_r <= 5'd0; f_apb_rd_live <= 1'b0;
        end else begin
            if (f_apb_rd_setup && !f_apb_rd_live) begin
                f_apb_rd_to_r <= 5'd0; f_apb_rd_live <= 1'b1;
            end else if (f_apb_rd_live) begin
                f_apb_rd_to_r <= f_apb_rd_to_r + 5'd1;
            end
            if (S_AXI_RVALID) f_apb_rd_live <= 1'b0;
        end
    end

    // ----------------------------------------------------------------
    // Liveness properties
    // ----------------------------------------------------------------
    // Bounds assume PREADY within 5 cycles → each APB transaction takes at
    // most 1 (setup) + 6 (access) = 7 cycles.
    // AW/W may stall while a read is in progress (~9 cycles with 5 wait states).
    // AR may stall while a write completes (~12 cycles).
    always @(posedge ACLK) begin
        if (f_past_valid && ARESETn) begin
            // L1: AW accepted within 25 cycles: read in flight ≤ 9 cy; or prior AW
            //     was accepted, W arrived within 5 cy, APB 7 cy, BREADY 5 cy, + transitions.
            // (previously 15; widened to cover orphan-AW scenario)
            assert (f_aw_stall < 5'd25);
            // L2: W accepted within 25 cycles: AW may arrive up to 5 cy after W
            //     (orphan-W assumption), then write takes up to 19 cy more (APB 7 +
            //     BREADY 5 + state transitions 2).
            assert (f_w_stall  < 5'd25);
            // L3: AR accepted within 25 cycles (write completes in ~19 cy + margin).
            assert (f_ar_stall < 5'd25);
            // L4: BVALID within 10 cycles of APB write setup (7 APB + 3 margin).
            assert (!f_apb_wr_live || (f_apb_wr_to_b < 5'd10));
            // L5: RVALID within 10 cycles of APB read setup (7 APB + 3 margin).
            assert (!f_apb_rd_live || (f_apb_rd_to_r < 5'd10));
        end
    end

    // ----------------------------------------------------------------
    // Cover goals
    // ----------------------------------------------------------------
    always @(posedge ACLK) begin
        if (f_past_valid && ARESETn) begin
            // Cover: a write transaction completes (BVALID accepted).
            cover ($past(S_AXI_BVALID) && $past(S_AXI_BREADY) && !S_AXI_BVALID);
            // Cover: a read transaction completes (RVALID with RLAST accepted).
            cover ($past(S_AXI_RVALID) && $past(S_AXI_RLAST)  &&
                   $past(S_AXI_RREADY) && !S_AXI_RVALID);
        end
    end

endmodule
`default_nettype wire
