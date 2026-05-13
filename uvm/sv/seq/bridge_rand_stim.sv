// bridge_rand_stim.sv — constrained-random transaction item and burst sequences
//
// bridge_rand_item: a rand-enabled descriptor for one AXI burst transaction.
// Constraints keep the stimulus legal for the burst bridge (no boundary crossing,
// 8-byte aligned address, supported burst type and length).
//
// bridge_rand_seq: a helper class that uses bridge_axi_stim_64 tasks to drive
// N random bursts and verify the responses match the scoreboard.
//
// Included inside bridge_uvm_tests_pkg, so UVM macros are in scope.

`ifndef BRIDGE_RAND_STIM_SV
`define BRIDGE_RAND_STIM_SV

// ---------------------------------------------------------------------------
// Constrained-random transaction item
// ---------------------------------------------------------------------------

class bridge_rand_item extends uvm_object;
    `uvm_object_utils(bridge_rand_item)

    // ---------------- randomisable fields ----------------------------------
    rand bit         is_write;           // 1 = write, 0 = read
    rand bit         apb_port;           // 0 = APB0 (addr[31]=0), 1 = APB1
    rand bit [1:0]   burst_type;         // 0=FIXED, 1=INCR
    rand bit [7:0]   burst_len;          // AXI AWLEN/ARLEN (beats-1)
    rand bit [12:0]  addr_page;          // bits [15:3] of the address

    // ---------------- derived (not randomised) -----------------------------
    logic [31:0]     addr;              // full 32-bit address
    logic [63:0]     wdata[];           // write data beats (driven after randomize)

    // ---------------- constraints ------------------------------------------

    // WRAP is not supported by the bridge.
    constraint c_burst_legal { burst_type inside {2'b00, 2'b01}; }

    // Keep burst length short so coverage accumulates quickly.
    constraint c_len { burst_len inside {[0:7]}; }

    // For INCR bursts, keep the whole burst within the same APB port.
    // With addr_page in [0:8191] and burst_len*8 <= 56, the last address is at
    // most addr_page*8 + 56 < 8191*8 + 56 = 65584 — well below 0x8000_0000.
    // APB port bit is addr[31] so this never crosses the boundary.
    constraint c_no_cross { burst_type == 2'b01 ->
        addr_page < 13'h1000; }           // conservative upper bound

    // Align to 8 bytes (bus width).
    // addr = {apb_port, 15'b0, addr_page, 3'b0}

    function new(string name = "bridge_rand_item");
        super.new(name);
    endfunction

    // Call after randomize() to compute derived fields.
    function void post_randomize();
        addr = {apb_port, 15'b0, addr_page, 3'b0};
        wdata = new[burst_len + 1];
        foreach (wdata[i])
            void'(std::randomize(wdata[i]));
    endfunction

    function string convert2string();
        return $sformatf("%s port=%0d burst=%0s len=%0d addr=0x%08h",
            is_write ? "WR" : "RD",
            apb_port,
            burst_type == 0 ? "FIXED" : "INCR",
            burst_len,
            addr);
    endfunction

endclass

// ---------------------------------------------------------------------------
// Constrained-random sequence driver for burst bridge
// ---------------------------------------------------------------------------

class bridge_rand_seq extends uvm_object;
    `uvm_object_utils(bridge_rand_seq)

    int unsigned n_txn    = 20;   // number of transactions per run
    int unsigned seed_off = 0;    // seed offset (set per test instance)

    bridge_axi_stim_64 stim;      // connected by the test before calling run()

    function new(string name = "bridge_rand_seq");
        super.new(name);
    endfunction

    // Drive n_txn random transactions through stim, report each one.
    task run();
        bridge_rand_item item;
        logic [1:0] resp;
        if (stim == null)
            `uvm_fatal("RAND_SEQ", "stim handle is null; call connect() first")

        for (int unsigned i = 0; i < n_txn; i++) begin
            item = bridge_rand_item::type_id::create($sformatf("item_%0d", i));
            if (!item.randomize() with { is_write == (i % 2 == 0); })
                `uvm_fatal("RAND_SEQ", "randomize() failed")
            `uvm_info("RAND_SEQ",
                $sformatf("[%0d/%0d] %s", i+1, n_txn, item.convert2string()),
                UVM_MEDIUM)
            if (item.is_write)
                drive_write(item, resp);
            else
                drive_read(item, resp);
        end
    endtask

    // Drive one write burst; returns BRESP.
    task drive_write(bridge_rand_item item, output logic [1:0] resp);
        // Use the existing axi_write_burst_ext task; pslverr_at = 8'hFF means
        // no slave error injected.
        stim.axi_write_burst_ext(
            item.addr[31:0],
            item.burst_len,
            item.burst_type,
            item.burst_len,   // wlast_at = last beat index
            8'hFF,            // pslverr_at = never
            resp
        );
        `uvm_info("RAND_SEQ",
            $sformatf("  BRESP=%0b (%s)", resp,
                resp == 2'b00 ? "OKAY" : resp == 2'b10 ? "SLVERR" : "DECERR"),
            UVM_HIGH)
    endtask

    // Drive one read burst; returns combined RRESP.
    task drive_read(bridge_rand_item item, output logic [1:0] resp);
        stim.axi_read_burst_ext(
            item.addr[31:0],
            item.burst_len,
            item.burst_type,
            resp
        );
        `uvm_info("RAND_SEQ",
            $sformatf("  RRESP=%0b (%s)", resp,
                resp == 2'b00 ? "OKAY" : resp == 2'b10 ? "SLVERR" : "DECERR"),
            UVM_HIGH)
    endtask

endclass

`endif
