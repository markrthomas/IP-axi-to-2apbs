// Verilator performance benchmark harness for axi4_to_apb4_2x_burst.
//
// Runs a large, back-to-back workload of INCR burst writes and reads across
// both APB ports with a zero-wait APB slave, times the simulation loop with a
// monotonic clock, and prints raw performance counters as "PERF <key> <value>"
// lines.  scripts/perf_report.py turns those into a terminal table + HTML.
//
// Metrics are two-sided:
//   * simulation speed   -- how fast the model runs (sim cycles / wall second)
//   * design efficiency  -- cycles the DUT spends per AXI beat (lower is better),
//                           which at a nominal clock gives sustained throughput.
#include "Vaxi4_to_apb4_2x_burst.h"
#include "verilated.h"
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>

static uint64_t g_time    = 0;   // simulated clock cycles
static uint64_t g_wbeats  = 0;   // AXI write beats accepted
static uint64_t g_rbeats  = 0;   // AXI read beats returned
static uint64_t g_txns    = 0;   // AXI transactions issued (AW or AR)

static Vaxi4_to_apb4_2x_burst* top;

// Zero-wait memoryless APB slave: PREADY tracks PENABLE, no PSLVERR.
static void apb_slave() {
    top->PREADY0  = top->PENABLE0;
    top->PREADY1  = top->PENABLE1;
    top->PRDATA0  = (uint64_t)0xDEADBEEFCAFEBABEULL;
    top->PRDATA1  = (uint64_t)0x0123456789ABCDEFULL;
    top->PSLVERR0 = 0;
    top->PSLVERR1 = 0;
}

static void tick() {
    apb_slave();
    top->ACLK = 1; top->eval();
    top->ACLK = 0; top->eval();
    ++g_time;
}

static void do_aw(uint32_t addr, uint8_t awlen) {
    top->S_AXI_AWVALID = 1;
    top->S_AXI_AWADDR  = addr;
    top->S_AXI_AWID    = 1;
    top->S_AXI_AWLEN   = awlen;
    top->S_AXI_AWSIZE  = 3;
    top->S_AXI_AWBURST = 1;  // INCR
    top->S_AXI_AWPROT  = 0;
    for (int i = 0; i < 64; i++) {
        apb_slave();
        bool aw_hs = top->S_AXI_AWVALID && top->S_AXI_AWREADY;
        top->ACLK = 1; top->eval();
        if (aw_hs) top->S_AXI_AWVALID = 0;
        top->ACLK = 0; top->eval();
        ++g_time;
        if (aw_hs) break;
    }
    ++g_txns;
}

static void do_w_beat(uint64_t data, bool last) {
    top->S_AXI_WVALID = 1;
    top->S_AXI_WDATA  = data;
    top->S_AXI_WSTRB  = 0xFF;
    top->S_AXI_WLAST  = last ? 1 : 0;
    for (int i = 0; i < 64; i++) {
        apb_slave();
        bool w_hs = top->S_AXI_WVALID && top->S_AXI_WREADY;
        top->ACLK = 1; top->eval();
        if (w_hs) top->S_AXI_WVALID = 0;
        top->ACLK = 0; top->eval();
        ++g_time;
        if (w_hs) { ++g_wbeats; break; }
    }
}

static void wait_b() {
    top->S_AXI_BREADY = 1;
    for (int i = 0; i < 256; i++) {
        apb_slave();
        bool b_hs = top->S_AXI_BVALID && top->S_AXI_BREADY;
        top->ACLK = 1; top->eval();
        top->ACLK = 0; top->eval();
        ++g_time;
        if (b_hs) break;
    }
    top->S_AXI_BREADY = 0;
    tick();
}

