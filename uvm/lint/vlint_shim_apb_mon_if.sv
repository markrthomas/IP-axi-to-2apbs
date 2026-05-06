`timescale 1ns/1ps

module vlint_shim_apb_mon_if;
  localparam int unsigned ADDR_WIDTH = 32;
  localparam int unsigned DATA_WIDTH = 64;

  logic clk;
  logic rst_n;
  logic [ADDR_WIDTH-1:0] PADDR;
  logic [2:0] PPROT;
  logic PSEL;
  logic PENABLE;
  logic PWRITE;
  logic [DATA_WIDTH-1:0] PWDATA;
  logic [(DATA_WIDTH/8)-1:0] PSTRB;
  logic [DATA_WIDTH-1:0] PRDATA;
  logic PREADY;
  logic PSLVERR;

  apb_mon_if #(
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_WIDTH(DATA_WIDTH)
  ) u (
      .clk(clk),
      .rst_n(rst_n),
      .PADDR(PADDR),
      .PPROT(PPROT),
      .PSEL(PSEL),
      .PENABLE(PENABLE),
      .PWRITE(PWRITE),
      .PWDATA(PWDATA),
      .PSTRB(PSTRB),
      .PRDATA(PRDATA),
      .PREADY(PREADY),
      .PSLVERR(PSLVERR)
  );
endmodule : vlint_shim_apb_mon_if
