// Memory + combinational reads for reproduced extended TB; PREADY/PSLVERR come from TB or fork shim.
`timescale 1ns/1ps

module apb_ext_mem_dual #(
    parameter int unsigned ADDR_WIDTH  = 32,
    parameter int unsigned DATA_WIDTH  = 64
) (
    input  wire logic                     clk,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire logic [ADDR_WIDTH-1:0]    PADDR0,
    input  wire logic [ADDR_WIDTH-1:0]    PADDR1,
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire logic                     PSEL0,
    input  wire logic                     PENABLE0,
    input  wire logic                     PWRITE0,
    input  wire logic                     PREADY0_in,
    input  wire logic                     PSEL1,
    input  wire logic                     PENABLE1,
    input  wire logic                     PWRITE1,
    input  wire logic                     PREADY1_in,
    input  wire logic [DATA_WIDTH-1:0]    PWDATA0,
    input  wire logic [DATA_WIDTH-1:0]    PWDATA1,
    output logic [DATA_WIDTH-1:0]         PRDATA0,
    output logic [DATA_WIDTH-1:0]         PRDATA1
);

  logic [DATA_WIDTH-1:0] mem0[0:1023];
  logic [DATA_WIDTH-1:0] mem1[0:1023];

  always_ff @(posedge clk) begin
    if (PSEL0 && PENABLE0 && PREADY0_in && PWRITE0)
      mem0[PADDR0[12:3]] <= PWDATA0;
    if (PSEL1 && PENABLE1 && PREADY1_in && PWRITE1)
      mem1[PADDR1[12:3]] <= PWDATA1;
  end

  always_comb begin
    PRDATA0 = mem0[PADDR0[12:3]];
    PRDATA1 = mem1[PADDR1[12:3]];
  end

endmodule
