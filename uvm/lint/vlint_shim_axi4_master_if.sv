`timescale 1ns/1ps

// Wrapper top so the AXI interface can be linted in isolation.
module vlint_shim_axi4_master_if;
  logic clk;
  logic rst_n;

  axi4_master_if u_axi (
    .clk  (clk),
    .rst_n(rst_n)
  );
endmodule : vlint_shim_axi4_master_if
