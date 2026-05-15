`timescale 1ns/1ps

// 32×32-bit RW register file with AXI3-Lite slave interface.
// AXI3-Lite = AXI4-Lite + WID on the write-data channel (must equal AWID).
// Address map: REG0–REG31 at byte offsets 0x00–0x7C (stride 4).
// Out-of-range access or WID≠AWID → SLVERR.  All registers reset to 0.
module axi3lite_regblock #(
    parameter ID_WIDTH   = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  wire                      ACLK,
    input  wire                      ARESETn,

    // AW channel
    input  wire [ID_WIDTH-1:0]       S_AXI_AWID,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [ADDR_WIDTH-1:0]     S_AXI_AWADDR,   // bits [1:0] ignored (word-aligned)
    input  wire [2:0]                S_AXI_AWPROT,   // accepted but not decoded
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire                      S_AXI_AWVALID,
    output reg                       S_AXI_AWREADY,

    // W channel (AXI3 adds WID)
    input  wire [ID_WIDTH-1:0]       S_AXI_WID,
    input  wire [DATA_WIDTH-1:0]     S_AXI_WDATA,
    input  wire [(DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input  wire                      S_AXI_WVALID,
    output reg                       S_AXI_WREADY,

    // B channel
    output reg  [ID_WIDTH-1:0]       S_AXI_BID,
    output reg  [1:0]                S_AXI_BRESP,
    output reg                       S_AXI_BVALID,
    input  wire                      S_AXI_BREADY,

    // AR channel
    input  wire [ID_WIDTH-1:0]       S_AXI_ARID,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [ADDR_WIDTH-1:0]     S_AXI_ARADDR,   // bits [1:0] ignored (word-aligned)
    input  wire [2:0]                S_AXI_ARPROT,   // accepted but not decoded
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire                      S_AXI_ARVALID,
    output reg                       S_AXI_ARREADY,

    // R channel
    output reg  [ID_WIDTH-1:0]       S_AXI_RID,
    output reg  [DATA_WIDTH-1:0]     S_AXI_RDATA,
    output reg  [1:0]                S_AXI_RRESP,
    output reg                       S_AXI_RVALID,
    input  wire                      S_AXI_RREADY
);

    // Register file
    reg [DATA_WIDTH-1:0] regfile [0:31];

    // Write path FSM
    localparam WR_IDLE       = 2'd0;
    localparam WR_HAVE_AW    = 2'd1;
    localparam WR_RESP       = 2'd2;

    reg [1:0]            wr_state;
    reg [ID_WIDTH-1:0]   wr_id;
    reg [4:0]            wr_idx;    // register index (bits [6:2] of AWADDR)
    reg                  wr_range;  // 1 = in-range

    // Read path FSM
    localparam RD_IDLE = 1'd0;
    localparam RD_RESP = 1'd1;

    reg                  rd_state;

    integer i;

    // Write FSM
    always @(posedge ACLK) begin
        if (!ARESETn) begin
            wr_state      <= WR_IDLE;
            S_AXI_AWREADY <= 1'b0;
            S_AXI_WREADY  <= 1'b0;
            S_AXI_BVALID  <= 1'b0;
            S_AXI_BID     <= {ID_WIDTH{1'b0}};
            S_AXI_BRESP   <= 2'b00;
            wr_id         <= {ID_WIDTH{1'b0}};
            wr_idx        <= 5'd0;
            wr_range      <= 1'b0;
            for (i = 0; i < 32; i = i + 1)
                regfile[i] <= {DATA_WIDTH{1'b0}};
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    S_AXI_AWREADY <= 1'b1;
                    S_AXI_WREADY  <= 1'b0;
                    if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                        S_AXI_AWREADY <= 1'b0;
                        S_AXI_WREADY  <= 1'b1;
                        wr_id         <= S_AXI_AWID;
                        wr_idx        <= S_AXI_AWADDR[6:2];
                        wr_range      <= (S_AXI_AWADDR[ADDR_WIDTH-1:7] == {(ADDR_WIDTH-7){1'b0}});
                        wr_state      <= WR_HAVE_AW;
                    end
                end

                WR_HAVE_AW: begin
                    if (S_AXI_WVALID && S_AXI_WREADY) begin
                        S_AXI_WREADY <= 1'b0;
                        S_AXI_BVALID <= 1'b1;
                        S_AXI_BID    <= wr_id;
                        if (!wr_range || (S_AXI_WID != wr_id)) begin
                            S_AXI_BRESP <= 2'b10; // SLVERR
                        end else begin
                            S_AXI_BRESP <= 2'b00; // OKAY
                            if (S_AXI_WSTRB[0]) regfile[wr_idx][ 7: 0] <= S_AXI_WDATA[ 7: 0];
                            if (S_AXI_WSTRB[1]) regfile[wr_idx][15: 8] <= S_AXI_WDATA[15: 8];
                            if (S_AXI_WSTRB[2]) regfile[wr_idx][23:16] <= S_AXI_WDATA[23:16];
                            if (S_AXI_WSTRB[3]) regfile[wr_idx][31:24] <= S_AXI_WDATA[31:24];
                        end
                        wr_state <= WR_RESP;
                    end
                end

                WR_RESP: begin
                    if (S_AXI_BVALID && S_AXI_BREADY) begin
                        S_AXI_BVALID <= 1'b0;
                        wr_state     <= WR_IDLE;
                    end
                end

                default: begin /*verilator coverage_block_off*/ wr_state <= WR_IDLE; end
            endcase
        end
    end

    // Read FSM (independent; serialised by ARREADY only in IDLE)
    // RDATA/RRESP/RID are latched at the AR handshake so they are valid the
    // same cycle RVALID asserts (one clock after AR handshake).
    always @(posedge ACLK) begin
        if (!ARESETn) begin
            rd_state      <= RD_IDLE;
            S_AXI_ARREADY <= 1'b0;
            S_AXI_RVALID  <= 1'b0;
            S_AXI_RID     <= {ID_WIDTH{1'b0}};
            S_AXI_RDATA   <= {DATA_WIDTH{1'b0}};
            S_AXI_RRESP   <= 2'b00;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    S_AXI_ARREADY <= 1'b1;
                    if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                        S_AXI_ARREADY <= 1'b0;
                        S_AXI_RID     <= S_AXI_ARID;
                        S_AXI_RVALID  <= 1'b1;
                        if (S_AXI_ARADDR[ADDR_WIDTH-1:7] == {(ADDR_WIDTH-7){1'b0}}) begin
                            S_AXI_RDATA <= regfile[S_AXI_ARADDR[6:2]];
                            S_AXI_RRESP <= 2'b00;
                        end else begin
                            S_AXI_RDATA <= {DATA_WIDTH{1'b0}};
                            S_AXI_RRESP <= 2'b10; // SLVERR
                        end
                        rd_state <= RD_RESP;
                    end
                end

                RD_RESP: begin
                    if (S_AXI_RVALID && S_AXI_RREADY) begin
                        S_AXI_RVALID <= 1'b0;
                        rd_state     <= RD_IDLE;
                    end
                end

                default: begin /*verilator coverage_block_off*/ rd_state <= RD_IDLE; end
            endcase
        end
    end

endmodule
