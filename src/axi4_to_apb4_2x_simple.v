`timescale 1ns/1ps

module axi4_to_apb4_2x_simple #(
    parameter ID_WIDTH     = 4,
    parameter ADDR_WIDTH   = 32,
    parameter DATA_WIDTH   = 64,
    parameter APB_ADDR_BIT = 31
)(
    input  wire                      ACLK,
    input  wire                      ARESETn,

    // AXI4 slave interface (single beat)
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

    // Single-beat only: burst type and WLAST are don't-cares (AWLEN/ARLEN != 0 is rejected above).
    wire _unused_ok = &{1'b0, S_AXI_AWBURST, S_AXI_WLAST, S_AXI_ARBURST};

    // verilator coverage_off
    localparam EXPECTED_AXSIZE = (DATA_WIDTH == 1024) ? 3'b111 :
                                 (DATA_WIDTH == 512)  ? 3'b110 :
                                 (DATA_WIDTH == 256)  ? 3'b101 :
                                 (DATA_WIDTH == 128)  ? 3'b100 :
                                 (DATA_WIDTH == 64)   ? 3'b011 :
                                 (DATA_WIDTH == 32)   ? 3'b010 :
                                 (DATA_WIDTH == 16)   ? 3'b001 :
                                 3'b000;
    // verilator coverage_on
    localparam ST_IDLE      = 3'd0;
    localparam ST_WRITE_APB = 3'd1;
    localparam ST_WRITE_RESP= 3'd2;
    localparam ST_READ_APB  = 3'd3;
    localparam ST_READ_RESP = 3'd4;
    localparam ST_ERR_RESP  = 3'd5;

    reg [2:0]                state;
    reg [ID_WIDTH-1:0]       id_reg;
    reg [ADDR_WIDTH-1:0]     addr_reg;
    reg [2:0]                prot_reg;
    reg                      sel_apb1;
    reg                      aw_pending;
    reg                      w_pending;
    reg [1:0]                err_resp;

    reg [DATA_WIDTH-1:0]     wdata_reg;
    reg [(DATA_WIDTH/8)-1:0] wstrb_reg;

    always @(*) begin
        S_AXI_AWREADY = 1'b0;
        S_AXI_WREADY  = 1'b0;
        S_AXI_ARREADY = 1'b0;
        if (state == ST_IDLE) begin
            if (!aw_pending && !S_AXI_ARVALID) S_AXI_AWREADY = 1'b1;
            if (!w_pending && !S_AXI_ARVALID)  S_AXI_WREADY  = 1'b1;
            if (!aw_pending && !w_pending && !S_AXI_AWVALID && !S_AXI_WVALID) S_AXI_ARREADY = 1'b1;
        end
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            state <= ST_IDLE;
            aw_pending <= 1'b0; w_pending <= 1'b0;
            S_AXI_BVALID <= 1'b0; S_AXI_RVALID <= 1'b0;
            {PSEL0, PENABLE0, PSEL1, PENABLE1} <= 4'b0;
        end else begin
            if (S_AXI_BVALID && S_AXI_BREADY) S_AXI_BVALID <= 1'b0;
            if (S_AXI_RVALID && S_AXI_RREADY) S_AXI_RVALID <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                        id_reg <= S_AXI_AWID; addr_reg <= S_AXI_AWADDR; prot_reg <= S_AXI_AWPROT; sel_apb1 <= S_AXI_AWADDR[APB_ADDR_BIT];
                        if (S_AXI_AWLEN != 8'd0 || S_AXI_AWSIZE != EXPECTED_AXSIZE) begin
                             err_resp <= 2'b11; state <= ST_ERR_RESP; aw_pending <= 1'b1;
                        end else aw_pending <= 1'b1;
                    end
                    if (S_AXI_WVALID && S_AXI_WREADY) begin
                        wdata_reg <= S_AXI_WDATA; wstrb_reg <= S_AXI_WSTRB; w_pending <= 1'b1;
                    end
                    if (aw_pending && w_pending) begin
                        aw_pending <= 1'b0; w_pending <= 1'b0;
                        if (state == ST_ERR_RESP) begin /* already transitioning */ end
                        else begin
                            if (sel_apb1) begin
                                PADDR1 <= addr_reg; PPROT1 <= prot_reg; PWDATA1 <= wdata_reg; PSTRB1 <= wstrb_reg; PWRITE1 <= 1'b1; PSEL1 <= 1'b1;
                            end else begin
                                PADDR0 <= addr_reg; PPROT0 <= prot_reg; PWDATA0 <= wdata_reg; PSTRB0 <= wstrb_reg; PWRITE0 <= 1'b1; PSEL0 <= 1'b1;
                            end
                            state <= ST_WRITE_APB;
                        end
                    end else if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                        id_reg <= S_AXI_ARID; addr_reg <= S_AXI_ARADDR; prot_reg <= S_AXI_ARPROT; sel_apb1 <= S_AXI_ARADDR[APB_ADDR_BIT];
                        if (S_AXI_ARLEN != 8'd0 || S_AXI_ARSIZE != EXPECTED_AXSIZE) begin
                            S_AXI_RID <= S_AXI_ARID; S_AXI_RDATA <= {DATA_WIDTH{1'b0}}; S_AXI_RRESP <= 2'b11; S_AXI_RLAST <= 1'b1; S_AXI_RVALID <= 1'b1;
                            state <= ST_READ_RESP;
                        end else begin
                            if (S_AXI_ARADDR[APB_ADDR_BIT]) begin
                                PADDR1 <= S_AXI_ARADDR; PPROT1 <= S_AXI_ARPROT; PWRITE1 <= 1'b0; PSEL1 <= 1'b1;
                            end else begin
                                PADDR0 <= S_AXI_ARADDR; PPROT0 <= S_AXI_ARPROT; PWRITE0 <= 1'b0; PSEL0 <= 1'b1;
                            end
                            state <= ST_READ_APB;
                        end
                    end
                end

                ST_WRITE_APB: begin
                    if (sel_apb1) begin
                        if (!PENABLE1) PENABLE1 <= 1'b1;
                        else if (PREADY1) begin
                            {PSEL1, PENABLE1} <= 2'b0; S_AXI_BID <= id_reg; S_AXI_BRESP <= PSLVERR1 ? 2'b10 : 2'b00; S_AXI_BVALID <= 1'b1; state <= ST_WRITE_RESP;
                        end
                    end else begin
                        if (!PENABLE0) PENABLE0 <= 1'b1;
                        else if (PREADY0) begin
                            {PSEL0, PENABLE0} <= 2'b0; S_AXI_BID <= id_reg; S_AXI_BRESP <= PSLVERR0 ? 2'b10 : 2'b00; S_AXI_BVALID <= 1'b1; state <= ST_WRITE_RESP;
                        end
                    end
                end

                ST_ERR_RESP: begin
                    if (aw_pending && w_pending) begin
                        aw_pending <= 1'b0; w_pending <= 1'b0; S_AXI_BID <= id_reg; S_AXI_BRESP <= err_resp; S_AXI_BVALID <= 1'b1; state <= ST_WRITE_RESP;
                    end
                end

                ST_WRITE_RESP: if (!S_AXI_BVALID) state <= ST_IDLE;

                ST_READ_APB: begin
                    if (sel_apb1) begin
                        if (!PENABLE1) PENABLE1 <= 1'b1;
                        else if (PREADY1) begin
                            {PSEL1, PENABLE1} <= 2'b0; S_AXI_RID <= id_reg; S_AXI_RDATA <= PRDATA1; S_AXI_RRESP <= PSLVERR1 ? 2'b10 : 2'b00; S_AXI_RLAST <= 1'b1; S_AXI_RVALID <= 1'b1; state <= ST_READ_RESP;
                        end
                    end else begin
                        if (!PENABLE0) PENABLE0 <= 1'b1;
                        else if (PREADY0) begin
                            {PSEL0, PENABLE0} <= 2'b0; S_AXI_RID <= id_reg; S_AXI_RDATA <= PRDATA0; S_AXI_RRESP <= PSLVERR0 ? 2'b10 : 2'b00; S_AXI_RLAST <= 1'b1; S_AXI_RVALID <= 1'b1; state <= ST_READ_RESP;
                        end
                    end
                end

                ST_READ_RESP: if (!S_AXI_RVALID) state <= ST_IDLE;

                // Excluded from coverage: no legal AXI stimulus can produce an
                // out-of-range state value; arm is unreachable by design.
                // See doc/coverage_notes.md §Exclusions.
                default: begin /*verilator coverage_block_off*/ state <= ST_IDLE; end
            endcase
        end
    end

endmodule
