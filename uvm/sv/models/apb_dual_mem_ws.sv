// Mirror tb_axi4_to_apb4_2x_simple_ws.v — parameterized multi-cycle read stall.
`timescale 1ns/1ps

module apb_dual_mem_ws #(
    parameter int unsigned ADDR_WIDTH     = 32,
    parameter int unsigned DATA_WIDTH     = 64,
    parameter int unsigned READ_WAIT_CYCLES = 2
) (
    input  wire logic                     clk,
    input  wire logic                     rst_n,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire logic [ADDR_WIDTH-1:0]    PADDR0,
    input  wire logic [ADDR_WIDTH-1:0]    PADDR1,
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire logic                     PSEL0,
    input  wire logic                     PENABLE0,
    input  wire logic                     PWRITE0,
    input  wire logic                     PSEL1,
    input  wire logic                     PENABLE1,
    input  wire logic                     PWRITE1,
    input  wire logic [DATA_WIDTH-1:0]    PWDATA0,
    input  wire logic [DATA_WIDTH-1:0]    PWDATA1,
    output logic [DATA_WIDTH-1:0]         PRDATA0,
    output logic [DATA_WIDTH-1:0]         PRDATA1,
    output logic                          PREADY0,
    output logic                          PREADY1,
    output wire logic                     PSLVERR0,
    output wire logic                     PSLVERR1
);

  assign PSLVERR0 = 1'b0;
  assign PSLVERR1 = 1'b0;

  logic [DATA_WIDTH-1:0] mem0[0:255];
  logic [DATA_WIDTH-1:0] mem1[0:255];

  int unsigned rd_count0;
  int unsigned rd_count1;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      PREADY0 <= 1'b1;
      PREADY1 <= 1'b1;
      rd_count0 <= 0;
      rd_count1 <= 0;
    end else begin
      PREADY0 <= 1'b1;
      PREADY1 <= 1'b1;

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
        end else if (READ_WAIT_CYCLES > 0) begin
          PREADY0  <= 1'b0;
          rd_count0 <= READ_WAIT_CYCLES;
        end
      end

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
        end else if (READ_WAIT_CYCLES > 0) begin
          PREADY1  <= 1'b0;
          rd_count1 <= READ_WAIT_CYCLES;
        end
      end
    end
  end

  always_comb begin
    PRDATA0 = mem0[PADDR0[9:2]];
    PRDATA1 = mem1[PADDR1[9:2]];
  end

endmodule
