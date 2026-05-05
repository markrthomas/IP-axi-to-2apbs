`ifndef APB_BURST_EXT_SIDE_IF_SV
`define APB_BURST_EXT_SIDE_IF_SV

// TB-driven PREADY shuffle + PSLVERR injection for reproduced burst-ext scenarios.

interface apb_burst_ext_side_if (input logic clk);
  logic PREADY0;
  logic PREADY1;
  logic PSLVERR0;
  logic PSLVERR1;

  initial begin
    PREADY0 = 1'b1;
    PREADY1 = 1'b1;
    PSLVERR0 = 1'b0;
    PSLVERR1 = 1'b0;
  end

endinterface

`endif
