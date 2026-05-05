// Mirror tb_parameterized_config.v APB data path (sizes follow PADDR[9:2]).
`timescale 1ns/1ps

module apb_dual_mem_param #(
    parameter int unsigned ADDR_WIDTH  = 32,
    parameter int unsigned DATA_WIDTH  = 32
) (
    input  wire logic                     clk,
    input  wire logic [ADDR_WIDTH-1:0]    PADDR0,
    input  wire logic [ADDR_WIDTH-1:0]    PADDR1,
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
    output wire logic                     PREADY0,
    output wire logic                     PREADY1,
    output wire logic                     PSLVERR0,
    output wire logic                     PSLVERR1
);

  logic [DATA_WIDTH-1:0] mem0[0:255];
  logic [DATA_WIDTH-1:0] mem1[0:255];

  assign PREADY0 = 1'b1;
  assign PREADY1 = 1'b1;
  assign PSLVERR0 = 1'b0;
  assign PSLVERR1 = 1'b0;

  always_ff @(posedge clk) begin
    if (PSEL0 && PENABLE0) begin
      if (PWRITE0)
        mem0[PADDR0[9:2]] <= PWDATA0;
    end
    if (PSEL1 && PENABLE1) begin
      if (PWRITE1)
        mem1[PADDR1[9:2]] <= PWDATA1;
    end
  end

  always_comb begin
    PRDATA0 = mem0[PADDR0[9:2]];
    PRDATA1 = mem1[PADDR1[9:2]];
  end

endmodule
