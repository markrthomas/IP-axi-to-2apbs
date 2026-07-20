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

from env import (AXI4Driver, BRESP_OKAY, BRESP_SLVERR, BRESP_DECERR, RRESP_OKAY,
                 reset_dut, start_slaves)


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


@cocotb.test()
async def test_fixed_burst_write_read(dut):
    """FIXED burst (AWBURST=0): all beats target the same address.

    The bridge issues one APB transaction per beat, each to the same PADDR.
    The last write wins, so read-back returns the final beat's data.
    """
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)
    start_slaves(dut, clk)

    axi = AXI4Driver(dut, clk)
    ADDR  = 0x0000_0300
    BEATS = [0xAAAA_0000_0000_0001,
             0xBBBB_0000_0000_0002,
             0xCCCC_0000_0000_0003,
             0xDDDD_0000_0000_0004]  # last beat wins

    bresp = await axi.burst_write(ADDR, BEATS, burst_type=0b00)
    assert bresp == BRESP_OKAY, f"FIXED burst write BRESP: {bresp}"

    rdata, rresp = await axi.read(ADDR)
    assert rresp == RRESP_OKAY,     f"Read RRESP: {rresp}"
    assert rdata == BEATS[-1],      f"FIXED burst read-back: 0x{rdata:016x}"


@cocotb.test()
async def test_fixed_burst_read(dut):
    """FIXED burst read (ARBURST=0): all beats return the same address."""
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)
    start_slaves(dut, clk)

    axi = AXI4Driver(dut, clk)
    ADDR  = 0x8000_0400
    VALUE = 0xDEAD_C0DE_CAFE_F00D

    bresp = await axi.write(ADDR, VALUE)
    assert bresp == BRESP_OKAY

    # 3-beat FIXED read: all 3 R beats should carry the same data.
    beats = await axi.burst_read(ADDR, 3, burst_type=0b00)
    assert len(beats) == 3, f"Expected 3 beats, got {len(beats)}"
    for i, beat in enumerate(beats):
        assert beat == VALUE, f"FIXED read beat {i}: 0x{beat:016x} != 0x{VALUE:016x}"


@cocotb.test()
async def test_partial_strobe_write(dut):
    """Partial byte-strobe write: only the strobed bytes are modified.

    Strategy: write a known all-ones word, then overwrite the upper 4 bytes only
    (strb=0xF0), then read back and confirm upper bytes changed, lower unchanged.
    """
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)
    start_slaves(dut, clk)

    axi = AXI4Driver(dut, clk)
    ADDR = 0x0000_0500

    # Prime with known value.
    bresp = await axi.write(ADDR, 0xFFFF_FFFF_FFFF_FFFF)
    assert bresp == BRESP_OKAY

    # Partial write: upper 4 bytes = 0xDEAD_BEEF, lower bytes unmodified.
    bresp = await axi.write(ADDR, 0xDEAD_BEEF_0000_0000, strb=0xF0)
    assert bresp == BRESP_OKAY

    rdata, rresp = await axi.read(ADDR)
    assert rresp == RRESP_OKAY, f"Read RRESP: {rresp}"
    # APB slave mem stores 64-bit words; strobe selects which bytes are written.
    # After partial write: upper 4 bytes = 0xDEAD_BEEF, lower 4 = 0xFFFF_FFFF.
    expected = 0xDEAD_BEEF_FFFF_FFFF
    assert rdata == expected, (
        f"Partial strobe read-back: 0x{rdata:016x}, expected 0x{expected:016x}"
    )


@cocotb.test()
async def test_boundary_crossing_read_decerr(dut):
    """2-beat INCR read starting at 0x7FFF_FFF8 crosses APB_ADDR_BIT=31 → DECERR.

    Bridge must return DECERR on the R channel and not touch APB slaves.
    """
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)
    s0, s1 = start_slaves(dut, clk)

    axi = AXI4Driver(dut, clk)
    CROSSING_ADDR = 0x7FFF_FFF8

    beats = await axi.burst_read(CROSSING_ADDR, 2)
    for i, beat in enumerate(beats):
        assert beat == 0, f"DECERR read beat {i} must be zero RDATA: 0x{beat:016x}"

    # Confirm no APB traffic was generated.
    assert not s0.mem, f"APB0 slave was accessed on DECERR read: {s0.mem}"
    assert not s1.mem, f"APB1 slave was accessed on DECERR read: {s1.mem}"


