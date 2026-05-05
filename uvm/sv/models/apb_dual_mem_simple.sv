// Mirror tb_axi4_to_apb4_2x_simple.v — one-cycle read wait insertion per APB port.
`timescale 1ns/1ps

module apb_dual_mem_simple #(
    parameter int unsigned ADDR_WIDTH  = 32,
    parameter int unsigned DATA_WIDTH  = 64
) (
    input  wire logic                  clk,
    input  wire logic                  rst_n,
    input  wire logic [ADDR_WIDTH-1:0] PADDR0,
    input  wire logic [ADDR_WIDTH-1:0] PADDR1,
    input  wire logic                  PSEL0,
    input  wire logic                  PENABLE0,
    input  wire logic                  PWRITE0,
    input  wire logic                  PSEL1,
    input  wire logic                  PENABLE1,
    input  wire logic                  PWRITE1,
    input  wire logic [DATA_WIDTH-1:0] PWDATA0,
    input  wire logic [DATA_WIDTH-1:0] PWDATA1,
    output logic [DATA_WIDTH-1:0]      PRDATA0,
    output logic [DATA_WIDTH-1:0]      PRDATA1,
    output logic                       PREADY0,
    output logic                       PREADY1,
    output wire logic                  PSLVERR0,
    output wire logic                  PSLVERR1
);

  assign PSLVERR0 = 1'b0;
  assign PSLVERR1 = 1'b0;

  logic [DATA_WIDTH-1:0] mem0[0:255];
  logic [DATA_WIDTH-1:0] mem1[0:255];

  logic rd_wait0, rd_wait1;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      PREADY0 <= 1'b1;
      PREADY1 <= 1'b1;
      rd_wait0 <= 1'b0;
      rd_wait1 <= 1'b0;
    end else begin
      PREADY0 <= 1'b1;
      PREADY1 <= 1'b1;

      if (rd_wait0) begin
        rd_wait0 <= 1'b0;
      end else if (PSEL0 && PENABLE0) begin
        if (PWRITE0) begin
          mem0[PADDR0[9:2]] <= PWDATA0;
        end else begin
          PREADY0  <= 1'b0;
          rd_wait0 <= 1'b1;
        end
      end

      if (rd_wait1) begin
        rd_wait1 <= 1'b0;
      end else if (PSEL1 && PENABLE1) begin
        if (PWRITE1) begin
          mem1[PADDR1[9:2]] <= PWDATA1;
        end else begin
          PREADY1  <= 1'b0;
          rd_wait1 <= 1'b1;
        end
      end
    end
  end

  always_comb begin
    PRDATA0 = mem0[PADDR0[9:2]];
    PRDATA1 = mem1[PADDR1[9:2]];
  end

endmodule
