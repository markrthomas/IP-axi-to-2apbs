// Verilator coverage harness for axi4_to_apb4_2x_simple.
// Exercises: write/read to APB0/1, illegal-AWLEN write, illegal-ARLEN read,
// PSLVERR on both ports, non-zero AWPROT/ARPROT.
#include "Vaxi4_to_apb4_2x_simple.h"
#include "verilated.h"
#if VM_COVERAGE
#include "verilated_cov.h"
#endif
#include <cstdint>

static uint64_t g_time = 0;
double sc_time_stamp() { return (double)g_time; }

static Vaxi4_to_apb4_2x_simple* top;

// When non-zero, inject PSLVERR on the given port for the next APB access.
static int g_slverr_port = -1;   // 0 or 1; -1 = no injection
// Number of wait states the APB slave inserts before asserting PREADY.
static int g_wait_states = 0;

// Per-port wait-state countdown: decremented each cycle PENABLE is high;
// PREADY is asserted only when the counter reaches zero.
static int g_ws_cnt0 = 0;
static int g_ws_cnt1 = 0;

static void apb_slave() {
    // Update per-port counters and drive PREADY.
    if (top->PENABLE0) {
        if (g_ws_cnt0 > 0) { g_ws_cnt0--; top->PREADY0 = 0; }
        else                { top->PREADY0 = 1; }
    } else {
        g_ws_cnt0 = g_wait_states;
        top->PREADY0 = 0;
    }
    if (top->PENABLE1) {
        if (g_ws_cnt1 > 0) { g_ws_cnt1--; top->PREADY1 = 0; }
        else                { top->PREADY1 = 1; }
    } else {
        g_ws_cnt1 = g_wait_states;
        top->PREADY1 = 0;
    }
    top->PRDATA0  = (uint64_t)0xDEADBEEFCAFEBABEULL;
    top->PRDATA1  = (uint64_t)0x0123456789ABCDEFULL;
    // Inject PSLVERR when requested: hold it high while PENABLE is asserted.
    if (g_slverr_port == 0 && top->PENABLE0) {
        top->PSLVERR0 = 1; top->PSLVERR1 = 0;
    } else if (g_slverr_port == 1 && top->PENABLE1) {
        top->PSLVERR0 = 0; top->PSLVERR1 = 1;
    } else {
        top->PSLVERR0 = 0; top->PSLVERR1 = 0;
    }
}

static void tick() {
    apb_slave();
    top->ACLK = 1; top->eval();
    top->ACLK = 0; top->eval();
    ++g_time;
}

// Drive a single-beat AXI write; wait for B completion.
// awlen != 0 triggers the illegal-burst error path.
static void write_single(uint32_t addr, uint64_t data,
                         uint8_t awlen = 0, uint8_t awprot = 0) {
    top->S_AXI_AWVALID = 1;
    top->S_AXI_AWADDR  = addr;
    top->S_AXI_AWID    = 1;
    top->S_AXI_AWLEN   = awlen;
    top->S_AXI_AWSIZE  = 3;
    top->S_AXI_AWBURST = 1;
    top->S_AXI_AWPROT  = awprot;
    top->S_AXI_WVALID  = 1;
    top->S_AXI_WDATA   = data;
    top->S_AXI_WSTRB   = 0xFF;
    top->S_AXI_WLAST   = 1;
    top->S_AXI_BREADY  = 1;

    for (int i = 0; i < 64; i++) {
        apb_slave();
        bool aw_hs = top->S_AXI_AWVALID && top->S_AXI_AWREADY;
        bool w_hs  = top->S_AXI_WVALID  && top->S_AXI_WREADY;
        top->ACLK = 1; top->eval();
        if (aw_hs) top->S_AXI_AWVALID = 0;
        if (w_hs)  top->S_AXI_WVALID  = 0;
        top->ACLK = 0; top->eval();
        ++g_time;
        if (!top->S_AXI_AWVALID && !top->S_AXI_WVALID) break;
    }
    for (int i = 0; i < 128; i++) {
        apb_slave();
        bool b_hs = top->S_AXI_BVALID && top->S_AXI_BREADY;
        top->ACLK = 1; top->eval();
        top->ACLK = 0; top->eval();
        ++g_time;
        if (b_hs) { g_slverr_port = -1; break; }
    }
    top->S_AXI_BREADY = 0;
    tick();
}

