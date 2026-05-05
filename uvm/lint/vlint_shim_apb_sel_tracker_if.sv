`timescale 1ns/1ps

module vlint_shim_apb_sel_tracker_if;
  logic clk;
  logic rst_n;
  apb_sel_tracker_if u (
    .clk  (clk),
    .rst_n(rst_n)
  );
endmodule : vlint_shim_apb_sel_tracker_if