static void do_read(uint32_t addr, int beats) {
    top->S_AXI_ARVALID = 1;
    top->S_AXI_ARADDR  = addr;
    top->S_AXI_ARID    = 2;
    top->S_AXI_ARLEN   = beats - 1;
    top->S_AXI_ARSIZE  = 3;
    top->S_AXI_ARBURST = 1;  // INCR
    top->S_AXI_ARPROT  = 0;
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
    ++g_txns;
    int recv = 0;
    for (int i = 0; i < beats * 32 && recv < beats; i++) {
        apb_slave();
        bool r_hs  = top->S_AXI_RVALID && top->S_AXI_RREADY;
        bool rlast = top->S_AXI_RLAST;
        top->ACLK = 1; top->eval();
        if (r_hs) { recv++; ++g_rbeats; }
        top->ACLK = 0; top->eval();
        ++g_time;
        if (r_hs && rlast) break;
    }
    top->S_AXI_RREADY = 0;
    tick();
}

double sc_time_stamp() { return (double)g_time; }

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    // Iteration count: one iter = one burst write + read-back pair.  Override
    // with argv[1]; default sized for a sub-second run that is still large
    // enough to be a stable timing sample.
    long iters = 4000;
    if (argc > 1) {
        long v = strtol(argv[1], nullptr, 10);
        if (v > 0) iters = v;
    }
    // Nominal clock for translating cycles/beat into wall throughput; matches
    // the 10 ns period used across the directed testbenches.
    const double clock_mhz = 100.0;

    top = new Vaxi4_to_apb4_2x_burst;
    top->ACLK = 0; top->ARESETn = 0;
    top->S_AXI_AWVALID = 0; top->S_AXI_WVALID = 0; top->S_AXI_BREADY = 0;
    top->S_AXI_ARVALID = 0; top->S_AXI_RREADY = 0;
    top->PRDATA0 = 0; top->PREADY0 = 0; top->PSLVERR0 = 0;
    top->PRDATA1 = 0; top->PREADY1 = 0; top->PSLVERR1 = 0;
    top->eval();
    for (int i = 0; i < 8; i++) tick();
    top->ARESETn = 1;
    tick(); tick();

    const uint64_t start_cycles = g_time;
    auto t0 = std::chrono::steady_clock::now();

    // Burst lengths cycle 1..16 beats; addresses alternate APB0/APB1 and step
    // through a 4 KiB window so no burst crosses the addr[31] port boundary.
    static const uint8_t lens[] = {1, 2, 4, 8, 16, 3, 7, 12};
    const int n_lens = (int)(sizeof(lens) / sizeof(lens[0]));
    for (long it = 0; it < iters; it++) {
        int len   = lens[it % n_lens];
        uint32_t base = (it & 1 ? 0x80000000u : 0x00000000u)
                        + (uint32_t)((it % 64) * 0x40);  // 8-byte*8 aligned window
        do_aw(base, (uint8_t)(len - 1));
        for (int b = 0; b < len; b++)
            do_w_beat(0xA5A5A5A500000000ULL + (uint64_t)b, b == len - 1);
        wait_b();
        do_read(base, len);
    }

    auto t1 = std::chrono::steady_clock::now();
    double wall = std::chrono::duration<double>(t1 - t0).count();
    uint64_t bench_cycles = g_time - start_cycles;

    for (int i = 0; i < 8; i++) tick();
    delete top;

    // Raw counters; scripts/perf_report.py derives the rates.
    printf("PERF iterations %ld\n",      iters);
    printf("PERF transactions %llu\n",   (unsigned long long)g_txns);
    printf("PERF axi_beats %llu\n",      (unsigned long long)(g_wbeats + g_rbeats));
    printf("PERF write_beats %llu\n",    (unsigned long long)g_wbeats);
    printf("PERF read_beats %llu\n",     (unsigned long long)g_rbeats);
    printf("PERF sim_cycles %llu\n",     (unsigned long long)bench_cycles);
    printf("PERF wall_seconds %.6f\n",   wall);
    printf("PERF clock_mhz %.3f\n",      clock_mhz);
    return 0;
}
