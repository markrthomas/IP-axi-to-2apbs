"""
cocotb tests for axi4_to_apb4_2x_simple.

Mirrors the UVM test_bridge_simple suite and the directed Verilog TB stimulus,
verifiable on Icarus Verilog without VCS.

Key address-decode rule: S_AXI_AWADDR/ARADDR bit 31 == 0 → APB slave 0,
                                                       == 1 → APB slave 1.
"""

import cocotb
from cocotb.clock import Clock

from env import AXI4Driver, BRESP_OKAY, RRESP_OKAY, reset_dut, start_slaves


@cocotb.test()
async def test_apb0_write_read(dut):
    """Write 0xDEAD_BEEF_CAFE_BABE to APB0 at 0x0000_0010, read back."""
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)
    s0, s1 = start_slaves(dut, clk)

    axi = AXI4Driver(dut, clk)
    WDATA = 0xDEAD_BEEF_CAFE_BABE
    ADDR  = 0x0000_0010

    bresp = await axi.write(ADDR, WDATA)
    assert bresp == BRESP_OKAY, f"Expected OKAY write resp, got {bresp}"

    rdata, rresp = await axi.read(ADDR)
    assert rresp  == RRESP_OKAY, f"Expected OKAY read resp, got {rresp}"
    assert rdata  == WDATA,      f"Read-back mismatch: 0x{rdata:016x} != 0x{WDATA:016x}"


@cocotb.test()
async def test_apb1_write_read(dut):
    """Write 0x1234_5678_9ABC_DEF0 to APB1 at 0x8000_0020, read back."""
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)
    s0, s1 = start_slaves(dut, clk)

    axi = AXI4Driver(dut, clk)
    WDATA = 0x1234_5678_9ABC_DEF0
    ADDR  = 0x8000_0020

    bresp = await axi.write(ADDR, WDATA)
    assert bresp == BRESP_OKAY, f"Expected OKAY write resp, got {bresp}"

    rdata, rresp = await axi.read(ADDR)
    assert rresp  == RRESP_OKAY, f"Expected OKAY read resp, got {rresp}"
    assert rdata  == WDATA,      f"Read-back mismatch: 0x{rdata:016x} != 0x{WDATA:016x}"


@cocotb.test()
async def test_address_decode(dut):
    """Address bit 31 routes to the correct APB slave; data must not cross."""
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)
    s0, s1 = start_slaves(dut, clk)

    axi = AXI4Driver(dut, clk)
    DATA0 = 0xAAAA_1111_BBBB_2222
    DATA1 = 0xCCCC_3333_DDDD_4444
    ADDR  = 0x0000_0040  # same offset, different slaves

    await axi.write(ADDR,             DATA0)
    await axi.write(ADDR | 0x8000_0000, DATA1)

    rd0, _ = await axi.read(ADDR)
    rd1, _ = await axi.read(ADDR | 0x8000_0000)

    assert rd0 == DATA0, f"APB0 data wrong: 0x{rd0:016x}"
    assert rd1 == DATA1, f"APB1 data wrong: 0x{rd1:016x}"
    assert rd0 != rd1,   "APB0 and APB1 should be independent"


@cocotb.test()
async def test_multiple_writes(dut):
    """Several sequential writes then reads back to APB0."""
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)
    start_slaves(dut, clk)

    axi = AXI4Driver(dut, clk)
    cases = [
        (0x0000_0010, 0xDEAD_BEEF_CAFE_BABE),
        (0x0000_0018, 0x1234_5678_9ABC_DEF0),
        (0x0000_0020, 0xFEED_FACE_C0FF_EE00),
        (0x0000_0028, 0x0001_0203_0405_0607),
    ]

    for addr, data in cases:
        bresp = await axi.write(addr, data)
        assert bresp == 0, f"Write to 0x{addr:08x} failed with bresp={bresp}"

    for addr, expected in cases:
        rdata, rresp = await axi.read(addr)
        assert rresp == 0,        f"Read rresp error at 0x{addr:08x}: {rresp}"
        assert rdata == expected, f"Mismatch at 0x{addr:08x}: got 0x{rdata:016x}"


@cocotb.test()
async def test_wait_state(dut):
    """APB slave inserts 2 wait cycles; bridge must stall and return correct data."""
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)
    # APB0 with 2 wait cycles, matching SIMPLE WS TEST
    start_slaves(dut, clk, wait0=2, wait1=0)

    axi = AXI4Driver(dut, clk)
    WDATA = 0xDEAD_BEEF_CAFE_BABE
    ADDR  = 0x0000_0010

    bresp = await axi.write(ADDR, WDATA)
    assert bresp == 0, f"Wait-state write failed: bresp={bresp}"

    rdata, rresp = await axi.read(ADDR)
    assert rresp == 0,     f"Wait-state read rresp error: {rresp}"
    assert rdata == WDATA, f"Wait-state read mismatch: 0x{rdata:016x}"
