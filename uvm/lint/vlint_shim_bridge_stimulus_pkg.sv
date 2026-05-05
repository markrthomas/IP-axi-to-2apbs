`timescale 1ns/1ps

// Elaborates stimulus package classes (no UVM / no RTL testbench).
module vlint_shim_bridge_stimulus_pkg;
  import bridge_stimulus_pkg::*;

  initial begin
    automatic bridge_axi_stim_64 s64 = new;
    automatic bridge_axi_stim_32 s32 = new;
  end
endmodule : vlint_shim_bridge_stimulus_pkg