// Drive a single-beat AXI read; wait for R completion.
// arlen != 0 triggers the illegal-read error path (RRESP=DECERR).
static void read_single(uint32_t addr, uint8_t arlen = 0, uint8_t arprot = 0) {
    top->S_AXI_ARVALID = 1;
    top->S_AXI_ARADDR  = addr;
    top->S_AXI_ARID    = 2;
    top->S_AXI_ARLEN   = arlen;
    top->S_AXI_ARSIZE  = 3;
    top->S_AXI_ARBURST = 1;
    top->S_AXI_ARPROT  = arprot;
    top->S_AXI_RREADY  = 1;

    for (int i = 0; i < 64; i++) {
        apb_slave();
        bool ar_hs = top->S_AXI_ARVALID && top->S_AXI_ARREADY;
        top->ACLK = 1; top->eval();
        if (ar_hs) top->S_AXI_ARVALID = 0;
        top->ACLK = 0; top->eval();
        ++g_time;
        if (ar_hs) break;
    }
    for (int i = 0; i < 128; i++) {
        apb_slave();
        bool r_hs = top->S_AXI_RVALID && top->S_AXI_RREADY;
        top->ACLK = 1; top->eval();
        top->ACLK = 0; top->eval();
        ++g_time;
        if (r_hs) { g_slverr_port = -1; break; }
    }
    top->S_AXI_RREADY = 0;
    tick();
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    top = new Vaxi4_to_apb4_2x_simple;

    top->ACLK = 0; top->ARESETn = 0;
    top->S_AXI_AWVALID = 0; top->S_AXI_WVALID = 0; top->S_AXI_BREADY = 0;
    top->S_AXI_ARVALID = 0; top->S_AXI_RREADY = 0;
    top->PRDATA0 = 0; top->PREADY0 = 0; top->PSLVERR0 = 0;
    top->PRDATA1 = 0; top->PREADY1 = 0; top->PSLVERR1 = 0;
    top->eval();

    for (int i = 0; i < 8; i++) tick();
    top->ARESETn = 1;
    tick(); tick();

    // 1. Normal write to APB slave 0.
    write_single(0x00001000, 0xCAFEBABEDEAD0001ULL);

    // 2. Normal write to APB slave 1.
    write_single(0x80001000, 0xCAFEBABEDEAD0002ULL);

    // 3. Normal read from APB slave 0.
    read_single(0x00002000);

    // 4. Normal read from APB slave 1.
    read_single(0x80002000);

    // 5. Illegal write: AWLEN=1 on single-beat-only bridge → ST_ERR_RESP write path.
    write_single(0x00003000, 0xBADBADBADBADBADDULL, /*awlen=*/1);

    // 6. Illegal read: ARLEN=1 → ST_READ_RESP error path (lines 152-153).
    read_single(0x00004000, /*arlen=*/1);

    // 7. PSLVERR on APB slave 0 write → BRESP=SLVERR (exercises the ternary branch).
    g_slverr_port = 0;
    write_single(0x00005000, 0xDEADBEEFCAFEBABEULL);

    // 8. PSLVERR on APB slave 1 write → BRESP=SLVERR.
    g_slverr_port = 1;
    write_single(0x80005000, 0xDEADBEEFCAFEBABEULL);

    // 9. PSLVERR on APB slave 0 read → RRESP=SLVERR.
    g_slverr_port = 0;
    read_single(0x00006000);

    // 10. PSLVERR on APB slave 1 read → RRESP=SLVERR.
    g_slverr_port = 1;
    read_single(0x80006000);

    // 11. Non-zero AWPROT/ARPROT → exercises prot_reg capture and PPROT propagation.
    //     Drive both APB0 and APB1 with non-zero prot to cover PPROT0 and PPROT1.
    write_single(0x00007000, 0x1234567890ABCDEFULL, /*awlen=*/0, /*awprot=*/3);
    read_single(0x00007000, /*arlen=*/0, /*arprot=*/5);
    write_single(0x80007000, 0xFEDCBA9876543210ULL, /*awlen=*/0, /*awprot=*/3);
    read_single(0x80007000, /*arlen=*/0, /*arprot=*/5);

    // 12. Repeat a write and read with 2 APB wait states (WAIT_CYCLES=2) to
    //     exercise the PREADY polling loop under realistic APB timing.
    g_wait_states = 2;
    g_ws_cnt0 = g_wait_states;
    g_ws_cnt1 = g_wait_states;
    write_single(0x00008000, 0xA5A5A5A5A5A5A5A5ULL);
    read_single(0x00008000);
    g_wait_states = 0;
    g_ws_cnt0 = 0;
    g_ws_cnt1 = 0;

    for (int i = 0; i < 8; i++) tick();

#if VM_COVERAGE
    VerilatedCov::write("coverage.dat");
#endif
    delete top;
    return 0;
}
