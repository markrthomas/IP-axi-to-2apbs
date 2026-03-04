// Simple single-beat AXI4 (AXI4-lite style) to 2x APB4 bridge
// - 32-bit address, 64-bit data
// - One beat per transaction (AWLEN/ARLEN must be 0)
// - Address[31] selects APB0 (0) or APB1 (1)

`timescale 1ns/1ps

module axi4_to_apb4_2x_simple #(
    parameter ID_WIDTH   = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64
)(
    input  wire                      ACLK,
    input  wire                      ARESETn,

    // AXI4 slave interface (single beat)
    // Write address channel
    input  wire [ID_WIDTH-1:0]       S_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0]     S_AXI_AWADDR,
    input  wire [7:0]                S_AXI_AWLEN,
    input  wire [2:0]                S_AXI_AWSIZE,
    input  wire [1:0]                S_AXI_AWBURST,
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
    input  wire [7:0]                S_AXI_ARLEN,
    input  wire [2:0]                S_AXI_ARSIZE,
    input  wire [1:0]                S_AXI_ARBURST,
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

    // Simple state machine
    localparam ST_IDLE      = 3'd0;
    localparam ST_WRITE_APB = 3'd1;
    localparam ST_WRITE_RESP= 3'd2;
    localparam ST_READ_APB  = 3'd3;
    localparam ST_READ_RESP = 3'd4;

    reg [2:0]                state;

    // Latched transaction info
    reg [ID_WIDTH-1:0]       id_reg;
    reg [ADDR_WIDTH-1:0]     addr_reg;
    reg [2:0]                prot_reg;
    reg                      is_write;
    reg                      sel_apb1;

    reg [DATA_WIDTH-1:0]     wdata_reg;
    reg [(DATA_WIDTH/8)-1:0] wstrb_reg;

    // Ready signals
    always @(*) begin
        // Defaults
        S_AXI_AWREADY = 1'b0;
        S_AXI_WREADY  = 1'b0;
        S_AXI_ARREADY = 1'b0;

        if (state == ST_IDLE) begin
            // Accept either a write (AW+W in same cycle) or a read, not both
            if (S_AXI_AWVALID && S_AXI_WVALID && !S_AXI_ARVALID) begin
                S_AXI_AWREADY = 1'b1;
                S_AXI_WREADY  = 1'b1;
            end else if (S_AXI_ARVALID && !S_AXI_AWVALID && !S_AXI_WVALID) begin
                S_AXI_ARREADY = 1'b1;
            end
        end
    end

    // Main FSM
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            state      <= ST_IDLE;
            id_reg     <= {ID_WIDTH{1'b0}};
            addr_reg   <= {ADDR_WIDTH{1'b0}};
            prot_reg   <= 3'b000;
            is_write   <= 1'b0;
            sel_apb1   <= 1'b0;
            wdata_reg  <= {DATA_WIDTH{1'b0}};
            wstrb_reg  <= {(DATA_WIDTH/8){1'b0}};

            S_AXI_BID    <= {ID_WIDTH{1'b0}};
            S_AXI_BRESP  <= 2'b00;
            S_AXI_BVALID <= 1'b0;

            S_AXI_RID    <= {ID_WIDTH{1'b0}};
            S_AXI_RDATA  <= {DATA_WIDTH{1'b0}};
            S_AXI_RRESP  <= 2'b00;
            S_AXI_RLAST  <= 1'b0;
            S_AXI_RVALID <= 1'b0;

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
            // Default deasserts each cycle
            if (state != ST_WRITE_APB) begin
                PSEL0 <= 1'b0;
                PSEL1 <= 1'b0;
                PENABLE0 <= 1'b0;
                PENABLE1 <= 1'b0;
            end

            // Clear responses when accepted
            if (S_AXI_BVALID && S_AXI_BREADY)
                S_AXI_BVALID <= 1'b0;
            if (S_AXI_RVALID && S_AXI_RREADY)
                S_AXI_RVALID <= 1'b0;

            case (state)
                ST_IDLE: begin
                    // Write acceptance: AW and W together
                    if (S_AXI_AWVALID && S_AXI_WVALID && S_AXI_AWREADY && S_AXI_WREADY) begin
                        id_reg    <= S_AXI_AWID;
                        addr_reg  <= S_AXI_AWADDR;
                        prot_reg  <= S_AXI_AWPROT;
                        is_write  <= 1'b1;
                        sel_apb1  <= S_AXI_AWADDR[31];
                        wdata_reg <= S_AXI_WDATA;
                        wstrb_reg <= S_AXI_WSTRB;

                        // Drive APB write SETUP phase
                        if (S_AXI_AWADDR[31]) begin
                            PADDR1  <= S_AXI_AWADDR;
                            PPROT1  <= S_AXI_AWPROT;
                            PWDATA1 <= S_AXI_WDATA;
                            PSTRB1  <= S_AXI_WSTRB;
                            PWRITE1 <= 1'b1;
                            PSEL1   <= 1'b1;
                        end else begin
                            PADDR0  <= S_AXI_AWADDR;
                            PPROT0  <= S_AXI_AWPROT;
                            PWDATA0 <= S_AXI_WDATA;
                            PSTRB0  <= S_AXI_WSTRB;
                            PWRITE0 <= 1'b1;
                            PSEL0   <= 1'b1;
                        end
                        state <= ST_WRITE_APB;
                    end
                    // Read acceptance
                    else if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                        id_reg   <= S_AXI_ARID;
                        addr_reg <= S_AXI_ARADDR;
                        prot_reg <= S_AXI_ARPROT;
                        is_write <= 1'b0;
                        sel_apb1 <= S_AXI_ARADDR[31];

                        // Drive APB read SETUP phase
                        if (S_AXI_ARADDR[31]) begin
                            PADDR1  <= S_AXI_ARADDR;
                            PPROT1  <= S_AXI_ARPROT;
                            PWRITE1 <= 1'b0;
                            PSEL1   <= 1'b1;
                        end else begin
                            PADDR0  <= S_AXI_ARADDR;
                            PPROT0  <= S_AXI_ARPROT;
                            PWRITE0 <= 1'b0;
                            PSEL0   <= 1'b1;
                        end
                        state <= ST_READ_APB;
                    end
                end

                // APB write: SETUP (PSEL) then ACCESS (PENABLE)
                ST_WRITE_APB: begin
                    if (sel_apb1) begin
                        PENABLE1 <= 1'b1;
                        if (PREADY1) begin
                            PSEL1    <= 1'b0;
                            PENABLE1 <= 1'b0;
                            // Prepare write response
                            S_AXI_BID   <= id_reg;
                            S_AXI_BRESP <= PSLVERR1 ? 2'b10 : 2'b00;
                            S_AXI_BVALID<= 1'b1;
                            state       <= ST_WRITE_RESP;
                        end
                    end else begin
                        PENABLE0 <= 1'b1;
                        if (PREADY0) begin
                            PSEL0    <= 1'b0;
                            PENABLE0 <= 1'b0;
                            S_AXI_BID   <= id_reg;
                            S_AXI_BRESP <= PSLVERR0 ? 2'b10 : 2'b00;
                            S_AXI_BVALID<= 1'b1;
                            state       <= ST_WRITE_RESP;
                        end
                    end
                end

                ST_WRITE_RESP: begin
                    if (!S_AXI_BVALID) begin
                        state <= ST_IDLE;
                    end
                end

                // APB read: SETUP then ACCESS, then drive RDATA
                ST_READ_APB: begin
                    if (sel_apb1) begin
                        PENABLE1 <= 1'b1;
                        if (PREADY1) begin
                            PSEL1    <= 1'b0;
                            PENABLE1 <= 1'b0;
                            S_AXI_RID   <= id_reg;
                            S_AXI_RDATA <= PRDATA1;
                            S_AXI_RRESP <= PSLVERR1 ? 2'b10 : 2'b00;
                            S_AXI_RLAST <= 1'b1;
                            S_AXI_RVALID<= 1'b1;
                            state       <= ST_READ_RESP;
                        end
                    end else begin
                        PENABLE0 <= 1'b1;
                        if (PREADY0) begin
                            PSEL0    <= 1'b0;
                            PENABLE0 <= 1'b0;
                            S_AXI_RID   <= id_reg;
                            S_AXI_RDATA <= PRDATA0;
                            S_AXI_RRESP <= PSLVERR0 ? 2'b10 : 2'b00;
                            S_AXI_RLAST <= 1'b1;
                            S_AXI_RVALID<= 1'b1;
                            state       <= ST_READ_RESP;
                        end
                    end
                end

                ST_READ_RESP: begin
                    if (!S_AXI_RVALID) begin
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule

