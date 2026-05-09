"""
Shared AXI4/APB4 driver and slave model for IP-axi-to-2apbs cocotb tests.

AXI4Driver : drives the AXI4 slave port of the DUT (single-beat and burst).
APBSlave   : responds to the APB4 master port of the DUT with memory-backed reads/writes.
reset_dut  : drives ARESETn low then releases it.
start_slaves: creates APB slave pair, killing any still-running ones from prior tests.
"""

import cocotb
from cocotb.triggers import RisingEdge

# Module-level task handles so each call to start_slaves() kills stale coroutines.
_slave_tasks: list = []

BRESP_OKAY   = 0b00
BRESP_SLVERR = 0b10
BRESP_DECERR = 0b11

RRESP_OKAY   = 0b00
RRESP_SLVERR = 0b10
RRESP_DECERR = 0b11


async def reset_dut(dut, clk, cycles=5):
    dut.ARESETn.value = 0
    dut.S_AXI_AWVALID.value = 0
    dut.S_AXI_WVALID.value  = 0
    dut.S_AXI_BREADY.value  = 1
    dut.S_AXI_ARVALID.value = 0
    dut.S_AXI_RREADY.value  = 1
    dut.PRDATA0.value  = 0
    dut.PREADY0.value  = 1
    dut.PSLVERR0.value = 0
    dut.PRDATA1.value  = 0
    dut.PREADY1.value  = 1
    dut.PSLVERR1.value = 0
    for _ in range(cycles):
        await RisingEdge(clk)
    dut.ARESETn.value = 1
    await RisingEdge(clk)


class AXI4Driver:
    def __init__(self, dut, clk):
        self.dut = dut
        self.clk = clk

    async def write(self, addr, data, awid=0, strb=0xFF):
        dut = self.dut
        clk = self.clk

        dut.S_AXI_AWID.value    = awid
        dut.S_AXI_AWADDR.value  = addr
        dut.S_AXI_AWLEN.value   = 0
        dut.S_AXI_AWSIZE.value  = 0b011  # 8 bytes
        dut.S_AXI_AWBURST.value = 0b01   # INCR
        dut.S_AXI_AWPROT.value  = 0
        dut.S_AXI_AWVALID.value = 1
        dut.S_AXI_WDATA.value   = data
        dut.S_AXI_WSTRB.value   = strb
        dut.S_AXI_WLAST.value   = 1
        dut.S_AXI_WVALID.value  = 1
        dut.S_AXI_BREADY.value  = 1

        aw_done = False
        w_done  = False
        for _ in range(64):
            await RisingEdge(clk)
            if not aw_done and int(dut.S_AXI_AWREADY.value) == 1:
                dut.S_AXI_AWVALID.value = 0
                aw_done = True
            if not w_done and int(dut.S_AXI_WREADY.value) == 1:
                dut.S_AXI_WVALID.value = 0
                w_done = True
            if aw_done and w_done:
                break
        else:
            raise AssertionError(f"Timeout on AW/W handshake (addr=0x{addr:08x})")

        for _ in range(64):
            await RisingEdge(clk)
            if int(dut.S_AXI_BVALID.value) == 1:
                bresp = int(dut.S_AXI_BRESP.value)
                dut.S_AXI_BREADY.value = 0
                return bresp
        raise AssertionError(f"Timeout waiting for BVALID (addr=0x{addr:08x})")

    async def read(self, addr, arid=0):
        dut = self.dut
        clk = self.clk

        dut.S_AXI_ARID.value    = arid
        dut.S_AXI_ARADDR.value  = addr
        dut.S_AXI_ARLEN.value   = 0
        dut.S_AXI_ARSIZE.value  = 0b011
        dut.S_AXI_ARBURST.value = 0b01
        dut.S_AXI_ARPROT.value  = 0
        dut.S_AXI_ARVALID.value = 1
        dut.S_AXI_RREADY.value  = 1

        for _ in range(64):
            await RisingEdge(clk)
            if int(dut.S_AXI_ARREADY.value) == 1:
                dut.S_AXI_ARVALID.value = 0
                break
        else:
            raise AssertionError(f"Timeout on AR handshake (addr=0x{addr:08x})")

        for _ in range(64):
            await RisingEdge(clk)
            if int(dut.S_AXI_RVALID.value) == 1:
                rdata = int(dut.S_AXI_RDATA.value)
                rresp = int(dut.S_AXI_RRESP.value)
                return rdata, rresp
        raise AssertionError(f"Timeout waiting for RVALID (addr=0x{addr:08x})")

    async def burst_write(self, addr, data_list, awid=0, strb=0xFF):
        dut    = self.dut
        clk    = self.clk
        length = len(data_list)

        dut.S_AXI_AWID.value    = awid
        dut.S_AXI_AWADDR.value  = addr
        dut.S_AXI_AWLEN.value   = length - 1
        dut.S_AXI_AWSIZE.value  = 0b011
        dut.S_AXI_AWBURST.value = 0b01
        dut.S_AXI_AWPROT.value  = 0
        dut.S_AXI_AWVALID.value = 1
        dut.S_AXI_BREADY.value  = 1

        for _ in range(64):
            await RisingEdge(clk)
            if int(dut.S_AXI_AWREADY.value) == 1:
                dut.S_AXI_AWVALID.value = 0
                break
        else:
            raise AssertionError(f"Timeout on AW handshake (burst, addr=0x{addr:08x})")

        for i, beat_data in enumerate(data_list):
            dut.S_AXI_WDATA.value  = beat_data
            dut.S_AXI_WSTRB.value  = strb
            dut.S_AXI_WLAST.value  = 1 if i == length - 1 else 0
            dut.S_AXI_WVALID.value = 1
            for _ in range(64):
                await RisingEdge(clk)
                if int(dut.S_AXI_WREADY.value) == 1:
                    break
            else:
                raise AssertionError(f"Timeout on W beat {i} (addr=0x{addr:08x})")
        dut.S_AXI_WVALID.value = 0

        for _ in range(64):
            await RisingEdge(clk)
            if int(dut.S_AXI_BVALID.value) == 1:
                return int(dut.S_AXI_BRESP.value)
        raise AssertionError(f"Timeout waiting for BVALID (burst, addr=0x{addr:08x})")

    async def burst_read(self, addr, length, arid=0):
        dut = self.dut
        clk = self.clk

        dut.S_AXI_ARID.value    = arid
        dut.S_AXI_ARADDR.value  = addr
        dut.S_AXI_ARLEN.value   = length - 1
        dut.S_AXI_ARSIZE.value  = 0b011
        dut.S_AXI_ARBURST.value = 0b01
        dut.S_AXI_ARPROT.value  = 0
        dut.S_AXI_ARVALID.value = 1
        dut.S_AXI_RREADY.value  = 1

        for _ in range(64):
            await RisingEdge(clk)
            if int(dut.S_AXI_ARREADY.value) == 1:
                dut.S_AXI_ARVALID.value = 0
                break
        else:
            raise AssertionError(f"Timeout on AR handshake (burst, addr=0x{addr:08x})")

        beats = []
        for _ in range(length * 32):
            await RisingEdge(clk)
            if int(dut.S_AXI_RVALID.value) == 1:
                beats.append(int(dut.S_AXI_RDATA.value))
                if int(dut.S_AXI_RLAST.value) == 1:
                    return beats
        raise AssertionError(
            f"Timeout collecting {length} read beats, got {len(beats)} (addr=0x{addr:08x})"
        )


