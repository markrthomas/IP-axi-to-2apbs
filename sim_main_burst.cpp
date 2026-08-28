// Verilator coverage harness for axi4_to_apb4_2x_burst.
// Exercises: single/burst write+read to APB0/1, PSLVERR on both ports,
// WLAST error, APB-port-crossing INCR burst, illegal AWBURST/ARBURST (DECERR),
// non-zero AWPROT/ARPROT.
#include "Vaxi4_to_apb4_2x_burst.h"
#include "verilated.h"
#if VM_COVERAGE
#include "verilated_cov.h"
#endif
#include <cstdint>

static uint64_t g_time = 0;
double sc_time_stamp() { return (double)g_time; }

static Vaxi4_to_apb4_2x_burst* top;

// Inject PSLVERR: -1=none, 0=port0, 1=port1.
static int g_slverr_port = -1;
// Inject PSLVERR only for a limited number of APB accesses (beats).
static int g_slverr_beats = 0;
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

    bool inject0 = (g_slverr_port == 0 && top->PENABLE0 && g_slverr_beats > 0);
    bool inject1 = (g_slverr_port == 1 && top->PENABLE1 && g_slverr_beats > 0);
    top->PSLVERR0 = inject0 ? 1 : 0;
    top->PSLVERR1 = inject1 ? 1 : 0;
    if ((inject0 || inject1) && (top->PREADY0 || top->PREADY1))
        g_slverr_beats--;
}

static void tick() {
    apb_slave();
    top->ACLK = 1; top->eval();
    top->ACLK = 0; top->eval();
    ++g_time;
}

// AW handshake.
static void do_aw(uint32_t addr, uint8_t awlen, uint8_t awburst = 1,
                  uint8_t awprot = 0) {
    top->S_AXI_AWVALID = 1;
    top->S_AXI_AWADDR  = addr;
    top->S_AXI_AWID    = 1;
    top->S_AXI_AWLEN   = awlen;
    top->S_AXI_AWSIZE  = 3;
    top->S_AXI_AWBURST = awburst;
    top->S_AXI_AWPROT  = awprot;
    for (int i = 0; i < 64; i++) {
        apb_slave();
        bool aw_hs = top->S_AXI_AWVALID && top->S_AXI_AWREADY;
        top->ACLK = 1; top->eval();
        if (aw_hs) top->S_AXI_AWVALID = 0;
        top->ACLK = 0; top->eval();
        ++g_time;
        if (aw_hs) break;
    }
}

// One W beat; wlast_override=-1 means use natural last (beat == awlen).
static void do_w_beat(uint64_t data, bool natural_last,
                      int wlast_override = -1) {
    top->S_AXI_WVALID = 1;
    top->S_AXI_WDATA  = data;
    top->S_AXI_WSTRB  = 0xFF;
    top->S_AXI_WLAST  = (wlast_override >= 0) ? (uint8_t)wlast_override
                                               : (natural_last ? 1 : 0);
    for (int i = 0; i < 64; i++) {
        apb_slave();
        bool w_hs = top->S_AXI_WVALID && top->S_AXI_WREADY;
        top->ACLK = 1; top->eval();
        if (w_hs) top->S_AXI_WVALID = 0;
        top->ACLK = 0; top->eval();
        ++g_time;
        if (w_hs) break;
    }
}

// Wait for B response; clears slverr state.
static void wait_b() {
    top->S_AXI_BREADY = 1;
    for (int i = 0; i < 256; i++) {
        apb_slave();
        bool b_hs = top->S_AXI_BVALID && top->S_AXI_BREADY;
        top->ACLK = 1; top->eval();
        top->ACLK = 0; top->eval();
        ++g_time;
        if (b_hs) { g_slverr_port = -1; g_slverr_beats = 0; break; }
    }
    top->S_AXI_BREADY = 0;
    tick();
}

