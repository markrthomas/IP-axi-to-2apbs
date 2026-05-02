`timescale 1ns/1ps

module axi4_to_apb4_2x_burst #(
    parameter ID_WIDTH     = 4,
    parameter ADDR_WIDTH   = 32,
    parameter DATA_WIDTH   = 64,
    parameter APB_ADDR_BIT = 31
)(
    input  wire                      ACLK,
    input  wire                      ARESETn,

    // AXI4 slave interface
    input  wire [ID_WIDTH-1:0]       S_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0]     S_AXI_AWADDR,
    input  wire [7:0]                S_AXI_AWLEN,
    input  wire [2:0]                S_AXI_AWSIZE,
    input  wire [1:0]                S_AXI_AWBURST,
    input  wire [2:0]                S_AXI_AWPROT,
    input  wire                      S_AXI_AWVALID,
    output reg                       S_AXI_AWREADY,

    input  wire [DATA_WIDTH-1:0]     S_AXI_WDATA,
    input  wire [(DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input  wire                      S_AXI_WLAST,
    input  wire                      S_AXI_WVALID,
    output reg                       S_AXI_WREADY,

    output reg  [ID_WIDTH-1:0]       S_AXI_BID,
    output reg  [1:0]                S_AXI_BRESP,
    output reg                       S_AXI_BVALID,
    input  wire                      S_AXI_BREADY,

    input  wire [ID_WIDTH-1:0]       S_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0]     S_AXI_ARADDR,
    input  wire [7:0]                S_AXI_ARLEN,
    input  wire [2:0]                S_AXI_ARSIZE,
    input  wire [1:0]                S_AXI_ARBURST,
    input  wire [2:0]                S_AXI_ARPROT,
    input  wire                      S_AXI_ARVALID,
    output reg                       S_AXI_ARREADY,

    output reg  [ID_WIDTH-1:0]       S_AXI_RID,
    output reg  [DATA_WIDTH-1:0]     S_AXI_RDATA,
    output reg  [1:0]                S_AXI_RRESP,
    output reg                       S_AXI_RLAST,
    output reg                       S_AXI_RVALID,
    input  wire                      S_AXI_RREADY,

    // APB4 master interface 0
    output reg  [ADDR_WIDTH-1:0]     PADDR0,
    output reg  [2:0]                PPROT0,
    output reg                       PSEL0,
    output reg                       PENABLE0,
    output reg                       PWRITE0,
    output reg  [DATA_WIDTH-1:0]     PWDATA0,
    output reg  [(DATA_WIDTH/8)-1:0] PSTRB0,
    input  wire [DATA_WIDTH-1:0]     PRDATA0,
    input  wire                      PREADY0,
    input  wire                      PSLVERR0,

    // APB4 master interface 1
    output reg  [ADDR_WIDTH-1:0]     PADDR1,
    output reg  [2:0]                PPROT1,
    output reg                       PSEL1,
    output reg                       PENABLE1,
    output reg                       PWRITE1,
    output reg  [DATA_WIDTH-1:0]     PWDATA1,
    output reg  [(DATA_WIDTH/8)-1:0] PSTRB1,
    input  wire [DATA_WIDTH-1:0]     PRDATA1,
    input  wire                      PREADY1,
    input  wire                      PSLVERR1
);

    localparam EXPECTED_AXSIZE = (DATA_WIDTH == 1024) ? 3'b111 :
                                 (DATA_WIDTH == 512)  ? 3'b110 :
                                 (DATA_WIDTH == 256)  ? 3'b101 :
                                 (DATA_WIDTH == 128)  ? 3'b100 :
                                 (DATA_WIDTH == 64)   ? 3'b011 :
                                 (DATA_WIDTH == 32)   ? 3'b010 :
                                 (DATA_WIDTH == 16)   ? 3'b001 :
                                 3'b000;

    reg [ID_WIDTH-1:0]           axi_id_reg;
    reg [ADDR_WIDTH-1:0]         axi_addr_reg;
    reg [2:0]                    axi_prot_reg;
    reg [2:0]                    axi_size_reg;
    reg [1:0]                    axi_burst_reg;
    reg [8:0]                    beat_index;
    reg [8:0]                    beats_sent;
    reg [8:0]                    beats_total;
    reg                          axi_is_write;
    reg                          axi_sel_apb1;
    reg                          txn_active;
    reg                          txn_decerr;
    reg                          pslverr_acc;
    reg                          wlast_err;

    reg [DATA_WIDTH-1:0]         rdata_fifo;
    reg [1:0]                    rresp_fifo;
    reg                          rfifo_valid;

    localparam APB_IDLE   = 2'd0;
    localparam APB_SETUP  = 2'd1;
    localparam APB_ACCESS = 2'd2;

    reg [1:0] apb_state;

    wire [ADDR_WIDTH-1:0] addr_incr = axi_addr_reg + (1 << axi_size_reg);

    wire [ADDR_WIDTH-1:0] aw_max_offset = {{ (ADDR_WIDTH-8){1'b0} }, S_AXI_AWLEN} << S_AXI_AWSIZE;
    wire [ADDR_WIDTH-1:0] ar_max_offset = {{ (ADDR_WIDTH-8){1'b0} }, S_AXI_ARLEN} << S_AXI_ARSIZE;
    wire [ADDR_WIDTH-1:0] aw_last_addr = S_AXI_AWADDR + aw_max_offset;
    wire [ADDR_WIDTH-1:0] ar_last_addr = S_AXI_ARADDR + ar_max_offset;

    wire aw_cross_apb = (S_AXI_AWBURST == 2'b01) && (S_AXI_AWADDR[APB_ADDR_BIT] ^ aw_last_addr[APB_ADDR_BIT]);
    wire ar_cross_apb = (S_AXI_ARBURST == 2'b01) && (S_AXI_ARADDR[APB_ADDR_BIT] ^ ar_last_addr[APB_ADDR_BIT]);

    wire aw_param_err = (S_AXI_AWSIZE != EXPECTED_AXSIZE) || (S_AXI_AWBURST > 2'b01) || aw_cross_apb;
    wire ar_param_err = (S_AXI_ARSIZE != EXPECTED_AXSIZE) || (S_AXI_ARBURST > 2'b01) || ar_cross_apb;

    wire busy_with_resp = S_AXI_BVALID || S_AXI_RVALID;
    wire idle_for_new   = !txn_active && !busy_with_resp && (apb_state == APB_IDLE);

    always @(*) begin
        S_AXI_AWREADY = idle_for_new && !S_AXI_ARVALID;
        S_AXI_ARREADY = idle_for_new && !S_AXI_AWVALID;
        if (txn_active && axi_is_write && (beat_index < beats_total)) begin
            if (txn_decerr) S_AXI_WREADY = 1'b1;
            else            S_AXI_WREADY = (apb_state == APB_IDLE);
        end else begin
            S_AXI_WREADY = 1'b0;
        end
    end

    wire aw_handshake = S_AXI_AWVALID && S_AXI_AWREADY;
    wire ar_handshake = S_AXI_ARVALID && S_AXI_ARREADY;
    wire w_handshake  = S_AXI_WVALID  && S_AXI_WREADY;

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            txn_active  <= 1'b0;
            beat_index  <= 9'd0;
            beats_sent  <= 9'd0;
            beats_total <= 9'd0;
            txn_decerr  <= 1'b0;
            pslverr_acc <= 1'b0;
            wlast_err   <= 1'b0;
            rfifo_valid <= 1'b0;
        end else begin
            if (aw_handshake) begin
                axi_id_reg    <= S_AXI_AWID;
                axi_addr_reg  <= S_AXI_AWADDR;
                axi_prot_reg  <= S_AXI_AWPROT;
                axi_size_reg  <= S_AXI_AWSIZE;
                axi_burst_reg <= S_AXI_AWBURST;
                beats_total   <= S_AXI_AWLEN + 1;
                beat_index    <= 9'd0;
                beats_sent    <= 9'd0;
                axi_is_write  <= 1'b1;
                axi_sel_apb1  <= S_AXI_AWADDR[APB_ADDR_BIT];
                txn_active    <= 1'b1;
                txn_decerr    <= aw_param_err;
                pslverr_acc   <= 1'b0;
                wlast_err     <= 1'b0;
            end else if (ar_handshake) begin
                axi_id_reg    <= S_AXI_ARID;
                axi_addr_reg  <= S_AXI_ARADDR;
                axi_prot_reg  <= S_AXI_ARPROT;
                axi_size_reg  <= S_AXI_ARSIZE;
                axi_burst_reg <= S_AXI_ARBURST;
                beats_total   <= S_AXI_ARLEN + 1;
                beat_index    <= 9'd0;
                beats_sent    <= 9'd0;
                axi_is_write  <= 1'b0;
                axi_sel_apb1  <= S_AXI_ARADDR[APB_ADDR_BIT];
                txn_active    <= 1'b1;
                txn_decerr    <= ar_param_err;
                pslverr_acc   <= 1'b0;
                wlast_err     <= 1'b0;
                rfifo_valid   <= 1'b0;
            end

            if (w_handshake && txn_active && axi_is_write) begin
                if (S_AXI_WLAST != (beat_index == beats_total - 1)) wlast_err <= 1'b1;
                if (txn_decerr) beat_index <= beat_index + 1;
            end

            if (apb_state == APB_ACCESS) begin
                if (axi_sel_apb1 ? PREADY1 : PREADY0) begin
                    if (axi_sel_apb1 ? PSLVERR1 : PSLVERR0) pslverr_acc <= 1'b1;
                    if (!axi_is_write) begin
                        rdata_fifo  <= axi_sel_apb1 ? PRDATA1 : PRDATA0;
                        rresp_fifo  <= (axi_sel_apb1 ? PSLVERR1 : PSLVERR0) ? 2'b10 : 2'b00;
                        rfifo_valid <= 1'b1;
                    end
                    if (axi_burst_reg == 2'b01) axi_addr_reg <= addr_incr;
                    beat_index <= beat_index + 1;
                end
            end

            if (S_AXI_BVALID && S_AXI_BREADY) txn_active <= 1'b0;
            if (S_AXI_RVALID && S_AXI_RREADY) begin
                rfifo_valid <= 1'b0;
                beats_sent  <= beats_sent + 1;
                if (S_AXI_RLAST) txn_active <= 1'b0;
            end
        end
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            apb_state <= APB_IDLE;
            {PSEL0, PENABLE0, PSEL1, PENABLE1} <= 4'b0;
        end else begin
            case (apb_state)
                APB_IDLE: begin
                    {PSEL0, PENABLE0, PSEL1, PENABLE1} <= 4'b0;
                    if (txn_active && !txn_decerr && (beat_index < beats_total)) begin
                        if (axi_is_write) begin
                            if (w_handshake) begin
                                if (axi_sel_apb1) begin
                                    PADDR1 <= axi_addr_reg; PPROT1 <= axi_prot_reg; PWDATA1 <= S_AXI_WDATA; PSTRB1 <= S_AXI_WSTRB; PWRITE1 <= 1'b1; PSEL1 <= 1'b1;
                                end else begin
                                    PADDR0 <= axi_addr_reg; PPROT0 <= axi_prot_reg; PWDATA0 <= S_AXI_WDATA; PSTRB0 <= S_AXI_WSTRB; PWRITE0 <= 1'b1; PSEL0 <= 1'b1;
                                end
                                apb_state <= APB_SETUP;
                            end
                        end else begin
                            if (!rfifo_valid && (!S_AXI_RVALID || S_AXI_RREADY)) begin
                                if (axi_sel_apb1) begin
                                    PADDR1 <= axi_addr_reg; PPROT1 <= axi_prot_reg; PWRITE1 <= 1'b0; PSEL1 <= 1'b1;
                                end else begin
                                    PADDR0 <= axi_addr_reg; PPROT0 <= axi_prot_reg; PWRITE0 <= 1'b0; PSEL0 <= 1'b1;
                                end
                                apb_state <= APB_SETUP;
                            end
                        end
                    end
                end
                APB_SETUP: begin
                    if (axi_sel_apb1) PENABLE1 <= 1'b1; else PENABLE0 <= 1'b1;
                    apb_state <= APB_ACCESS;
                end
                APB_ACCESS: begin
                    if (axi_sel_apb1 ? PREADY1 : PREADY0) begin
                        {PSEL0, PENABLE0, PSEL1, PENABLE1} <= 4'b0;
                        apb_state <= APB_IDLE;
                    end
                end
                default: apb_state <= APB_IDLE;
            endcase
        end
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            S_AXI_BVALID <= 1'b0;
            S_AXI_BID    <= {ID_WIDTH{1'b0}};
            S_AXI_BRESP  <= 2'b00;
        end else begin
            if (S_AXI_BVALID && S_AXI_BREADY) S_AXI_BVALID <= 1'b0;
            else if (txn_active && axi_is_write && (beat_index == beats_total) && (apb_state == APB_IDLE) && !S_AXI_BVALID) begin
                S_AXI_BID    <= axi_id_reg;
                S_AXI_BRESP  <= txn_decerr ? 2'b11 : (pslverr_acc || wlast_err ? 2'b10 : 2'b00);
                S_AXI_BVALID <= 1'b1;
            end
        end
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            S_AXI_RVALID <= 1'b0;
            S_AXI_RID    <= {ID_WIDTH{1'b0}};
            S_AXI_RDATA  <= {DATA_WIDTH{1'b0}};
            S_AXI_RRESP  <= 2'b00;
            S_AXI_RLAST  <= 1'b0;
        end else begin
            if (S_AXI_RVALID && S_AXI_RREADY) S_AXI_RVALID <= 1'b0;
            else if (txn_active && !axi_is_write && (beats_sent < beats_total) && !S_AXI_RVALID) begin
                if (txn_decerr) begin
                    S_AXI_RID    <= axi_id_reg;
                    S_AXI_RDATA  <= {DATA_WIDTH{1'b0}};
                    S_AXI_RRESP  <= 2'b11;
                    S_AXI_RLAST  <= (beats_sent == beats_total - 1);
                    S_AXI_RVALID <= 1'b1;
                end else if (rfifo_valid) begin
                    S_AXI_RID    <= axi_id_reg;
                    S_AXI_RDATA  <= rdata_fifo;
                    S_AXI_RRESP  <= rresp_fifo;
                    S_AXI_RLAST  <= (beats_sent == beats_total - 1);
                    S_AXI_RVALID <= 1'b1;
                end
            end
        end
    end

endmodule
