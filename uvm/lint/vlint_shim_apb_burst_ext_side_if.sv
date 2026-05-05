`timescale 1ns/1ps

module vlint_shim_apb_burst_ext_side_if;
  logic clk;
  apb_burst_ext_side_if u (.clk(clk));
endmodule : vlint_shim_apb_burst_ext_side_if
