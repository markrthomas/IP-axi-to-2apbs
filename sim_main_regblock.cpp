// Verilator coverage harness for axi3lite_regblock.
// Exercises: write/read all 32 regs, byte strobes, out-of-range access,
// WID-mismatch path, and all-strobe-zero no-op write.
#include "Vaxi3lite_regblock.h"
#include "verilated.h"
#if VM_COVERAGE
#include "verilated_cov.h"
#endif
#include <cassert>
#include <cstdint>

static uint64_t g_time = 0;
double sc_time_stamp() { return (double)g_time; }

static Vaxi3lite_regblock* top;

static void tick() {
    top->ACLK = 1; top->eval();
    top->ACLK = 0; top->eval();
    ++g_time;
}

// Drive a write; return BRESP.
// wid may differ from awid to trigger WID-mismatch SLVERR.
static uint8_t axi_write(uint32_t addr, uint32_t data, uint8_t strb,
                         uint8_t awid, uint8_t wid, uint8_t awprot = 0) {
    top->S_AXI_AWID    = awid;
    top->S_AXI_AWADDR  = addr;
    top->S_AXI_AWPROT  = awprot;
    top->S_AXI_AWVALID = 1;
    top->S_AXI_WID     = wid;
    top->S_AXI_WDATA   = data;
    top->S_AXI_WSTRB   = strb;
    top->S_AXI_WVALID  = 1;
    top->S_AXI_BREADY  = 1;

    // Wait for AW handshake
    for (int i = 0; i < 32; i++) {
        bool aw_hs = top->S_AXI_AWVALID && top->S_AXI_AWREADY;
        top->ACLK = 1; top->eval();
        if (aw_hs) { top->S_AXI_AWVALID = 0; }
        top->ACLK = 0; top->eval();
        ++g_time;
        if (aw_hs) break;
    }

    // Wait for W handshake
    for (int i = 0; i < 32; i++) {
        bool w_hs = top->S_AXI_WVALID && top->S_AXI_WREADY;
        top->ACLK = 1; top->eval();
        if (w_hs) { top->S_AXI_WVALID = 0; }
        top->ACLK = 0; top->eval();
        ++g_time;
        if (w_hs) break;
    }

    // Wait for B response
    uint8_t bresp = 0;
    for (int i = 0; i < 64; i++) {
        bool b_hs = top->S_AXI_BVALID && top->S_AXI_BREADY;
        top->ACLK = 1; top->eval();
        if (b_hs) { bresp = top->S_AXI_BRESP; }
        top->ACLK = 0; top->eval();
        ++g_time;
        if (b_hs) break;
    }
    top->S_AXI_BREADY = 0;
    tick();
    return bresp;
}

// Drive a read; return RDATA via out-param and RRESP as return value.
static uint8_t axi_read(uint32_t addr, uint32_t* rdata, uint8_t arid = 0,
                        uint8_t arprot = 0) {
    top->S_AXI_ARID    = arid;
    top->S_AXI_ARADDR  = addr;
    top->S_AXI_ARPROT  = arprot;
    top->S_AXI_ARVALID = 1;
    top->S_AXI_RREADY  = 1;

    // Wait for AR handshake
    for (int i = 0; i < 32; i++) {
        bool ar_hs = top->S_AXI_ARVALID && top->S_AXI_ARREADY;
        top->ACLK = 1; top->eval();
        if (ar_hs) { top->S_AXI_ARVALID = 0; }
        top->ACLK = 0; top->eval();
        ++g_time;
        if (ar_hs) break;
    }

    // Wait for R response
    uint8_t rresp = 0;
    for (int i = 0; i < 64; i++) {
        bool r_hs = top->S_AXI_RVALID && top->S_AXI_RREADY;
        top->ACLK = 1; top->eval();
        if (r_hs) { rresp = top->S_AXI_RRESP; *rdata = top->S_AXI_RDATA; }
        top->ACLK = 0; top->eval();
        ++g_time;
        if (r_hs) break;
    }
    top->S_AXI_RREADY = 0;
    tick();
    return rresp;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    top = new Vaxi3lite_regblock;

    top->ACLK = 0; top->ARESETn = 0;
    top->S_AXI_AWVALID = 0; top->S_AXI_WVALID = 0; top->S_AXI_BREADY = 0;
    top->S_AXI_ARVALID = 0; top->S_AXI_RREADY = 0;
    top->eval();

    for (int i = 0; i < 8; i++) tick();
    top->ARESETn = 1;
    tick(); tick();

    uint32_t rdata = 0;
    uint8_t  resp  = 0;

    // 1. Write then read-back all 32 registers.
    for (int i = 0; i < 32; i++) {
        uint32_t wdata = 0xDEAD0000u | (uint32_t)i;
        resp = axi_write(i * 4, wdata, 0xF, /*awid=*/1, /*wid=*/1);
        assert(resp == 0);  // OKAY
    }
    for (int i = 0; i < 32; i++) {
        resp = axi_read(i * 4, &rdata, /*arid=*/2);
        assert(resp == 0);
        assert(rdata == (0xDEAD0000u | (uint32_t)i));
    }

    // 2. Byte-strobe partial write on REG0: overwrite only byte 2 ([23:16]).
    // REG0 = 0xDEAD0000; WSTRB[2]=1 writes bits[23:16]=0xAB → 0xDEAB0000.
    resp = axi_write(0, 0x00AB0000u, 0x4, /*awid=*/3, /*wid=*/3);
    assert(resp == 0);
    resp = axi_read(0, &rdata);
    assert(resp == 0);
    assert(rdata == 0xDEAB0000u);

    // 3. All-strobe-zero write (no bytes written, BRESP still OKAY).
    resp = axi_write(4, 0xFFFFFFFFu, 0x0, /*awid=*/5, /*wid=*/5);
    assert(resp == 0);
    resp = axi_read(4, &rdata);
    assert(resp == 0);
    assert(rdata == (0xDEAD0001u));  // unchanged

    // 4. Out-of-range write → SLVERR.
    resp = axi_write(0x80, 0xCAFEBABEu, 0xF, /*awid=*/1, /*wid=*/1);
    assert(resp == 2);  // SLVERR

    // 5. Out-of-range read → SLVERR.
    resp = axi_read(0x80, &rdata);
    assert(resp == 2);

    // 6. WID ≠ AWID → SLVERR; register must be unchanged.
    resp = axi_write(0x08, 0xBADBAD00u, 0xF, /*awid=*/7, /*wid=*/8);
    assert(resp == 2);
    resp = axi_read(0x08, &rdata);
    assert(resp == 0);
    assert(rdata == (0xDEAD0002u));  // unchanged

    // 7. Read with non-zero ARID to exercise RID path.
    resp = axi_read(0x0C, &rdata, /*arid=*/0xA);
    assert(resp == 0);
    assert(rdata == (0xDEAD0003u));

    // 8. Non-zero AWPROT/ARPROT — toggles all PROT bits for toggle coverage.
    resp = axi_write(0x10, 0x11111111u, 0xF, /*awid=*/1, /*wid=*/1, /*awprot=*/7);
    assert(resp == 0);
    resp = axi_read(0x10, &rdata, /*arid=*/0, /*arprot=*/7);
    assert(resp == 0);
    assert(rdata == 0x11111111u);

    for (int i = 0; i < 8; i++) tick();

#if VM_COVERAGE
    VerilatedCov::write("coverage.dat");
#endif
    delete top;
    return 0;
}
