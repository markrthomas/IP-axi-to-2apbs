`ifndef BRIDGE_STIMULUS_PKG_SV
`define BRIDGE_STIMULUS_PKG_SV

/* verilator lint_off DECLFILENAME */
package bridge_stimulus_pkg;
  timeunit 1ns;
  timeprecision 1ps;

  typedef virtual axi4_master_if #(.ID_WIDTH(4), .ADDR_WIDTH(32), .DATA_WIDTH(64)) v_axi_if_64_t;

  typedef virtual axi4_master_if #(.ID_WIDTH(4), .ADDR_WIDTH(32), .DATA_WIDTH(32)) v_axi_if_32_t;

  typedef virtual apb_burst_ext_side_if v_apb_side_if_t;

  typedef virtual apb_sel_tracker_if v_apb_sel_tracker_t;

  class bridge_axi_stim_64;
    v_axi_if_64_t vif;
    v_apb_side_if_t sif;

    function void set_if(v_axi_if_64_t v, v_apb_side_if_t s = null);
      vif = v;
      sif = s;
    endfunction

    function void drv_init_zeros();
      vif.S_AXI_AWID = 0;
      vif.S_AXI_AWADDR = 0;
      vif.S_AXI_AWLEN = 0;
      vif.S_AXI_AWSIZE = 0;
      vif.S_AXI_AWBURST = 0;
      vif.S_AXI_AWPROT = 0;
      vif.S_AXI_AWVALID = 0;
      vif.S_AXI_WDATA = 0;
      vif.S_AXI_WSTRB = 0;
      vif.S_AXI_WLAST = 0;
      vif.S_AXI_WVALID = 0;
      vif.S_AXI_BREADY = 0;
      vif.S_AXI_ARID = 0;
      vif.S_AXI_ARADDR = 0;
      vif.S_AXI_ARLEN = 0;
      vif.S_AXI_ARSIZE = 0;
      vif.S_AXI_ARBURST = 0;
      vif.S_AXI_ARPROT = 0;
      vif.S_AXI_ARVALID = 0;
      vif.S_AXI_RREADY = 0;
    endfunction

    task wait_reset_after_start();
      @(posedge vif.rst_n);
      @(posedge vif.clk);
    endtask

    task axi_single_write_together_ok(input logic [31:0] addr, input logic [63:0] data);
      @(posedge vif.clk);
      vif.S_AXI_AWID <= 0;
      vif.S_AXI_AWADDR <= addr;
      vif.S_AXI_AWLEN <= 8'd0;
      vif.S_AXI_AWSIZE <= 3'h3;
      vif.S_AXI_AWBURST <= 2'h1;
      vif.S_AXI_AWPROT <= 3'h0;
      vif.S_AXI_AWVALID <= 1'h1;
      vif.S_AXI_WDATA <= data;
      vif.S_AXI_WSTRB <= {8 {1'h1}};
      vif.S_AXI_WLAST <= 1'h1;
      vif.S_AXI_WVALID <= 1'h1;
      vif.S_AXI_BREADY <= 1'h1;
      wait (vif.S_AXI_AWREADY && vif.S_AXI_WREADY);
      @(posedge vif.clk);
      vif.S_AXI_AWVALID <= 1'h0;
      vif.S_AXI_WVALID <= 1'h0;
      wait (vif.S_AXI_BVALID);
      if (vif.S_AXI_BRESP !== 2'b00) begin
        $display("ERROR: BRESP not OKAY: %b", vif.S_AXI_BRESP);
        $fatal;
      end
      @(posedge vif.clk);
      vif.S_AXI_BREADY <= 1'h0;
    endtask

    task axi_single_read_standard(input logic [31:0] addr, output logic [63:0] data,
                                  input logic expect_ok);
      @(posedge vif.clk);
      vif.S_AXI_ARID <= 0;
      vif.S_AXI_ARADDR <= addr;
      vif.S_AXI_ARLEN <= 8'd0;
      vif.S_AXI_ARSIZE <= 3'h3;
      vif.S_AXI_ARBURST <= 2'h1;
      vif.S_AXI_ARPROT <= 3'h0;
      vif.S_AXI_ARVALID <= 1'h1;
      vif.S_AXI_RREADY <= 1'h1;
      wait (vif.S_AXI_ARREADY);
      @(posedge vif.clk);
      vif.S_AXI_ARVALID <= 1'h0;
      wait (vif.S_AXI_RVALID);
      if (expect_ok && vif.S_AXI_RRESP !== 2'b00) begin
        $display("ERROR: RRESP not OKAY: %b", vif.S_AXI_RRESP);
        $fatal;
      end
      data = vif.S_AXI_RDATA;
      if (expect_ok && !vif.S_AXI_RLAST) begin
        $display("ERROR: RLAST not asserted");
        $fatal;
      end
      @(posedge vif.clk);
      vif.S_AXI_RREADY <= 1'h0;
    endtask

    task axi_single_write_burst_style(input logic [31:0] addr, input logic [63:0] data,
                                      input logic [1:0] expect_resp);
      @(posedge vif.clk);
      vif.S_AXI_AWID <= 0;
      vif.S_AXI_AWADDR <= addr;
      vif.S_AXI_AWLEN <= 8'd0;
      vif.S_AXI_AWSIZE <= 3'h3;
      vif.S_AXI_AWBURST <= 2'h1;
      vif.S_AXI_AWPROT <= 3'h0;
      vif.S_AXI_AWVALID <= 1'h1;
      vif.S_AXI_WDATA <= data;
      vif.S_AXI_WSTRB <= {8 {1'h1}};
      vif.S_AXI_WLAST <= 1'h1;
      vif.S_AXI_WVALID <= 1'h1;
      vif.S_AXI_BREADY <= 1'h1;
      wait (vif.S_AXI_AWREADY);
      @(posedge vif.clk);
      vif.S_AXI_AWVALID <= 1'h0;
      wait (vif.S_AXI_WREADY);
      @(posedge vif.clk);
      vif.S_AXI_WVALID <= 1'h0;
      wait (vif.S_AXI_BVALID);
      if (vif.S_AXI_BRESP !== expect_resp) begin
        $display("ERROR: Write BRESP mismatch Got %b exp %b", vif.S_AXI_BRESP,
                 expect_resp);
        $fatal;
      end
      @(posedge vif.clk);
      vif.S_AXI_BREADY <= 1'h0;
    endtask

    task axi_single_read_burst_style(input logic [31:0] addr, input logic [1:0] expect_resp,
                                     output logic [63:0] data);
      @(posedge vif.clk);
      vif.S_AXI_ARID <= 0;
      vif.S_AXI_ARADDR <= addr;
      vif.S_AXI_ARLEN <= 8'd0;
      vif.S_AXI_ARSIZE <= 3'h3;
      vif.S_AXI_ARBURST <= 2'h1;
      vif.S_AXI_ARPROT <= 3'h0;
      vif.S_AXI_ARVALID <= 1'h1;
      vif.S_AXI_RREADY <= 1'h1;
      wait (vif.S_AXI_ARREADY);
      @(posedge vif.clk);
      vif.S_AXI_ARVALID <= 1'h0;
      wait (vif.S_AXI_RVALID);
      if (vif.S_AXI_RRESP !== expect_resp) begin
        $display("ERROR: Read RRESP mismatch Got %b exp %b", vif.S_AXI_RRESP, expect_resp);
        $fatal;
      end
      data = vif.S_AXI_RDATA;
      if (!vif.S_AXI_RLAST) begin
        $display("ERROR: RLAST single-beat read missing");
        $fatal;
      end
      @(posedge vif.clk);
      vif.S_AXI_RREADY <= 1'h0;
    endtask

    task axi_crossing_write_decerr();
      integer wseed;
      @(posedge vif.clk);
      vif.S_AXI_AWID <= 0;
      vif.S_AXI_AWADDR <= 32'h7FFF_FFF8;
      vif.S_AXI_AWLEN <= 8'h1;
      vif.S_AXI_AWSIZE <= 3'h3;
      vif.S_AXI_AWBURST <= 2'h1;
      vif.S_AXI_AWPROT <= 3'h0;
      vif.S_AXI_AWVALID <= 1'h1;
      vif.S_AXI_WSTRB <= {8 {1'h1}};
      vif.S_AXI_BREADY <= 1'h1;
      wait (vif.S_AXI_AWREADY);
      @(posedge vif.clk);
      vif.S_AXI_AWVALID <= 1'h0;
      wseed = 32'h3f9012ab;
      repeat (2) begin
        vif.S_AXI_WDATA <= 64'($random(wseed));
        vif.S_AXI_WLAST <= ((vif.S_AXI_WDATA == 'd1) ? 1'h1 : 1'h0);
        vif.S_AXI_WVALID <= 1'h1;
        wait (vif.S_AXI_WREADY);
        @(posedge vif.clk);
        vif.S_AXI_WVALID <= 1'h0;
      end
      wait (vif.S_AXI_BVALID);
      if (vif.S_AXI_BRESP !== 2'h3) begin
        $display("ERROR: Expected DECERR crossing write got %b", vif.S_AXI_BRESP);
        $fatal;
      end
      @(posedge vif.clk);
      vif.S_AXI_BREADY <= 1'h0;
    endtask

    task axi_write_burst_ext(input logic [31:0] addr, input logic [7:0] len,
                             input logic [1:0] burst, input logic [7:0] wlast_at,
                             input logic [7:0] pslverr_at, output logic [1:0] resp);
      int unsigned i;
      if (sif == null) begin
        $display("ERROR: burst-ext needs apb_burst_ext_side_if");
        $fatal;
      end
      @(posedge vif.clk);
      vif.S_AXI_AWADDR <= addr;
      vif.S_AXI_AWLEN <= len;
      vif.S_AXI_AWSIZE <= 3'h3;
      vif.S_AXI_AWBURST <= burst;
      vif.S_AXI_AWVALID <= 1'h1;
      vif.S_AXI_BREADY <= 1'h1;
      while (!vif.S_AXI_AWREADY)
        @(posedge vif.clk);
      @(posedge vif.clk);
      vif.S_AXI_AWVALID <= 1'h0;
      for (i = 0; i <= len; i++) begin
        vif.S_AXI_WDATA <= 64'(addr) ^ 64'(i);
        vif.S_AXI_WSTRB <= 8'hFF;
        vif.S_AXI_WVALID <= 1'h1;
        vif.S_AXI_WLAST <= (i == 32'(wlast_at));
        if (addr[31])
          sif.PSLVERR1 <= (i == 32'(pslverr_at));
        else
          sif.PSLVERR0 <= (i == 32'(pslverr_at));
        while (!vif.S_AXI_WREADY)
          @(posedge vif.clk);
        @(posedge vif.clk);
        vif.S_AXI_WVALID <= 1'h0;
        vif.S_AXI_WLAST <= 1'h0;
        sif.PSLVERR0 <= 1'h0;
        sif.PSLVERR1 <= 1'h0;
      end
      while (!vif.S_AXI_BVALID)
        @(posedge vif.clk);
      resp = vif.S_AXI_BRESP;
      @(posedge vif.clk);
      vif.S_AXI_BREADY <= 1'h0;
    endtask

    task axi_read_burst_ext(input logic [31:0] addr, input logic [7:0] len,
                            input logic [1:0] burst, output logic [1:0] combined_resp);
      int unsigned i;
      @(posedge vif.clk);
      vif.S_AXI_ARADDR <= addr;
      vif.S_AXI_ARLEN <= len;
      vif.S_AXI_ARSIZE <= 3'h3;
      vif.S_AXI_ARBURST <= burst;
      vif.S_AXI_ARVALID <= 1'h1;
      vif.S_AXI_RREADY <= 1'h1;
      while (!vif.S_AXI_ARREADY)
        @(posedge vif.clk);
      @(posedge vif.clk);
      vif.S_AXI_ARVALID <= 1'h0;
      combined_resp = 2'h0;
      for (i = 0; i <= len; i++) begin
        while (!vif.S_AXI_RVALID)
          @(posedge vif.clk);
        if (vif.S_AXI_RRESP > combined_resp)
          combined_resp = vif.S_AXI_RRESP;
        if (vif.S_AXI_RLAST != (i == 32'(len)))
          $display("ERROR: RLAST mismatch beat %0d", i);
        @(posedge vif.clk);
      end
      vif.S_AXI_RREADY <= 1'h0;
    endtask

    task run_mirror_simple();
      logic [63:0] rdata0;
      drv_init_zeros();
      wait_reset_after_start();
      axi_single_write_together_ok(32'h0000_0010, 64'hDEAD_BEEF_CAFE_BABE);
      axi_single_read_standard(32'h0000_0010, rdata0, 1'b1);
      if (rdata0 !== 64'hDEAD_BEEF_CAFE_BABE) begin
        $display("ERROR: APB0 mismatch Got %h", rdata0);
        $fatal;
      end
      axi_single_write_together_ok(32'h8000_0020, 64'h1234_5678_9ABC_DEF0);
      axi_single_read_standard(32'h8000_0020, rdata0, 1'b1);
      if (rdata0 !== 64'h1234_5678_9ABC_DEF0) begin
        $display("ERROR: APB1 mismatch Got %h", rdata0);
        $fatal;
      end
      $display("SIMPLE TEST PASSED");
    endtask

    task run_mirror_burst();
      logic [63:0] rd;
      drv_init_zeros();
      wait_reset_after_start();
      axi_single_write_burst_style(32'h0000_0010, 64'hDEAD_BEEF_CAFE_BABE, 2'b00);
      axi_single_read_burst_style(32'h0000_0010, 2'b00, rd);
      if (rd !== 64'hDEAD_BEEF_CAFE_BABE) begin
        $display("ERROR: APB0 read mismatch Got %h", rd);
        $fatal;
      end
      axi_single_write_burst_style(32'h8000_0020, 64'h1234_5678_9ABC_DEF0, 2'b00);
      axi_single_read_burst_style(32'h8000_0020, 2'b00, rd);
      if (rd !== 64'h1234_5678_9ABC_DEF0) begin
        $display("ERROR: APB1 read mismatch Got %h", rd);
        $fatal;
      end
      axi_crossing_write_decerr();
      $display("TEST PASSED");
    endtask

    task run_mirror_burst_ext();
      logic [1:0] res;
      int pready_rand_seed;
      drv_init_zeros();
      @(posedge vif.rst_n);
      repeat (5)
        @(posedge vif.clk);

      axi_write_burst_ext(32'h0000_1000, 2, 2'b01, 8'd2, 8'd1, res);
      if (res !== 2'b10)
        $display("FAILURE T1 got %b", res);

      axi_write_burst_ext(32'h0000_2000, 2, 2'b01, 8'd0, 8'hFF, res);
      if (res !== 2'b10)
        $display("FAILURE T2 got %b", res);

      axi_write_burst_ext(32'h0000_3000, 1, 2'b01, 8'hFF, 8'hFF, res);
      if (res !== 2'b10)
        $display("FAILURE T3 got %b", res);

      axi_write_burst_ext(32'h0000_4000, 3, 2'b00, 8'd3, 8'hFF, res);
      if (res !== 2'b00)
        $display("FAILURE T4 got %b", res);
      axi_read_burst_ext(32'h0000_4000, 3, 2'b00, res);
      if (res !== 2'b00)
        $display("FAILURE T4 read got %b", res);

      axi_write_burst_ext(32'h8000_1000, 1, 2'b01, 8'd1, 8'hFF, res);
      if (res !== 2'b00)
        $display("FAILURE T5 got %b", res);
      axi_read_burst_ext(32'h8000_1000, 1, 2'b01, res);
      if (res !== 2'b00)
        $display("FAILURE T5 read got %b", res);

      axi_write_burst_ext(32'h7FFF_FFF8, 1, 2'b01, 8'd1, 8'hFF, res);
      if (res !== 2'b11)
        $display("FAILURE T6 got %b", res);

      fork
        begin
          pready_rand_seed = 32'h6b4d2e19;
          repeat (100) begin
            @(posedge vif.clk);
            sif.PREADY0 <= 1'($unsigned($random(pready_rand_seed)));
            sif.PREADY1 <= 1'($unsigned($random(pready_rand_seed)));
          end
          sif.PREADY0 <= 1'b1;
          sif.PREADY1 <= 1'b1;
        end
        begin
          axi_write_burst_ext(32'h0000_5000, 7, 2'b01, 8'd7, 8'hFF, res);
          if (res !== 2'b00)
            $display("FAILURE T7 write got %b", res);
          axi_read_burst_ext(32'h0000_5000, 7, 2'b01, res);
          if (res !== 2'b00)
            $display("FAILURE T7 read got %b", res);
        end
      join

      $display("All repro tests complete");
    endtask
  endclass

  //---------------------------------------------------------------------------
  class bridge_axi_stim_32;

    v_axi_if_32_t vif;

    function void connect_if(v_axi_if_32_t v);
      vif = v;
    endfunction

    function void drv_init();
      vif.S_AXI_AWID = 0;
      vif.S_AXI_AWADDR = 0;
      vif.S_AXI_AWLEN = 0;
      vif.S_AXI_AWSIZE = 0;
      vif.S_AXI_AWBURST = 0;
      vif.S_AXI_AWPROT = 0;
      vif.S_AXI_AWVALID = 0;
      vif.S_AXI_WDATA = 0;
      vif.S_AXI_WSTRB = 0;
      vif.S_AXI_WLAST = 0;
      vif.S_AXI_WVALID = 0;
      vif.S_AXI_BREADY = 0;
      vif.S_AXI_ARID = 0;
      vif.S_AXI_ARADDR = 0;
      vif.S_AXI_ARLEN = 0;
      vif.S_AXI_ARSIZE = 0;
      vif.S_AXI_ARBURST = 0;
      vif.S_AXI_ARPROT = 0;
      vif.S_AXI_ARVALID = 0;
      vif.S_AXI_RREADY = 0;
    endfunction

    task axi_write_32(input logic [31:0] addr, input logic [31:0] data);
      @(posedge vif.clk);
      vif.S_AXI_AWADDR <= addr;
      vif.S_AXI_AWLEN <= 8'd0;
      vif.S_AXI_AWSIZE <= 3'h2;
      vif.S_AXI_AWBURST <= 2'h1;
      vif.S_AXI_AWVALID <= 1'h1;
      vif.S_AXI_BREADY <= 1'h1;
      vif.S_AXI_WDATA <= data;
      vif.S_AXI_WSTRB <= 4'hF;
      vif.S_AXI_WVALID <= 1'h1;
      vif.S_AXI_WLAST <= 1'h1;
      fork
        begin
          while (!vif.S_AXI_AWREADY)
            @(posedge vif.clk);
          @(posedge vif.clk);
          vif.S_AXI_AWVALID <= 1'h0;
        end
        begin
          while (!vif.S_AXI_WREADY)
            @(posedge vif.clk);
          @(posedge vif.clk);
          vif.S_AXI_WVALID <= 1'h0;
        end
      join

      while (!vif.S_AXI_BVALID)
        @(posedge vif.clk);
      @(posedge vif.clk);
      vif.S_AXI_BREADY <= 1'h0;
    endtask

    task run_mirror_param(v_apb_sel_tracker_t mon);
      drv_init();
      @(posedge vif.rst_n);
      repeat (5)
        @(posedge vif.clk);

      mon.clear_pulse();
      $display("Test Parameterized: APB0 (bit 20=0)");
      axi_write_32(32'h0000_0000, 32'hAAAA_BBBB);
      @(posedge vif.clk);
      if (!mon.saw0) begin
        $display("FAILURE: Expected PSEL0");
        $fatal;
      end else
        $display("SUCCESS: PSEL0 asserted");

      mon.clear_pulse();
      $display("Test Parameterized: APB1 (bit 20=1)");
      axi_write_32(32'h0010_0000, 32'hCCCC_DDDD);
      @(posedge vif.clk);
      if (!mon.saw1) begin
        $display("FAILURE: Expected PSEL1");
        $fatal;
      end else
        $display("SUCCESS: PSEL1 asserted");

      $display("Test Parameterized: Wrong Size (expect DECERR)");
      @(posedge vif.clk);
      vif.S_AXI_AWADDR <= 32'h0;
      vif.S_AXI_AWLEN <= 8'd0;
      vif.S_AXI_AWSIZE <= 3'h3;
      vif.S_AXI_AWBURST <= 2'h1;
      vif.S_AXI_AWVALID <= 1'h1;
      vif.S_AXI_BREADY <= 1'h1;
      vif.S_AXI_WDATA <= 32'h0;
      vif.S_AXI_WSTRB <= 4'hF;
      vif.S_AXI_WVALID <= 1'h1;
      vif.S_AXI_WLAST <= 1'h1;
      fork
        begin
          while (!vif.S_AXI_AWREADY)
            @(posedge vif.clk);
          @(posedge vif.clk) vif.S_AXI_AWVALID <= 1'h0;
        end
        begin
          while (!vif.S_AXI_WREADY)
            @(posedge vif.clk);
          @(posedge vif.clk) vif.S_AXI_WVALID <= 1'h0;
        end
      join
      while (!vif.S_AXI_BVALID)
        @(posedge vif.clk);
      if (vif.S_AXI_BRESP !== 2'b11) begin
        $display(
            "FAILURE: Expected DECERR for 64-bit size on 32-bit bridge got %b",
            vif.S_AXI_BRESP);
        $fatal;
      end else
        $display("SUCCESS: DECERR for wrong size");

      @(posedge vif.clk);
      $display("Parameterized test complete");
    endtask
  endclass

endpackage
/* verilator lint_on DECLFILENAME */

`endif
