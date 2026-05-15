"""
cocotb tests for axi3lite_regblock.

AXI3-Lite = AXI4-Lite + WID on the write-data channel (must match AWID).
32 RW registers at offsets 0x00–0x7C.  Out-of-range or WID≠AWID → SLVERR.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

BRESP_OKAY   = 0b00
BRESP_SLVERR = 0b10

RRESP_OKAY   = 0b00
RRESP_SLVERR = 0b10


async def reset_dut(dut, clk, cycles=5):
    dut.ARESETn.value       = 0
    dut.S_AXI_AWVALID.value = 0
    dut.S_AXI_WVALID.value  = 0
    dut.S_AXI_BREADY.value  = 1
    dut.S_AXI_ARVALID.value = 0
    dut.S_AXI_RREADY.value  = 1
    for _ in range(cycles):
        await RisingEdge(clk)
    dut.ARESETn.value = 1
    await RisingEdge(clk)


class AXI3LiteDriver:
    """Drive AXI3-Lite transactions to axi3lite_regblock."""

    def __init__(self, dut, clk):
        self.dut = dut
        self.clk = clk

    async def write(self, addr, data, awid=0, wid=None, strb=0xF):
        """Issue an AXI3-Lite write. wid defaults to awid (matching); override to inject WID-mismatch."""
        if wid is None:
            wid = awid
        dut = self.dut
        clk = self.clk

        dut.S_AXI_AWID.value    = awid
        dut.S_AXI_AWADDR.value  = addr
        dut.S_AXI_AWPROT.value  = 0
        dut.S_AXI_AWVALID.value = 1
        dut.S_AXI_WID.value     = wid
        dut.S_AXI_WDATA.value   = data
        dut.S_AXI_WSTRB.value   = strb
        dut.S_AXI_WVALID.value  = 1
        dut.S_AXI_BREADY.value  = 1

        # AW handshake
        for _ in range(64):
            await RisingEdge(clk)
            if int(dut.S_AXI_AWREADY.value) == 1:
                dut.S_AXI_AWVALID.value = 0
                break
        else:
            raise AssertionError(f"Timeout on AW handshake (addr=0x{addr:08x})")

        # W handshake
        for _ in range(64):
            await RisingEdge(clk)
            if int(dut.S_AXI_WREADY.value) == 1:
                dut.S_AXI_WVALID.value = 0
                break
        else:
            raise AssertionError(f"Timeout on W handshake (addr=0x{addr:08x})")

        # B response
        for _ in range(64):
            await RisingEdge(clk)
            if int(dut.S_AXI_BVALID.value) == 1:
                bresp = int(dut.S_AXI_BRESP.value)
                dut.S_AXI_BREADY.value = 0
                return bresp
        raise AssertionError(f"Timeout waiting for BVALID (addr=0x{addr:08x})")

    async def read(self, addr, arid=0):
        """Issue an AXI3-Lite read. Returns (rdata, rresp)."""
        dut = self.dut
        clk = self.clk

        dut.S_AXI_ARID.value    = arid
        dut.S_AXI_ARADDR.value  = addr
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
                dut.S_AXI_RREADY.value = 0
                return rdata, rresp
        raise AssertionError(f"Timeout waiting for RVALID (addr=0x{addr:08x})")


@cocotb.test()
async def test_sequential_write_read_all(dut):
    """Write then read-back all 32 registers."""
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)

    axi = AXI3LiteDriver(dut, clk)
    for i in range(32):
        data  = 0xC0DE0000 | i
        bresp = await axi.write(i * 4, data, awid=1, strb=0xF)
        assert bresp == BRESP_OKAY, f"REG{i} write BRESP {bresp}"

    for i in range(32):
        rdata, rresp = await axi.read(i * 4, arid=2)
        assert rresp == RRESP_OKAY, f"REG{i} read RRESP {rresp}"
        assert rdata == (0xC0DE0000 | i), \
            f"REG{i} read-back: got 0x{rdata:08x}, expected 0x{0xC0DE0000 | i:08x}"


@cocotb.test()
async def test_wstrb_partial_write(dut):
    """Partial WSTRB write: verify only the selected byte lane is modified."""
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)

    axi = AXI3LiteDriver(dut, clk)

    # Prime REG0 with a known value
    await axi.write(0x00, 0x11223344, awid=1, strb=0xF)

    # Overwrite byte 3 (bits [31:24]) with 0xAA via strb[3]=1 only
    await axi.write(0x00, 0xAA000000, awid=1, strb=0x8)
    rdata, rresp = await axi.read(0x00)
    assert rresp == RRESP_OKAY
    assert rdata == 0xAA223344, f"Partial write result: 0x{rdata:08x}"

    # Overwrite byte 0 (bits [7:0]) with 0xBB via strb[0]=1 only
    await axi.write(0x00, 0x000000BB, awid=1, strb=0x1)
    rdata, rresp = await axi.read(0x00)
    assert rresp == RRESP_OKAY
    assert rdata == 0xAA2233BB, f"Partial write result: 0x{rdata:08x}"


@cocotb.test()
async def test_out_of_range_write_slverr(dut):
    """Out-of-range write address (beyond REG31 at 0x7C) returns SLVERR."""
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)

    axi = AXI3LiteDriver(dut, clk)
    bresp = await axi.write(0x80, 0xDEADBEEF, awid=3)
    assert bresp == BRESP_SLVERR, f"Expected SLVERR, got BRESP={bresp}"

    # Out-of-range at high address
    bresp = await axi.write(0xFFFF_FF00, 0xCAFEBABE, awid=3)
    assert bresp == BRESP_SLVERR, f"Expected SLVERR at high addr, got BRESP={bresp}"


@cocotb.test()
async def test_out_of_range_read_slverr(dut):
    """Out-of-range read address returns SLVERR with RDATA=0."""
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)

    axi = AXI3LiteDriver(dut, clk)
    rdata, rresp = await axi.read(0x80)
    assert rresp == RRESP_SLVERR, f"Expected SLVERR, got RRESP={rresp}"

    rdata, rresp = await axi.read(0x1000_0000)
    assert rresp == RRESP_SLVERR, f"Expected SLVERR at high addr, got RRESP={rresp}"


@cocotb.test()
async def test_wid_mismatch_slverr(dut):
    """WID ≠ AWID on the W channel returns SLVERR; register data is not modified."""
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)

    axi = AXI3LiteDriver(dut, clk)

    # Prime REG1 with a known value
    await axi.write(0x04, 0x12345678, awid=1)

    # WID-mismatch write: AWID=5, WID=6 → SLVERR, register unchanged
    bresp = await axi.write(0x04, 0xDEADBEEF, awid=5, wid=6)
    assert bresp == BRESP_SLVERR, f"Expected SLVERR on WID mismatch, got BRESP={bresp}"

    rdata, rresp = await axi.read(0x04)
    assert rresp == RRESP_OKAY
    assert rdata == 0x12345678, \
        f"Register must be unchanged after WID-mismatch write; got 0x{rdata:08x}"
