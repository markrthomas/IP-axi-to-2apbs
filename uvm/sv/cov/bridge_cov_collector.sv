// bridge_cov_collector.sv — functional coverage for the AXI-to-APB bridge
//
// Subscribes to the AXI write, AXI read, and APB analysis ports produced by
// the bridge monitors.  Three covergroups capture transaction-level stimulus
// and response coverage; crosses expose combinations not seen in isolation.
//
// Wired into bridge_env via cfg.has_coverage (default true).

`ifndef BRIDGE_COV_COLLECTOR_SV
`define BRIDGE_COV_COLLECTOR_SV

// Must be declared before the class that uses them.
`uvm_analysis_imp_decl(_axi_wr)
`uvm_analysis_imp_decl(_axi_rd)
`uvm_analysis_imp_decl(_apb_cov)

class bridge_cov_collector extends uvm_component;
    `uvm_component_utils(bridge_cov_collector)

    uvm_analysis_imp_axi_wr  #(bridge_axi_wr_tr, bridge_cov_collector) axi_wr_imp;
    uvm_analysis_imp_axi_rd  #(bridge_axi_rd_tr, bridge_cov_collector) axi_rd_imp;
    uvm_analysis_imp_apb_cov #(bridge_apb_tr,    bridge_cov_collector) apb_imp;

    // Current-transaction handles; covergroups sample these at write() time.
    bridge_axi_wr_tr cur_wr;
    bridge_axi_rd_tr cur_rd;
    bridge_apb_tr    cur_apb;

    // ------------------------------------------------------------------
    // AXI write covergroup
    // ------------------------------------------------------------------
    covergroup cg_axi_write;
        cp_burst_type: coverpoint cur_wr.awburst[1:0] {
            bins fixed = {2'b00};
            bins incr  = {2'b01};
        }
        cp_burst_len: coverpoint cur_wr.awlen {
            bins single   = {8'd0};
            bins two_beat = {8'd1};
            bins tri_beat = {8'd2};
            bins quad     = {8'd3};
            bins longer   = {[8'd4 : 8'd255]};
        }
        cp_apb_port: coverpoint cur_wr.addr[31] {
            bins port0 = {1'b0};
            bins port1 = {1'b1};
        }
        cp_bresp: coverpoint cur_wr.bresp {
            bins okay   = {2'b00};
            bins slverr = {2'b10};
            bins decerr = {2'b11};
        }
        cx_type_len:  cross cp_burst_type, cp_burst_len;
        cx_len_port:  cross cp_burst_len,  cp_apb_port;
        cx_port_resp: cross cp_apb_port,   cp_bresp;
    endgroup

    // ------------------------------------------------------------------
    // AXI read covergroup
    // ------------------------------------------------------------------
    covergroup cg_axi_read;
        cp_burst_type: coverpoint cur_rd.arburst[1:0] {
            bins fixed = {2'b00};
            bins incr  = {2'b01};
        }
        cp_burst_len: coverpoint cur_rd.arlen {
            bins single   = {8'd0};
            bins two_beat = {8'd1};
            bins tri_beat = {8'd2};
            bins quad     = {8'd3};
            bins longer   = {[8'd4 : 8'd255]};
        }
        cp_apb_port: coverpoint cur_rd.addr[31] {
            bins port0 = {1'b0};
            bins port1 = {1'b1};
        }
        cp_rresp: coverpoint cur_rd.rresp {
            bins okay   = {2'b00};
            bins slverr = {2'b10};
            bins decerr = {2'b11};
        }
        cx_type_len:  cross cp_burst_type, cp_burst_len;
        cx_len_port:  cross cp_burst_len,  cp_apb_port;
        cx_port_resp: cross cp_apb_port,   cp_rresp;
    endgroup

    // ------------------------------------------------------------------
    // APB transaction covergroup
    // ------------------------------------------------------------------
    covergroup cg_apb;
        cp_port: coverpoint cur_apb.port {
            bins apb0 = {0};
            bins apb1 = {1};
        }
        cp_dir: coverpoint cur_apb.pwrite {
            bins read  = {1'b0};
            bins write = {1'b1};
        }
        cp_slverr: coverpoint cur_apb.pslverr {
            bins ok    = {1'b0};
            bins error = {1'b1};
        }
        cp_strb_full: coverpoint (cur_apb.pstrb == 8'hFF) {
            bins full    = {1'b1};
            bins partial = {1'b0};
        }
        cx_port_dir:   cross cp_port,  cp_dir;
        cx_dir_slverr: cross cp_dir,   cp_slverr;
        cx_port_strb:  cross cp_port,  cp_strb_full;
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_axi_write = new();
        cg_axi_read  = new();
        cg_apb       = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        axi_wr_imp = new("axi_wr_imp", this);
        axi_rd_imp = new("axi_rd_imp", this);
        apb_imp    = new("apb_imp",    this);
    endfunction

    function void write_axi_wr(bridge_axi_wr_tr tr);
        cur_wr = tr;
        cg_axi_write.sample();
    endfunction

    function void write_axi_rd(bridge_axi_rd_tr tr);
        cur_rd = tr;
        cg_axi_read.sample();
    endfunction

    function void write_apb_cov(bridge_apb_tr tr);
        cur_apb = tr;
        cg_apb.sample();
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info(get_type_name(),
            $sformatf("[COV] AXI-write=%.1f%%  AXI-read=%.1f%%  APB=%.1f%%",
                cg_axi_write.get_coverage(),
                cg_axi_read.get_coverage(),
                cg_apb.get_coverage()),
            UVM_MEDIUM)
    endfunction

endclass

`endif