// AR handshake + collect all R beats; clears slverr state.
static void do_read(uint32_t addr, int beats, uint8_t arburst = 1,
                    uint8_t arprot = 0) {
    top->S_AXI_ARVALID = 1;
    top->S_AXI_ARADDR  = addr;
    top->S_AXI_ARID    = 2;
    top->S_AXI_ARLEN   = beats - 1;
    top->S_AXI_ARSIZE  = 3;
    top->S_AXI_ARBURST = arburst;
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
    int recv = 0;
    for (int i = 0; i < beats * 32 && recv < beats; i++) {
        apb_slave();
        bool r_hs  = top->S_AXI_RVALID && top->S_AXI_RREADY;
        bool rlast = top->S_AXI_RLAST;
        top->ACLK = 1; top->eval();
        if (r_hs) recv++;
        top->ACLK = 0; top->eval();
        ++g_time;
        if (r_hs && rlast) { g_slverr_port = -1; g_slverr_beats = 0; break; }
    }
    top->S_AXI_RREADY = 0;
    tick();
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
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

    // 1. Single-beat write to APB slave 0.
    do_aw(0x00001000, 0);
    do_w_beat(0xCAFEBABE00000001ULL, true);
    wait_b();

    // 2. Single-beat write to APB slave 1.
    do_aw(0x80001000, 0);
    do_w_beat(0xCAFEBABE00000002ULL, true);
    wait_b();

    // 3. 4-beat INCR burst write to APB slave 0.
    do_aw(0x00002000, 3);
    for (int b = 0; b < 4; b++)
        do_w_beat(0xA0A0A0A0B0B0B0B0ULL + b, b == 3);
    wait_b();

    // 4. Single-beat read from APB slave 0.
    do_read(0x00003000, 1);

    // 5. Single-beat read from APB slave 1.
    do_read(0x80003000, 1);

    // 6. 4-beat INCR burst read from APB slave 0.
    do_read(0x00004000, 4);

    // 7. Illegal AWBURST=2 (WRAP) write → txn_decerr → BRESP=DECERR.
    do_aw(0x00005000, 0, /*awburst=*/2);
    do_w_beat(0xBADBADBADBADBADDULL, true);
    wait_b();

    // 8. Illegal ARBURST=2 (WRAP) read → txn_decerr read path (lines 281-286).
    do_read(0x00006000, 1, /*arburst=*/2);

    // 9. APB-port-crossing INCR write → aw_cross_apb=1 → txn_decerr (lines 116,119).
    //    addr=0x7FFF_FFE8, awlen=3, awsize=3: last_addr = 0x7FFF_FFE8+0x18 = 0x8000_0000
    do_aw(0x7FFFFFE8, 3, /*awburst=*/1);
    for (int b = 0; b < 4; b++)
        do_w_beat(0xCCCCCCCCDDDDDDDDULL + b, b == 3);
    wait_b();

    // 10. APB-port-crossing INCR read → ar_cross_apb=1 (line 117).
    //     addr=0x7FFFFFE8, arlen=3, arsize=3: last=0x8000_0000
    do_read(0x7FFFFFE8, 4, /*arburst=*/1);

    // 11. PSLVERR on APB slave 0 write → pslverr_acc=1 → BRESP=SLVERR.
    g_slverr_port = 0; g_slverr_beats = 1;
    do_aw(0x00007000, 0);
    do_w_beat(0xDEADBEEFCAFEBABEULL, true);
    wait_b();

    // 12. PSLVERR on APB slave 1 write → BRESP=SLVERR.
    g_slverr_port = 1; g_slverr_beats = 1;
    do_aw(0x80007000, 0);
    do_w_beat(0xDEADBEEFCAFEBABEULL, true);
    wait_b();

    // 13. PSLVERR on APB slave 0 read → RRESP=SLVERR (exercises rresp_fifo path).
    g_slverr_port = 0; g_slverr_beats = 1;
    do_read(0x00008000, 1);

    // 14. WLAST on wrong beat → wlast_err=1 → BRESP=SLVERR (line 185).
    //     4-beat burst but WLAST asserted on beat 1 (index 1 of 4).
    do_aw(0x00009000, 3);
    do_w_beat(0x1111111111111111ULL, false, /*wlast_override=*/0);  // beat 0, no early last
    do_w_beat(0x2222222222222222ULL, false, /*wlast_override=*/1);  // beat 1, EARLY LAST
    do_w_beat(0x3333333333333333ULL, false, /*wlast_override=*/0);  // beat 2
    do_w_beat(0x4444444444444444ULL, true,  /*wlast_override=*/1);  // beat 3, natural last
    wait_b();

    // 15. Non-zero AWPROT/ARPROT → exercises axi_prot_reg capture.
    //     Drive both APB0 and APB1 with non-zero prot to cover PPROT0 and PPROT1.
    do_aw(0x0000A000, 0, /*awburst=*/1, /*awprot=*/3);
    do_w_beat(0x5A5A5A5A5A5A5A5AULL, true);
    wait_b();
    do_read(0x0000A000, 1, /*arburst=*/1, /*arprot=*/5);
    do_aw(0x8000A000, 0, /*awburst=*/1, /*awprot=*/3);
    do_w_beat(0xA5A5A5A5A5A5A5A5ULL, true);
    wait_b();
    do_read(0x8000A000, 1, /*arburst=*/1, /*arprot=*/5);

    // 16. Repeat a single write and a 4-beat burst read with 2 APB wait states
    //     (WAIT_CYCLES=2) to exercise the PREADY polling loop under realistic
    //     APB timing.  apb_slave() reloads g_ws_cnt* from g_wait_states whenever
    //     PENABLE is deasserted, so updating g_wait_states here takes effect
    //     automatically on the first idle cycle before the next APB access.
    g_wait_states = 2;
    do_aw(0x0000B000, 0);
    do_w_beat(0xB5B5B5B5B5B5B5B5ULL, true);
    wait_b();
    do_read(0x0000B000, 4);
    g_wait_states = 0;

    for (int i = 0; i < 8; i++) tick();

#if VM_COVERAGE
    VerilatedCov::write("coverage.dat");
#endif
    delete top;
    return 0;
}
