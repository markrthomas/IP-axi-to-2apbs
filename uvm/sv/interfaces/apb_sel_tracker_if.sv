`ifndef APB_SEL_TRACKER_IF_SV
`define APB_SEL_TRACKER_IF_SV

// Sticky PSEL visibility with software clear (mirrors psel*_seen in tb_parameterized_config.v).

interface apb_sel_tracker_if (input logic clk, input logic rst_n);
  logic PSEL0;
  logic PSEL1;

  logic saw0;
  logic saw1;
  logic clr;

  initial clr = 1'b0;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      saw0 <= 1'b0;
      saw1 <= 1'b0;
    end else if (clr) begin
      saw0 <= 1'b0;
      saw1 <= 1'b0;
    end else begin
      if (PSEL0)
        saw0 <= 1'b1;
      if (PSEL1)
        saw1 <= 1'b1;
    end
  end

  task automatic clear_pulse();
    @(posedge clk);
    clr = 1'b1;
    @(posedge clk);
    clr = 1'b0;
  endtask
endinterface

`endif