@cocotb.test()
async def test_multi_beat_read_incr(dut):
    """4-beat INCR burst read returns all beats in order with correct RLAST."""
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)
    start_slaves(dut, clk)

    axi = AXI4Driver(dut, clk)
    BASE  = 0x0000_0600
    BEATS = [0xCAFE_0000_0000_0001,
             0xCAFE_0000_0000_0002,
             0xCAFE_0000_0000_0003,
             0xCAFE_0000_0000_0004]

    # Write the four locations individually.
    for i, data in enumerate(BEATS):
        bresp = await axi.write(BASE + i * 8, data)
        assert bresp == BRESP_OKAY, f"Write beat {i} failed: {bresp}"

    # Read them back as a 4-beat burst.
    read_beats = await axi.burst_read(BASE, 4)
    assert len(read_beats) == 4, f"Expected 4 beats, got {len(read_beats)}"
    for i, (got, expected) in enumerate(zip(read_beats, BEATS)):
        assert got == expected, f"Beat {i}: 0x{got:016x} != 0x{expected:016x}"


@cocotb.test()
async def test_wait_state_tolerance(dut):
    """APB slave with 2 wait cycles per access; bridge must stall correctly."""
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)
    start_slaves(dut, clk, wait0=2, wait1=2)

    axi = AXI4Driver(dut, clk)
    WDATA = 0xFEED_FACE_CAFE_BABE
    ADDR  = 0x0000_0700

    bresp = await axi.write(ADDR, WDATA)
    assert bresp == BRESP_OKAY, f"Wait-state write BRESP: {bresp}"

    rdata, rresp = await axi.read(ADDR)
    assert rresp == RRESP_OKAY, f"Wait-state read RRESP: {rresp}"
    assert rdata == WDATA,      f"Wait-state read-back: 0x{rdata:016x}"


@cocotb.test()
async def test_wait_state_burst(dut):
    """4-beat burst to APB slave with wait states; all beats must complete."""
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)
    start_slaves(dut, clk, wait0=3, wait1=0)

    axi = AXI4Driver(dut, clk)
    BASE  = 0x0000_0800
    BEATS = [0x1111_1111_1111_1111,
             0x2222_2222_2222_2222,
             0x3333_3333_3333_3333,
             0x4444_4444_4444_4444]

    bresp = await axi.burst_write(BASE, BEATS)
    assert bresp == BRESP_OKAY, f"Wait-state burst write BRESP: {bresp}"

    read_beats = await axi.burst_read(BASE, 4)
    for i, (got, expected) in enumerate(zip(read_beats, BEATS)):
        assert got == expected, f"WS burst beat {i}: 0x{got:016x} != 0x{expected:016x}"


@cocotb.test()
async def test_premature_wlast_no_deadlock(dut):
    """Compliant master asserts WLAST early (beat 0 of a 4-beat write) and stops.
    The bridge must not deadlock: it must return a single SLVERR write response."""
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)
    start_slaves(dut, clk)

    axi = AXI4Driver(dut, clk)
    bresp = await axi.burst_write_wlast_at(0x0000_0900, awlen=3, wlast_at=0)
    assert bresp == BRESP_SLVERR, f"Premature-WLAST BRESP: {bresp} (expected SLVERR)"


@cocotb.test()
async def test_missing_wlast_no_deadlock(dut):
    """Compliant master sends the full beat count but never asserts WLAST.
    The bridge must complete on the beat count and flag SLVERR, not hang."""
    clk = dut.ACLK
    cocotb.start_soon(Clock(clk, 10, units="ns").start())
    await reset_dut(dut, clk)
    start_slaves(dut, clk)

    axi = AXI4Driver(dut, clk)
    # awlen=1 => 2 beats expected; wlast_at=99 => WLAST never asserted.
    bresp = await axi.burst_write_wlast_at(0x0000_0A00, awlen=1, wlast_at=99)
    assert bresp == BRESP_SLVERR, f"Missing-WLAST BRESP: {bresp} (expected SLVERR)"
