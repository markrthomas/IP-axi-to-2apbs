module axi4_to_apb4_2x_burst #(
    parameter ID_WIDTH   = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64
)(
    input  wire                      ACLK,
    input  wire                      ARESETn,

    // AXI4 slave interface
    // Write address channel
    input  wire [ID_WIDTH-1:0]       S_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0]     S_AXI_AWADDR,
    input  wire [7:0]                S_AXI_AWLEN,    // beats-1
    input  wire [2:0]                S_AXI_AWSIZE,   // expect 3'b011 (8B)
    input  wire [1:0]                S_AXI_AWBURST,  // 01=INCR, 00=FIXED
    input  wire [2:0]                S_AXI_AWPROT,
    input  wire                      S_AXI_AWVALID,
    output reg                       S_AXI_AWREADY,

    // Write data channel
    input  wire [DATA_WIDTH-1:0]     S_AXI_WDATA,
    input  wire [(DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input  wire                      S_AXI_WLAST,
    input  wire                      S_AXI_WVALID,
    output reg                       S_AXI_WREADY,

    // Write response channel
    output reg  [ID_WIDTH-1:0]       S_AXI_BID,
    output reg  [1:0]                S_AXI_BRESP,
    output reg                       S_AXI_BVALID,
    input  wire                      S_AXI_BREADY,

    // Read address channel
    input  wire [ID_WIDTH-1:0]       S_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0]     S_AXI_ARADDR,
    input  wire [7:0]                S_AXI_ARLEN,    // beats-1
    input  wire [2:0]                S_AXI_ARSIZE,   // expect 3'b011
    input  wire [1:0]                S_AXI_ARBURST,  // 01=INCR, 00=FIXED
    input  wire [2:0]                S_AXI_ARPROT,
    input  wire                      S_AXI_ARVALID,
    output reg                       S_AXI_ARREADY,

    // Read data channel
    output reg  [ID_WIDTH-1:0]       S_AXI_RID,
    output reg  [DATA_WIDTH-1:0]     S_AXI_RDATA,
    output reg  [1:0]                S_AXI_RRESP,
    output reg                       S_AXI_RLAST,
    output reg                       S_AXI_RVALID,
    input  wire                      S_AXI_RREADY,

    // APB4 master interface 0 (addr[31]==0)
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

    // APB4 master interface 1 (addr[31]==1)
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

    reg [ID_WIDTH-1:0]           axi_id_reg;
    reg [ADDR_WIDTH-1:0]         axi_addr_reg;      // current beat address
    reg [2:0]                    axi_prot_reg;
    reg [2:0]                    axi_size_reg;
    reg [1:0]                    axi_burst_reg;
    reg [7:0]                    axi_len_reg;       // beats-1
    reg [7:0]                    beat_index;        // current beat
    reg [7:0]                    beats_total;       // len+1
    reg                          axi_is_write;
    reg                          axi_sel_apb1;      // 0=APB0, 1=APB1
    reg                          txn_active;
    reg                          txn_decerr;        // this transaction is DECERR

    reg [DATA_WIDTH-1:0]         axi_wdata_reg;
    reg [(DATA_WIDTH/8)-1:0]     axi_wstrb_reg;

    localparam APB_IDLE   = 2'd0;
    localparam APB_SETUP  = 2'd1;
    localparam APB_ACCESS = 2'd2;

    reg [1:0] apb_state;

    wire [ADDR_WIDTH-1:0] addr_incr =
        axi_addr_reg + (1 << axi_size_reg);

    wire [ADDR_WIDTH-1:0] aw_max_offset =
        { { (ADDR_WIDTH-8){1'b0} }, S_AXI_AWLEN } << S_AXI_AWSIZE;
    wire [ADDR_WIDTH-1:0] ar_max_offset =
        { { (ADDR_WIDTH-8){1'b0} }, S_AXI_ARLEN } << S_AXI_ARSIZE;

    // Verilog-2001: cannot index an expression directly, so use
    // temporaries for last addresses when checking for crossing bit 31.
    wire [ADDR_WIDTH-1:0] aw_last_addr = S_AXI_AWADDR + aw_max_offset;
    wire [ADDR_WIDTH-1:0] ar_last_addr = S_AXI_ARADDR + ar_max_offset;

    wire aw_cross_31 =
        (S_AXI_AWBURST == 2'b01) &&
        (S_AXI_AWADDR[31] ^ aw_last_addr[31]);

    wire ar_cross_31 =
        (S_AXI_ARBURST == 2'b01) &&
        (S_AXI_ARADDR[31] ^ ar_last_addr[31]);

    wire aw_param_err =
        (S_AXI_AWSIZE  != 3'b011) ||
        (S_AXI_AWBURST != 2'b01 && S_AXI_AWBURST != 2'b00) ||
        aw_cross_31;

    wire ar_param_err =
        (S_AXI_ARSIZE  != 3'b011) ||
        (S_AXI_ARBURST != 2'b01 && S_AXI_ARBURST != 2'b00) ||
        ar_cross_31;

    wire busy_with_resp = S_AXI_BVALID || S_AXI_RVALID;
    wire idle_for_new   = !txn_active && !busy_with_resp && (apb_state == APB_IDLE);

    always @(*) begin
        S_AXI_AWREADY = idle_for_new && !S_AXI_ARVALID;
        S_AXI_ARREADY = idle_for_new && !S_AXI_AWVALID;

        if (txn_active && axi_is_write && (beat_index < beats_total)) begin
            if (txn_decerr)
                S_AXI_WREADY = 1'b1;
            else
                S_AXI_WREADY = (apb_state == APB_IDLE);
        end else begin
            S_AXI_WREADY = 1'b0;
        end
    end

    wire aw_handshake = S_AXI_AWVALID && S_AXI_AWREADY;
    wire ar_handshake = S_AXI_ARVALID && S_AXI_ARREADY;
    wire w_handshake  = S_AXI_WVALID  && S_AXI_WREADY;

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            axi_id_reg    <= {ID_WIDTH{1'b0}};
            axi_addr_reg  <= {ADDR_WIDTH{1'b0}};
            axi_prot_reg  <= 3'b000;
            axi_size_reg  <= 3'b000;
            axi_burst_reg <= 2'b01;
            axi_len_reg   <= 8'd0;
            beats_total   <= 8'd1;
            beat_index    <= 8'd0;
            axi_is_write  <= 1'b0;
            axi_sel_apb1  <= 1'b0;
            txn_active    <= 1'b0;
            txn_decerr    <= 1'b0;
            axi_wdata_reg <= {DATA_WIDTH{1'b0}};
            axi_wstrb_reg <= {(DATA_WIDTH/8){1'b0}};
        end else begin
            if (aw_handshake) begin
                axi_id_reg    <= S_AXI_AWID;
                axi_addr_reg  <= S_AXI_AWADDR;
                axi_prot_reg  <= S_AXI_AWPROT;
                axi_size_reg  <= S_AXI_AWSIZE;
                axi_burst_reg <= S_AXI_AWBURST;
                axi_len_reg   <= S_AXI_AWLEN;
                beats_total   <= S_AXI_AWLEN + 1;
                beat_index    <= 8'd0;
                axi_is_write  <= 1'b1;
                axi_sel_apb1  <= S_AXI_AWADDR[31];
                txn_active    <= 1'b1;
                txn_decerr    <= aw_param_err;
            end

            if (ar_handshake) begin
                axi_id_reg    <= S_AXI_ARID;
                axi_addr_reg  <= S_AXI_ARADDR;
                axi_prot_reg  <= S_AXI_ARPROT;
                axi_size_reg  <= S_AXI_ARSIZE;
                axi_burst_reg <= S_AXI_ARBURST;
                axi_len_reg   <= S_AXI_ARLEN;
                beats_total   <= S_AXI_ARLEN + 1;
                beat_index    <= 8'd0;
                axi_is_write  <= 1'b0;
                axi_sel_apb1  <= S_AXI_ARADDR[31];
                txn_active    <= 1'b1;
                txn_decerr    <= ar_param_err;
            end

            if (w_handshake && txn_active && axi_is_write) begin
                axi_wdata_reg <= S_AXI_WDATA;
                axi_wstrb_reg <= S_AXI_WSTRB;

                if (txn_decerr) begin
                    beat_index <= beat_index + 1;
                end
            end

            if (S_AXI_BVALID && S_AXI_BREADY) begin
                txn_active <= 1'b0;
            end
            if (S_AXI_RVALID && S_AXI_RREADY && S_AXI_RLAST) begin
                txn_active <= 1'b0;
            end
        end
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            apb_state <= APB_IDLE;

            PADDR0   <= {ADDR_WIDTH{1'b0}};
            PPROT0   <= 3'b000;
            PSEL0    <= 1'b0;
            PENABLE0 <= 1'b0;
            PWRITE0  <= 1'b0;
            PWDATA0  <= {DATA_WIDTH{1'b0}};
            PSTRB0   <= {(DATA_WIDTH/8){1'b0}};

            PADDR1   <= {ADDR_WIDTH{1'b0}};
            PPROT1   <= 3'b000;
            PSEL1    <= 1'b0;
            PENABLE1 <= 1'b0;
            PWRITE1  <= 1'b0;
            PWDATA1  <= {DATA_WIDTH{1'b0}};
            PSTRB1   <= {(DATA_WIDTH/8){1'b0}};
        end else begin
            case (apb_state)
                APB_IDLE: begin
                    PSEL0    <= 1'b0;
                    PENABLE0 <= 1'b0;
                    PWRITE0  <= 1'b0;

                    PSEL1    <= 1'b0;
                    PENABLE1 <= 1'b0;
                    PWRITE1  <= 1'b0;

                    if (txn_active && !txn_decerr && (beat_index < beats_total)) begin
                        if (axi_is_write) begin
                            if (w_handshake) begin
                                if (axi_sel_apb1) begin
                                    PADDR1  <= axi_addr_reg;
                                    PPROT1  <= axi_prot_reg;
                                    PWDATA1 <= S_AXI_WDATA;
                                    PSTRB1  <= S_AXI_WSTRB;
                                    PWRITE1 <= 1'b1;
                                    PSEL1   <= 1'b1;
                                end else begin
                                    PADDR0  <= axi_addr_reg;
                                    PPROT0  <= axi_prot_reg;
                                    PWDATA0 <= S_AXI_WDATA;
                                    PSTRB0  <= S_AXI_WSTRB;
                                    PWRITE0 <= 1'b1;
                                    PSEL0   <= 1'b1;
                                end
                                apb_state <= APB_SETUP;
                            end
                        end else begin
                            if (!S_AXI_RVALID || (S_AXI_RVALID && S_AXI_RREADY)) begin
                                if (axi_sel_apb1) begin
                                    PADDR1  <= axi_addr_reg;
                                    PPROT1  <= axi_prot_reg;
                                    PWRITE1 <= 1'b0;
                                    PSEL1   <= 1'b1;
                                end else begin
                                    PADDR0  <= axi_addr_reg;
                                    PPROT0  <= axi_prot_reg;
                                    PWRITE0 <= 1'b0;
                                    PSEL0   <= 1'b1;
                                end
                                apb_state <= APB_SETUP;
                            end
                        end
                    end
                end

                APB_SETUP: begin
                    if (axi_sel_apb1) begin
                        PENABLE1 <= 1'b1;
                    end else begin
                        PENABLE0 <= 1'b1;
                    end
                    apb_state <= APB_ACCESS;
                end

                APB_ACCESS: begin
                    if (!axi_sel_apb1) begin
                        if (PREADY0) begin
                            PSEL0    <= 1'b0;
                            PENABLE0 <= 1'b0;

                            if (axi_burst_reg == 2'b01)
                                axi_addr_reg <= addr_incr;

                            beat_index <= beat_index + 1;
                            apb_state  <= APB_IDLE;
                        end
                    end else begin
                        if (PREADY1) begin
                            PSEL1    <= 1'b0;
                            PENABLE1 <= 1'b0;

                            if (axi_burst_reg == 2'b01)
                                axi_addr_reg <= addr_incr;

                            beat_index <= beat_index + 1;
                            apb_state  <= APB_IDLE;
                        end
                    end
                end

                default: apb_state <= APB_IDLE;
            endcase
        end
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            S_AXI_BID    <= {ID_WIDTH{1'b0}};
            S_AXI_BRESP  <= 2'b00;
            S_AXI_BVALID <= 1'b0;
        end else begin
            if (S_AXI_BVALID && S_AXI_BREADY)
                S_AXI_BVALID <= 1'b0;

            if (txn_active && axi_is_write && txn_decerr &&
                (beat_index == beats_total) && !S_AXI_BVALID) begin
                S_AXI_BID    <= axi_id_reg;
                S_AXI_BRESP  <= 2'b11;
                S_AXI_BVALID <= 1'b1;
            end

            if (txn_active && axi_is_write && !txn_decerr &&
                (beat_index == beats_total) &&
                (apb_state == APB_IDLE) &&
                !S_AXI_BVALID) begin
                S_AXI_BID <= axi_id_reg;
                if (!axi_sel_apb1)
                    S_AXI_BRESP <= PSLVERR0 ? 2'b10 : 2'b00;
                else
                    S_AXI_BRESP <= PSLVERR1 ? 2'b10 : 2'b00;
                S_AXI_BVALID <= 1'b1;
            end
        end
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            S_AXI_RID    <= {ID_WIDTH{1'b0}};
            S_AXI_RDATA  <= {DATA_WIDTH{1'b0}};
            S_AXI_RRESP  <= 2'b00;
            S_AXI_RLAST  <= 1'b0;
            S_AXI_RVALID <= 1'b0;
        end else begin
            if (S_AXI_RVALID && S_AXI_RREADY)
                S_AXI_RVALID <= 1'b0;

            if (txn_active && !axi_is_write && txn_decerr &&
                (beat_index < beats_total) && !S_AXI_RVALID) begin
                S_AXI_RID    <= axi_id_reg;
                S_AXI_RDATA  <= {DATA_WIDTH{1'b0}};
                S_AXI_RRESP  <= 2'b11;
                S_AXI_RLAST  <= (beat_index == beats_total - 1);
                S_AXI_RVALID <= 1'b1;

                if (S_AXI_RREADY) begin
                    beat_index <= beat_index + 1;
                end
            end

            if (txn_active && !axi_is_write && !txn_decerr &&
                (apb_state == APB_IDLE) &&
                (beat_index != 0) &&
                !S_AXI_RVALID) begin
                S_AXI_RID <= axi_id_reg;
                if (!axi_sel_apb1) begin
                    S_AXI_RDATA <= PRDATA0;
                    S_AXI_RRESP <= PSLVERR0 ? 2'b10 : 2'b00;
                end else begin
                    S_AXI_RDATA <= PRDATA1;
                    S_AXI_RRESP <= PSLVERR1 ? 2'b10 : 2'b00;
                end
                S_AXI_RLAST  <= (beat_index == beats_total);
                S_AXI_RVALID <= 1'b1;
            end
        end
    end

endmodule

