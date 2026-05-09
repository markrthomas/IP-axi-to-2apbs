"""
cocotb tests for axi4_to_apb4_2x_burst.

Mirrors the UVM test_bridge_burst and test_bridge_burst_ext suites.

Key behaviors under test:
  - Single-beat writes and reads to both APB slaves.
  - Multi-beat INCR bursts (all beats target same slave).
  - A 2-beat burst starting at 0x7FFF_FFF8 crosses the APB_ADDR_BIT=31 boundary
    and must be rejected with DECERR (no APB access, no side effects).
"""

import cocotb
from cocotb.clock import Clock

from env import AXI4Driver, BRESP_OKAY, BRESP_DECERR, RRESP_OKAY, reset_dut, start_slaves


@cocotb.test()
async def test_single_write_read_apb0(dut):
    """Single-beat write/read to APB0; mirrors axi_single_write/read in Verilog TB."""
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)
    start_slaves(dut, clk)

    axi = AXI4Driver(dut, clk)
    WDATA = 0xDEAD_BEEF_CAFE_BABE
    ADDR  = 0x0000_0010

    bresp = await axi.write(ADDR, WDATA)
    assert bresp == BRESP_OKAY, f"Write BRESP: {bresp}"

    rdata, rresp = await axi.read(ADDR)
    assert rresp == RRESP_OKAY, f"Read RRESP: {rresp}"
    assert rdata == WDATA,      f"Read-back: 0x{rdata:016x}"


@cocotb.test()
async def test_single_write_read_apb1(dut):
    """Single-beat write/read to APB1."""
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)
    start_slaves(dut, clk)

    axi = AXI4Driver(dut, clk)
    WDATA = 0x1234_5678_9ABC_DEF0
    ADDR  = 0x8000_0010

    bresp = await axi.write(ADDR, WDATA)
    assert bresp == BRESP_OKAY, f"Write BRESP: {bresp}"

    rdata, rresp = await axi.read(ADDR)
    assert rresp == RRESP_OKAY, f"Read RRESP: {rresp}"
    assert rdata == WDATA,      f"Read-back: 0x{rdata:016x}"


@cocotb.test()
async def test_burst_write_read_apb0(dut):
    """4-beat INCR burst write then read-back to APB0."""
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)
    s0, _ = start_slaves(dut, clk)

    axi = AXI4Driver(dut, clk)
    BASE  = 0x0000_0100
    BEATS = [0x0001_0203_0405_0607,
             0x0809_0A0B_0C0D_0E0F,
             0x1011_1213_1415_1617,
             0x1819_1A1B_1C1D_1E1F]

    bresp = await axi.burst_write(BASE, BEATS)
    assert bresp == BRESP_OKAY, f"Burst write BRESP: {bresp}"

    # Read back one beat at a time (simple bridge handles single reads via APB)
    for i, expected in enumerate(BEATS):
        addr = BASE + i * 8
        rdata, rresp = await axi.read(addr)
        assert rresp == RRESP_OKAY, f"Read RRESP beat {i}: {rresp}"
        assert rdata == expected,   f"Beat {i}: got 0x{rdata:016x}, want 0x{expected:016x}"


@cocotb.test()
async def test_burst_write_read_apb1(dut):
    """4-beat INCR burst write then read-back to APB1."""
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)
    _, s1 = start_slaves(dut, clk)

    axi = AXI4Driver(dut, clk)
    BASE  = 0x8000_0200
    BEATS = [0xAAAA_BBBB_CCCC_DDDD,
             0xEEEE_FFFF_0000_1111,
             0x2222_3333_4444_5555,
             0x6666_7777_8888_9999]

    bresp = await axi.burst_write(BASE, BEATS)
    assert bresp == BRESP_OKAY, f"Burst write BRESP: {bresp}"

    for i, expected in enumerate(BEATS):
        addr = BASE + i * 8
        rdata, rresp = await axi.read(addr)
        assert rresp == RRESP_OKAY, f"Read RRESP beat {i}: {rresp}"
        assert rdata == expected,   f"Beat {i}: got 0x{rdata:016x}"


@cocotb.test()
async def test_boundary_crossing_decerr(dut):
    """2-beat burst at 0x7FFF_FFF8 crosses the APB_ADDR_BIT=31 boundary → DECERR.

    Mirrors axi_crossing_write_decerr task in tb_axi4_to_apb4_2x_burst.v.
    Bridge must not drive APB and must return BRESP=DECERR (2'b11).
    """
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)
    s0, s1 = start_slaves(dut, clk)

    axi = AXI4Driver(dut, clk)
    CROSSING_ADDR = 0x7FFF_FFF8

    # Seed matches the Verilog TB's $random seed for test equivalence.
    beats = [0x3f9012ab, 0xDEAD_C0DE]
    bresp = await axi.burst_write(CROSSING_ADDR, beats)
    assert bresp == BRESP_DECERR, (
        f"Expected DECERR (0b11={BRESP_DECERR}) for crossing burst, got {bresp}"
    )

    # APB slaves must have seen no writes (memory still empty).
    assert not s0.mem, f"APB0 slave mem was written despite DECERR: {s0.mem}"
    assert not s1.mem, f"APB1 slave mem was written despite DECERR: {s1.mem}"


@cocotb.test()
async def test_alternating_slaves(dut):
    """Alternate single writes between APB0 and APB1; verify independence."""
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)
    start_slaves(dut, clk)

    axi = AXI4Driver(dut, clk)
    cases = [
        (0x0000_0010, 0x1111_1111_1111_1111),
        (0x8000_0010, 0x2222_2222_2222_2222),
        (0x0000_0018, 0x3333_3333_3333_3333),
        (0x8000_0018, 0x4444_4444_4444_4444),
    ]

    for addr, data in cases:
        bresp = await axi.write(addr, data)
        assert bresp == BRESP_OKAY, f"Write failed at 0x{addr:08x}: {bresp}"

    for addr, expected in cases:
        rdata, rresp = await axi.read(addr)
        assert rresp == RRESP_OKAY, f"Read rresp at 0x{addr:08x}: {rresp}"
        assert rdata == expected,   f"Mismatch at 0x{addr:08x}: 0x{rdata:016x}"
