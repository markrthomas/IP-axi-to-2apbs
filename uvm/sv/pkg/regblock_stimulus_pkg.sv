`ifndef REGBLOCK_STIMULUS_PKG_SV
`define REGBLOCK_STIMULUS_PKG_SV

/* verilator lint_off DECLFILENAME */
package regblock_stimulus_pkg;
  timeunit 1ns;
  timeprecision 1ps;

  typedef virtual axi3lite_if #(
    .ID_WIDTH(4), .ADDR_WIDTH(32), .DATA_WIDTH(32)
  ) v_axi3lite_if_t;

  class regblock_axi3lite_stim;
    v_axi3lite_if_t vif;

    function void set_if(v_axi3lite_if_t v);
      vif = v;
    endfunction

    function void drv_init_zeros();
      vif.S_AXI_AWID    = '0;
      vif.S_AXI_AWADDR  = '0;
      vif.S_AXI_AWPROT  = '0;
      vif.S_AXI_AWVALID = 1'b0;
      vif.S_AXI_WID     = '0;
      vif.S_AXI_WDATA   = '0;
      vif.S_AXI_WSTRB   = '0;
      vif.S_AXI_WVALID  = 1'b0;
      vif.S_AXI_BREADY  = 1'b0;
      vif.S_AXI_ARID    = '0;
      vif.S_AXI_ARADDR  = '0;
      vif.S_AXI_ARPROT  = '0;
      vif.S_AXI_ARVALID = 1'b0;
      vif.S_AXI_RREADY  = 1'b0;
    endfunction

    task wait_reset_done();
      @(posedge vif.rst_n);
      @(posedge vif.clk);
    endtask

    // AXI3-Lite single write.  Sets WID = awid (matching).
    // Returns BRESP[1:0].
    task axi3lite_single_write(
      input  logic [31:0] addr,
      input  logic [31:0] data,
      input  logic [ 3:0] strb   = 4'hF,
      input  logic [ 3:0] awid   = 4'd0,
      output logic [ 1:0] bresp
    );
      @(posedge vif.clk);
      vif.S_AXI_AWID    <= awid;
      vif.S_AXI_AWADDR  <= addr;
      vif.S_AXI_AWPROT  <= 3'd0;
      vif.S_AXI_AWVALID <= 1'b1;
      vif.S_AXI_WID     <= awid;
      vif.S_AXI_WDATA   <= data;
      vif.S_AXI_WSTRB   <= strb;
      vif.S_AXI_WVALID  <= 1'b1;
      vif.S_AXI_BREADY  <= 1'b1;

      // AW handshake
      wait (vif.S_AXI_AWREADY);
      @(posedge vif.clk);
      vif.S_AXI_AWVALID <= 1'b0;
      // W handshake
      wait (vif.S_AXI_WREADY);
      @(posedge vif.clk);
      vif.S_AXI_WVALID <= 1'b0;
      // B response
      wait (vif.S_AXI_BVALID);
      bresp = vif.S_AXI_BRESP;
      @(posedge vif.clk);
      vif.S_AXI_BREADY <= 1'b0;
    endtask

    // AXI3-Lite single read.  Returns {rdata, rresp}.
    task axi3lite_single_read(
      input  logic [31:0] addr,
      input  logic [ 3:0] arid  = 4'd0,
      output logic [31:0] rdata,
      output logic [ 1:0] rresp
    );
      @(posedge vif.clk);
      vif.S_AXI_ARID    <= arid;
      vif.S_AXI_ARADDR  <= addr;
      vif.S_AXI_ARPROT  <= 3'd0;
      vif.S_AXI_ARVALID <= 1'b1;
      vif.S_AXI_RREADY  <= 1'b1;

      wait (vif.S_AXI_ARREADY);
      @(posedge vif.clk);
      vif.S_AXI_ARVALID <= 1'b0;

      wait (vif.S_AXI_RVALID);
      rdata = vif.S_AXI_RDATA;
      rresp = vif.S_AXI_RRESP;
      @(posedge vif.clk);
      vif.S_AXI_RREADY <= 1'b0;
    endtask

  endclass

endpackage

`endif