def start_slaves(dut, clk, wait0=0, wait1=0):
    """Create and launch two APB slave models, killing any still-active from prior tests."""
    global _slave_tasks
    for t in _slave_tasks:
        t.kill()
    _slave_tasks.clear()

    s0 = APBSlave(dut, 0, clk, wait_cycles=wait0)
    s1 = APBSlave(dut, 1, clk, wait_cycles=wait1)
    _slave_tasks.append(cocotb.start_soon(s0.run()))
    _slave_tasks.append(cocotb.start_soon(s1.run()))
    return s0, s1


class APBSlave:
    """Memory-backed APB4 slave model for one APB port (n=0 or n=1)."""

    def __init__(self, dut, n, clk, wait_cycles=0):
        self.dut         = dut
        self.n           = n
        self.clk         = clk
        self.wait_cycles = wait_cycles
        self.mem         = {}
        self._active     = True

    async def run(self):
        dut    = self.dut
        n      = self.n
        clk    = self.clk
        psel   = getattr(dut, f"PSEL{n}")
        penbl  = getattr(dut, f"PENABLE{n}")
        pwrite = getattr(dut, f"PWRITE{n}")
        paddr  = getattr(dut, f"PADDR{n}")
        pwdata = getattr(dut, f"PWDATA{n}")
        prdata = getattr(dut, f"PRDATA{n}")
        pready = getattr(dut, f"PREADY{n}")

        wait_remaining = 0

        while self._active:
            await RisingEdge(clk)
            # PSEL/PENABLE are reset to 0; safe to read always.
            sel    = int(psel.value)
            enable = int(penbl.value)

            if not sel:
                pready.value  = 1
                wait_remaining = 0
                continue

            # Only read PWRITE/PADDR/PWDATA when PSEL=1 (they may be X at reset).
            write = int(pwrite.value)
            addr  = int(paddr.value)

            if not enable:
                # Setup phase: preload PRDATA for reads, arm wait counter.
                # IMPORTANT: drive PREADY=0 here when wait is needed so the
                # DUT sees PREADY=0 at the very first access cycle (NBA timing:
                # our drive after rising edge T is visible at rising edge T+1).
                if not write:
                    prdata.value = self.mem.get(addr, 0)
                wait_remaining = self.wait_cycles
                if self.wait_cycles > 0:
                    pready.value = 0
                else:
                    pready.value = 1

            else:
                # Access phase.
                if wait_remaining > 0:
                    pready.value = 0
                    wait_remaining -= 1
                else:
                    pready.value = 1
                    if write:
                        self.mem[addr] = int(pwdata.value)

    def stop(self):
        self._active = False
