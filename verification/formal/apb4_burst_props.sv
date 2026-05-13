// apb4_burst_props.sv — SymbiYosys formal wrapper for axi4_to_apb4_2x_burst
//
// Extends the simple-bridge checks with burst-specific properties:
//   P1-P3: APB handshake timing and mutual exclusion (same as simple)
//   P4-P5: BVALID/RVALID deassert after acceptance
//   P6:    BID matches AWID captured at the AW handshake
//   P7:    RID matches ARID captured at the AR handshake
//   P8:    RLAST appears exactly on the final read beat
//   P9:    DECERR reads deliver zero RDATA on every beat
//   P10:   No new AXI transaction accepted while one is in progress
//
// Ghost state tracks the captured ID and beat counters; it does not alter
// the DUT's behaviour — it is only used in assume/assert/cover statements.
//
// Cover goals:
//   - A single-beat write (AWLEN=0) completes with OKAY
//   - A multi-beat write (AWLEN>0) completes with OKAY
//   - A read burst completes: RVALID + RLAST accepted with OKAY
//   - A DECERR write response is issued

`default_nettype none
`timescale 1ns/1ps

module apb4_burst_props #(
    parameter ID_WIDTH     = 4,
    parameter ADDR_WIDTH   = 32,
    parameter DATA_WIDTH   = 64,
    parameter APB_ADDR_BIT = 31
) (
    input wire ACLK,
    input wire ARESETn
);

    // ----------------------------------------------------------------
    // Free variables: AXI master inputs and APB slave responses
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

    wire [ADDR_WIDTH-1:0]     PADDR0, PADDR1;
    wire [2:0]                PPROT0,  PPROT1;
    wire                      PSEL0,   PSEL1;
    wire                      PENABLE0, PENABLE1;
    wire                      PWRITE0, PWRITE1;
    wire [DATA_WIDTH-1:0]     PWDATA0, PWDATA1;
    wire [(DATA_WIDTH/8)-1:0] PSTRB0,  PSTRB1;

    // ----------------------------------------------------------------
    // DUT instantiation
    // ----------------------------------------------------------------
    axi4_to_apb4_2x_burst #(
        .ID_WIDTH     (ID_WIDTH),
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .APB_ADDR_BIT (APB_ADDR_BIT)
    ) u_dut (
        .ACLK          (ACLK),
        .ARESETn       (ARESETn),
        .S_AXI_AWID    (S_AXI_AWID),    .S_AXI_AWADDR  (S_AXI_AWADDR),
        .S_AXI_AWLEN   (S_AXI_AWLEN),   .S_AXI_AWSIZE  (S_AXI_AWSIZE),
        .S_AXI_AWBURST (S_AXI_AWBURST), .S_AXI_AWPROT  (S_AXI_AWPROT),
        .S_AXI_AWVALID (S_AXI_AWVALID), .S_AXI_AWREADY (S_AXI_AWREADY),
        .S_AXI_WDATA   (S_AXI_WDATA),   .S_AXI_WSTRB   (S_AXI_WSTRB),
        .S_AXI_WLAST   (S_AXI_WLAST),   .S_AXI_WVALID  (S_AXI_WVALID),
        .S_AXI_WREADY  (S_AXI_WREADY),
        .S_AXI_BID     (S_AXI_BID),     .S_AXI_BRESP   (S_AXI_BRESP),
        .S_AXI_BVALID  (S_AXI_BVALID),  .S_AXI_BREADY  (S_AXI_BREADY),
        .S_AXI_ARID    (S_AXI_ARID),    .S_AXI_ARADDR  (S_AXI_ARADDR),
        .S_AXI_ARLEN   (S_AXI_ARLEN),   .S_AXI_ARSIZE  (S_AXI_ARSIZE),
        .S_AXI_ARBURST (S_AXI_ARBURST), .S_AXI_ARPROT  (S_AXI_ARPROT),
        .S_AXI_ARVALID (S_AXI_ARVALID), .S_AXI_ARREADY (S_AXI_ARREADY),
        .S_AXI_RID     (S_AXI_RID),     .S_AXI_RDATA   (S_AXI_RDATA),
        .S_AXI_RRESP   (S_AXI_RRESP),   .S_AXI_RLAST   (S_AXI_RLAST),
        .S_AXI_RVALID  (S_AXI_RVALID),  .S_AXI_RREADY  (S_AXI_RREADY),
        .PADDR0        (PADDR0),         .PPROT0        (PPROT0),
        .PSEL0         (PSEL0),          .PENABLE0      (PENABLE0),
        .PWRITE0       (PWRITE0),        .PWDATA0       (PWDATA0),
        .PSTRB0        (PSTRB0),         .PRDATA0       (PRDATA0),
        .PREADY0       (PREADY0),        .PSLVERR0      (PSLVERR0),
        .PADDR1        (PADDR1),         .PPROT1        (PPROT1),
        .PSEL1         (PSEL1),          .PENABLE1      (PENABLE1),
        .PWRITE1       (PWRITE1),        .PWDATA1       (PWDATA1),
        .PSTRB1        (PSTRB1),         .PRDATA1       (PRDATA1),
        .PREADY1       (PREADY1),        .PSLVERR1      (PSLVERR1)
    );

    // ----------------------------------------------------------------
    // Formal infrastructure
    // ----------------------------------------------------------------
    reg f_past_valid;
    initial f_past_valid = 1'b0;
    always @(posedge ACLK) f_past_valid <= 1'b1;

    always @(*) if (!f_past_valid) assume (!ARESETn);

    // AXI AW/AR/W stability: once VALID is raised it must hold until READY,
    // and the control payload must not change.
    always @(posedge ACLK) begin
        if (f_past_valid && $past(ARESETn)) begin
            if ($past(S_AXI_AWVALID) && !$past(S_AXI_AWREADY))
                assume (S_AXI_AWVALID &&
                        S_AXI_AWID    == $past(S_AXI_AWID)    &&
                        S_AXI_AWADDR  == $past(S_AXI_AWADDR)  &&
                        S_AXI_AWLEN   == $past(S_AXI_AWLEN)   &&
                        S_AXI_AWSIZE  == $past(S_AXI_AWSIZE)  &&
                        S_AXI_AWBURST == $past(S_AXI_AWBURST));
            if ($past(S_AXI_ARVALID) && !$past(S_AXI_ARREADY))
                assume (S_AXI_ARVALID &&
                        S_AXI_ARID    == $past(S_AXI_ARID)    &&
                        S_AXI_ARADDR  == $past(S_AXI_ARADDR)  &&
                        S_AXI_ARLEN   == $past(S_AXI_ARLEN)   &&
                        S_AXI_ARSIZE  == $past(S_AXI_ARSIZE)  &&
                        S_AXI_ARBURST == $past(S_AXI_ARBURST));
            if ($past(S_AXI_WVALID) && !$past(S_AXI_WREADY))
                assume (S_AXI_WVALID &&
                        S_AXI_WDATA == $past(S_AXI_WDATA) &&
                        S_AXI_WSTRB == $past(S_AXI_WSTRB) &&
                        S_AXI_WLAST == $past(S_AXI_WLAST));
        end
    end

    // Constrain AWSIZE and ARSIZE to the legal value for DATA_WIDTH=64 so
    // the BMC explores legal transactions (3'b011 = 8-byte transfers).
    localparam [2:0] LEGAL_SIZE = 3'b011;
    always @(*) begin
        assume (S_AXI_AWSIZE == LEGAL_SIZE);
        assume (S_AXI_ARSIZE == LEGAL_SIZE);
        // Constrain burst type to FIXED or INCR (no WRAP in this bridge)
        assume (S_AXI_AWBURST <= 2'b01);
        assume (S_AXI_ARBURST <= 2'b01);
        // Constrain burst length to <=3 beats so a full transaction can
        // complete within the BMC depth.
        assume (S_AXI_AWLEN <= 8'd3);
        assume (S_AXI_ARLEN <= 8'd3);
    end

    // ----------------------------------------------------------------
    // Ghost state: capture IDs and beat counts at handshake
    // ----------------------------------------------------------------

    // Write ID and length tracking
    reg [ID_WIDTH-1:0] f_wr_id;
    reg [7:0]          f_wr_awlen;   // AWLEN captured at AW handshake
    reg                f_wr_id_live; // set at AW handshake, clear cycle AFTER B acceptance

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            f_wr_id      <= '0;
            f_wr_awlen   <= '0;
            f_wr_id_live <= 1'b0;
        end else begin
            if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                f_wr_id      <= S_AXI_AWID;
                f_wr_awlen   <= S_AXI_AWLEN;
                f_wr_id_live <= 1'b1;
            end
            if (S_AXI_BVALID && S_AXI_BREADY)
                f_wr_id_live <= 1'b0;
        end
    end

    // Read ID and beat tracking
    reg [ID_WIDTH-1:0] f_rd_id;
    reg                f_rd_id_live;  // set at AR handshake, clear after RLAST
    reg [7:0]          f_rd_arlen;    // ARLEN captured at handshake
    reg [8:0]          f_rd_beats;    // R beats accepted so far (including current)

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            f_rd_id      <= '0;
            f_rd_id_live <= 1'b0;
            f_rd_arlen   <= '0;
            f_rd_beats   <= '0;
        end else begin
            if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                f_rd_id      <= S_AXI_ARID;
                f_rd_id_live <= 1'b1;
                f_rd_arlen   <= S_AXI_ARLEN;
                f_rd_beats   <= '0;
            end
            if (S_AXI_RVALID && S_AXI_RREADY) begin
                f_rd_beats <= f_rd_beats + 9'd1;
                if (S_AXI_RLAST) f_rd_id_live <= 1'b0;
            end
        end
    end

    // ----------------------------------------------------------------
    // Properties
    // ----------------------------------------------------------------
    always @(posedge ACLK) begin
        if (f_past_valid && $past(ARESETn) && ARESETn) begin

            // P1: APB setup phase lasts exactly 1 cycle.
            if ($past(PSEL0) && !$past(PENABLE0)) assert (PENABLE0);
            if ($past(PSEL1) && !$past(PENABLE1)) assert (PENABLE1);

            // P2: APB transaction completes cleanly.
            if ($past(PSEL0) && $past(PENABLE0) && $past(PREADY0))
                assert (!PSEL0 && !PENABLE0);
            if ($past(PSEL1) && $past(PENABLE1) && $past(PREADY1))
                assert (!PSEL1 && !PENABLE1);

            // P3: Mutual exclusion — at most one APB port active.
            assert (!(PSEL0    && PSEL1));
            assert (!(PENABLE0 && PENABLE1));

            // P4: BVALID deasserts the cycle after it is accepted.
            if ($past(S_AXI_BVALID) && $past(S_AXI_BREADY))
                assert (!S_AXI_BVALID);

            // P5: RVALID deasserts the cycle after a beat is accepted.
            if ($past(S_AXI_RVALID) && $past(S_AXI_RREADY))
                assert (!S_AXI_RVALID);

            // P6: BID matches the AWID captured at the AW handshake.
            if (f_wr_id_live && S_AXI_BVALID)
                assert (S_AXI_BID == f_wr_id);

            // P7: RID matches the ARID captured at the AR handshake.
            if (f_rd_id_live && S_AXI_RVALID)
                assert (S_AXI_RID == f_rd_id);

            // P8: RLAST is asserted on the (ARLEN+1)th beat and only then.
            if (f_rd_id_live && S_AXI_RVALID) begin
                // On the last beat RLAST must be high.
                if (f_rd_beats == {1'b0, f_rd_arlen})
                    assert (S_AXI_RLAST);
                // Before the last beat RLAST must be low.
                if (f_rd_beats < {1'b0, f_rd_arlen})
                    assert (!S_AXI_RLAST);
            end

            // P9: DECERR reads deliver zero RDATA on every beat.
            if (f_rd_id_live && S_AXI_RVALID && (S_AXI_RRESP == 2'b11))
                assert (S_AXI_RDATA == {DATA_WIDTH{1'b0}});

            // P10: No new AW or AR handshake while a response is outstanding.
            //      (The bridge is single-transaction; AWREADY/ARREADY are 0
            //       while BVALID or RVALID is asserted.)
            if (S_AXI_BVALID || S_AXI_RVALID) begin
                assert (!S_AXI_AWREADY);
                assert (!S_AXI_ARREADY);
            end

        end
    end

    // ----------------------------------------------------------------
    // Cover goals
    // Note: f_wr_id_live / f_rd_id_live clear one cycle AFTER the handshake
    // (registered), so cover goals check the handshake cycle directly.
    // ----------------------------------------------------------------
    always @(posedge ACLK) begin
        if (f_past_valid && ARESETn) begin
            // A single-beat write (AWLEN=0) completes with OKAY.
            cover (S_AXI_BVALID && S_AXI_BREADY &&
                   (S_AXI_BRESP == 2'b00) && (f_wr_awlen == 8'd0));

            // A multi-beat INCR write (AWLEN>0) completes with OKAY.
            cover (S_AXI_BVALID && S_AXI_BREADY &&
                   (S_AXI_BRESP == 2'b00) && (f_wr_awlen > 8'd0));

            // A read burst completes: RVALID + RLAST accepted with OKAY.
            cover (S_AXI_RVALID && S_AXI_RLAST && S_AXI_RREADY &&
                   (S_AXI_RRESP == 2'b00));

            // A DECERR write response is issued.
            cover (S_AXI_BVALID && S_AXI_BREADY && (S_AXI_BRESP == 2'b11));
        end
    end

endmodule
`default_nettype wire
