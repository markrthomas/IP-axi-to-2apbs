// Verilator coverage harness for axi4_to_apb4_2x_burst.
// Exercises: single-beat write/read to APB0/1, 4-beat burst write/read, illegal-burst error.
#include "Vaxi4_to_apb4_2x_burst.h"
#include "verilated.h"
#if VM_COVERAGE
#include "verilated_cov.h"
#endif
#include <cstdint>

static uint64_t g_time = 0;
double sc_time_stamp() { return (double)g_time; }

static Vaxi4_to_apb4_2x_burst* top;

// Zero-wait-state APB slave: PREADY follows PENABLE.
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

// Drive AW handshake; caller sets up all AW fields before calling.
static void do_aw(uint32_t addr, uint8_t awlen, uint8_t awburst = 1) {
    top->S_AXI_AWVALID = 1;
    top->S_AXI_AWADDR  = addr;
    top->S_AXI_AWID    = 1;
    top->S_AXI_AWLEN   = awlen;
    top->S_AXI_AWSIZE  = 3;
    top->S_AXI_AWBURST = awburst;
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
}

// Drive one W beat; waits for WREADY.
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
        if (w_hs) break;
    }
}

// Wait for B response.
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

// Drive AR handshake + collect all R beats.
static void do_read(uint32_t addr, int beats) {
    top->S_AXI_ARVALID = 1;
    top->S_AXI_ARADDR  = addr;
    top->S_AXI_ARID    = 2;
    top->S_AXI_ARLEN   = beats - 1;
    top->S_AXI_ARSIZE  = 3;
    top->S_AXI_ARBURST = 1;
    top->S_AXI_ARPROT  = 0;
    top->S_AXI_RREADY  = 1;

    // AR handshake.
    for (int i = 0; i < 64; i++) {
        apb_slave();
        bool ar_hs = top->S_AXI_ARVALID && top->S_AXI_ARREADY;
        top->ACLK = 1; top->eval();
        if (ar_hs) top->S_AXI_ARVALID = 0;
        top->ACLK = 0; top->eval();
        ++g_time;
        if (ar_hs) break;
    }
    // Collect R beats.
    int recv = 0;
    for (int i = 0; i < beats * 32 && recv < beats; i++) {
        apb_slave();
        bool r_hs  = top->S_AXI_RVALID && top->S_AXI_RREADY;
        bool rlast = top->S_AXI_RLAST;
        top->ACLK = 1; top->eval();
        if (r_hs) recv++;
        top->ACLK = 0; top->eval();
        ++g_time;
        if (r_hs && rlast) break;
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

    // Reset.
    for (int i = 0; i < 8; i++) tick();
    top->ARESETn = 1;
    tick(); tick();

    // 1. Single-beat write to APB slave 0.
    do_aw(0x00001000, 0);
    do_w_beat(0xCAFEBABE00000001ULL, true);
    wait_b();

    // 2. Single-beat write to APB slave 1 (addr[31]=1).
    do_aw(0x80001000, 0);
    do_w_beat(0xCAFEBABE00000002ULL, true);
    wait_b();

    // 3. 4-beat burst write to APB slave 0 (AWLEN=3 → beats_total=4).
    do_aw(0x00002000, 3);
    for (int b = 0; b < 4; b++)
        do_w_beat((uint64_t)0xA0A0A0A0B0B0B0B0ULL + b, b == 3);
    wait_b();

    // 4. Single-beat read from APB slave 0.
    do_read(0x00003000, 1);

    // 5. Single-beat read from APB slave 1.
    do_read(0x80003000, 1);

    // 6. 4-beat burst read from APB slave 0.
    do_read(0x00004000, 4);

    // 7. Illegal AWBURST=2 (WRAP > 2'b01) → txn_decerr → SLVERR.
    do_aw(0x00005000, 0, /*awburst=*/2);
    do_w_beat(0xBADBADBADBADBADDULL, true);
    wait_b();

    // Settle.
    for (int i = 0; i < 8; i++) tick();

#if VM_COVERAGE
    VerilatedCov::write("coverage.dat");
#endif
    delete top;
    return 0;
}
