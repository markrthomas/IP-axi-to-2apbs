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
            wdata[i] = {$urandom(), $urandom()};  // avoid std::randomize portability issues
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

    // Drive n_txn random transactions (write phase then read phase) through stim.
    // Two-pass ordering ensures reads always see previously-written data, so
    // coverage of read responses is meaningful rather than returning zero.
    task run();
        bridge_rand_item items[];
        logic [1:0] resp;
        int unsigned half;
        if (stim == null)
            `uvm_fatal("RAND_SEQ", "stim handle is null; connect stim before calling run()")

        half  = n_txn / 2;
        items = new[n_txn];

        // Phase 1: randomize all items and drive writes.
        `uvm_info("RAND_SEQ", $sformatf("Phase 1: %0d writes", half), UVM_MEDIUM)
        for (int unsigned i = 0; i < half; i++) begin
            items[i] = bridge_rand_item::type_id::create($sformatf("wr_%0d", i));
            if (!items[i].randomize() with { is_write == 1'b1; })
                `uvm_fatal("RAND_SEQ", "randomize() failed on write item")
            `uvm_info("RAND_SEQ",
                $sformatf("  [W%0d] %s", i, items[i].convert2string()), UVM_MEDIUM)
            drive_write(items[i], resp);
        end

        // Phase 2: read back the same addresses.
        `uvm_info("RAND_SEQ", $sformatf("Phase 2: %0d reads", half), UVM_MEDIUM)
        for (int unsigned i = 0; i < half; i++) begin
            `uvm_info("RAND_SEQ",
                $sformatf("  [R%0d] addr=0x%08h len=%0d", i, items[i].addr, items[i].burst_len),
                UVM_MEDIUM)
            drive_read(items[i], resp);
        end

        // Phase 3: any remaining items (when n_txn is odd) as random writes.
        for (int unsigned i = half; i < n_txn; i++) begin
            items[i] = bridge_rand_item::type_id::create($sformatf("extra_%0d", i));
            if (!items[i].randomize() with { is_write == 1'b1; })
                `uvm_fatal("RAND_SEQ", "randomize() failed on extra item")
            drive_write(items[i], resp);
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

// ---------------------------------------------------------------------------
// Three-phase stress sequence — mirrors test/tb_stress_burst.v
//
// Phase 1 (seed): write 16 words to each APB port at fixed addresses.
// Phase 2 (random): n_txn random single/burst reads and writes across both
//   ports; reads only target addresses that were previously written.
// Phase 3 (sweep): read back all 16 seed words from each port.
//
// Data integrity is verified by the scoreboard (slv_shadow), not here.
// ---------------------------------------------------------------------------

class bridge_stress_seq extends uvm_object;
    `uvm_object_utils(bridge_stress_seq)

    int unsigned n_txn    = 100;   // random transaction count (phase 2)
    int unsigned seed_off = 0;     // per-instance seed offset

    bridge_axi_stim_64 stim;       // connected by the test before calling run()

    // Sparse set of (port<<16 | addr_page) keys that have been written.
    bit sh_written[int unsigned];

    function new(string name = "bridge_stress_seq");
        super.new(name);
    endfunction

    // Compose the sh_written key from a rand item.
    function automatic int unsigned mk_key(int unsigned port, int unsigned page);
        return (port << 16) | page;
    endfunction

    // Record all pages written by item (INCR touches consecutive pages,
    // FIXED touches only one page repeated).
    function void mark_written(bridge_rand_item item);
        int unsigned port  = int unsigned'(item.apb_port);
        int unsigned page0 = int unsigned'(item.addr_page);
        if (item.burst_type == 2'b01) begin   // INCR
            for (int unsigned b = 0; b <= int unsigned'(item.burst_len); b++)
                sh_written[mk_key(port, page0 + b)] = 1;
        end else begin                         // FIXED
            sh_written[mk_key(port, page0)] = 1;
        end
    endfunction

    // Return 1 if every beat of a read burst has a written backing entry.
    function bit all_written(bridge_rand_item item);
        int unsigned port  = int unsigned'(item.apb_port);
        int unsigned page0 = int unsigned'(item.addr_page);
        if (item.burst_type == 2'b01) begin
            for (int unsigned b = 0; b <= int unsigned'(item.burst_len); b++)
                if (!sh_written.exists(mk_key(port, page0 + b))) return 0;
        end else begin
            if (!sh_written.exists(mk_key(port, page0))) return 0;
        end
        return 1;
    endfunction

    // -----------------------------------------------------------------------
    // Main entry point.
    // -----------------------------------------------------------------------
    task run();
        logic [1:0] resp;

        if (stim == null)
            `uvm_fatal("STRESS_SEQ", "stim handle is null; connect stim before calling run()")

        // Phase 1: seed 16 single-beat writes to each APB port.
        `uvm_info("STRESS_SEQ", "Phase 1: seeding both APB ports", UVM_MEDIUM)
        for (int unsigned i = 0; i < 16; i++) begin
            logic [31:0] a0 = {1'b0, 15'b0, 13'(i), 3'b0};   // APB0
            logic [31:0] a1 = {1'b1, 15'b0, 13'(i), 3'b0};   // APB1
            stim.axi_write_burst_ext(a0, 8'h00, 2'b01, 8'h00, 8'hFF, resp);
            sh_written[mk_key(0, i)] = 1;
            stim.axi_write_burst_ext(a1, 8'h00, 2'b01, 8'h00, 8'hFF, resp);
            sh_written[mk_key(1, i)] = 1;
        end

        // Phase 2: n_txn random single/burst transactions.
        `uvm_info("STRESS_SEQ",
            $sformatf("Phase 2: %0d random transactions", n_txn), UVM_MEDIUM)
        begin
            int unsigned attempts;
            int unsigned done;
            done     = 0;
            attempts = 0;
            while (done < n_txn) begin
                bridge_rand_item item;
                item = bridge_rand_item::type_id::create(
                    $sformatf("stress_%0d", done));

                if (!item.randomize())
                    `uvm_fatal("STRESS_SEQ", "randomize() failed")

                // For reads, skip if no backing write exists (retry).
                if (!item.is_write && !all_written(item)) begin
                    attempts++;
                    if (attempts > n_txn * 4) begin
                        `uvm_warning("STRESS_SEQ",
                            "Too many read-skip retries; forcing write")
                        void'(item.randomize() with { is_write == 1'b1; });
                    end else
                        continue;
                end

                `uvm_info("STRESS_SEQ",
                    $sformatf("  [T%0d] %s", done, item.convert2string()),
                    UVM_HIGH)

                if (item.is_write) begin
                    stim.axi_write_burst_ext(
                        item.addr, item.burst_len, item.burst_type,
                        item.burst_len, 8'hFF, resp);
                    mark_written(item);
                end else begin
                    stim.axi_read_burst_ext(
                        item.addr, item.burst_len, item.burst_type, resp);
                end
                done++;
                attempts = 0;
            end
        end

        // Phase 3: sweep-read the 16 seed words from each port.
        `uvm_info("STRESS_SEQ", "Phase 3: sweep read-back", UVM_MEDIUM)
        for (int unsigned i = 0; i < 16; i++) begin
            logic [31:0] a0 = {1'b0, 15'b0, 13'(i), 3'b0};
            logic [31:0] a1 = {1'b1, 15'b0, 13'(i), 3'b0};
            stim.axi_read_burst_ext(a0, 8'h00, 2'b01, resp);
            stim.axi_read_burst_ext(a1, 8'h00, 2'b01, resp);
        end

        `uvm_info("STRESS_SEQ",
            $sformatf("bridge_stress_seq: DONE (%0d txn)", n_txn), UVM_MEDIUM)
    endtask

endclass

`endif
