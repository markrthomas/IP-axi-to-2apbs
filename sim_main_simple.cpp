// Verilator coverage harness for axi4_to_apb4_2x_simple.
// Exercises: write to APB0/1, read from APB0/1, illegal-AWLEN error path.
#include "Vaxi4_to_apb4_2x_simple.h"
#include "verilated.h"
#if VM_COVERAGE
#include "verilated_cov.h"
#endif
#include <cstdint>

static uint64_t g_time = 0;
double sc_time_stamp() { return (double)g_time; }

static Vaxi4_to_apb4_2x_simple* top;

// Zero-wait-state APB slave: PREADY follows PENABLE.
static void apb_slave() {
    top->PREADY0  = top->PENABLE0;
    top->PREADY1  = top->PENABLE1;
    top->PRDATA0  = (uint64_t)0xDEADBEEFCAFEBABEULL;
    top->PRDATA1  = (uint64_t)0x0123456789ABCDEFULL;
    top->PSLVERR0 = 0;
    top->PSLVERR1 = 0;
}

// One clock cycle: drive APB slave, rising edge, falling edge.
static void tick() {
    apb_slave();
    top->ACLK = 1; top->eval();
    top->ACLK = 0; top->eval();
    ++g_time;
}

// Drive a single-beat AXI write; wait for B completion.
// awlen != 0 triggers the illegal-burst error path.
static void write_single(uint32_t addr, uint64_t data, uint8_t awlen = 0) {
    top->S_AXI_AWVALID = 1;
    top->S_AXI_AWADDR  = addr;
    top->S_AXI_AWID    = 1;
    top->S_AXI_AWLEN   = awlen;
    top->S_AXI_AWSIZE  = 3;    // 8-byte beats (DATA_WIDTH=64)
    top->S_AXI_AWBURST = 1;    // INCR
    top->S_AXI_AWPROT  = 0;
    top->S_AXI_WVALID  = 1;
    top->S_AXI_WDATA   = data;
    top->S_AXI_WSTRB   = 0xFF;
    top->S_AXI_WLAST   = 1;
    top->S_AXI_BREADY  = 1;

    // Wait for AW + W handshake (both are ready simultaneously in IDLE).
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
    // Wait for B response.
    for (int i = 0; i < 128; i++) {
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

// Drive a single-beat AXI read; wait for R completion.
static void read_single(uint32_t addr) {
    top->S_AXI_ARVALID = 1;
    top->S_AXI_ARADDR  = addr;
    top->S_AXI_ARID    = 2;
    top->S_AXI_ARLEN   = 0;
    top->S_AXI_ARSIZE  = 3;
    top->S_AXI_ARBURST = 1;
    top->S_AXI_ARPROT  = 0;
    top->S_AXI_RREADY  = 1;

    // Wait for AR handshake.
    for (int i = 0; i < 64; i++) {
        apb_slave();
        bool ar_hs = top->S_AXI_ARVALID && top->S_AXI_ARREADY;
        top->ACLK = 1; top->eval();
        if (ar_hs) top->S_AXI_ARVALID = 0;
        top->ACLK = 0; top->eval();
        ++g_time;
        if (ar_hs) break;
    }
    // Wait for R response.
    for (int i = 0; i < 128; i++) {
        apb_slave();
        bool r_hs = top->S_AXI_RVALID && top->S_AXI_RREADY;
        top->ACLK = 1; top->eval();
        top->ACLK = 0; top->eval();
        ++g_time;
        if (r_hs) break;
    }
    top->S_AXI_RREADY = 0;
    tick();
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    top = new Vaxi4_to_apb4_2x_simple;

    // Initialize inputs.
    top->ACLK = 0; top->ARESETn = 0;
    top->S_AXI_AWVALID = 0; top->S_AXI_WVALID = 0; top->S_AXI_BREADY = 0;
    top->S_AXI_ARVALID = 0; top->S_AXI_RREADY = 0;
    top->PRDATA0 = 0; top->PREADY0 = 0; top->PSLVERR0 = 0;
    top->PRDATA1 = 0; top->PREADY1 = 0; top->PSLVERR1 = 0;
    top->eval();

    // Reset for 8 cycles.
    for (int i = 0; i < 8; i++) tick();
    top->ARESETn = 1;
    tick(); tick();

    // 1. Write to APB slave 0 (addr[31]=0).
    write_single(0x00001000, 0xCAFEBABEDEAD0001ULL);

    // 2. Write to APB slave 1 (addr[31]=1).
    write_single(0x80001000, 0xCAFEBABEDEAD0002ULL);

    // 3. Read from APB slave 0.
    read_single(0x00002000);

    // 4. Read from APB slave 1.
    read_single(0x80002000);

    // 5. Illegal write: AWLEN=1 → ST_ERR_RESP path.
    write_single(0x00003000, 0xBADBADBADBADBADDULL, /*awlen=*/1);

    // Settle.
    for (int i = 0; i < 8; i++) tick();

#if VM_COVERAGE
    VerilatedCov::write("coverage.dat");
#endif
    delete top;
    return 0;
}
