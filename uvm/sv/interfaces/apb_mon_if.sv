`ifndef APB_MON_IF_SV
`define APB_MON_IF_SV

// Passive APB4 bundle for monitors (signals driven by RTL; all inputs here).
interface apb_mon_if #(
  parameter int unsigned ADDR_WIDTH = 32,
  parameter int unsigned DATA_WIDTH = 64
) (
    input logic clk,
    input logic rst_n,
    input logic [ ADDR_WIDTH    - 1:0 ] PADDR,
    input logic [                      2:0 ] PPROT,
    input logic PSEL,
    input logic PENABLE,
    input logic PWRITE,
    input logic [ DATA_WIDTH - 1:0 ] PWDATA,
    input logic [(DATA_WIDTH / 8) - 1:0] PSTRB,
    input logic [ DATA_WIDTH - 1:0 ] PRDATA,
    input logic PREADY,
    input logic PSLVERR
);

endinterface

`endif
