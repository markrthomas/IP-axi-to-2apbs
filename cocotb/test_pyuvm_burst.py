"""
PyUVM testbench for axi4_to_apb4_2x_burst.

This is a UVM-structured counterpart to the plain-cocotb suite in
``test_burst_bridge.py``.  It exercises the same DUT through a full pyUVM
component hierarchy so the project has a PyUVM reference flow alongside the
SystemVerilog UVM env under ``uvm/``:

    AxiTxn            sequence item (a whole AXI burst: write or read)
    BurstSeq          directed + constrained-random write/read-back stimulus
    AxiDriver         pin-level driver, reusing env.AXI4Driver, broadcasts
                      each completed txn on an analysis port
    Scoreboard        uvm_subscriber holding a reference memory model; checks
                      every read beat against the last write to that address
    BridgeEnv         wires sequencer -> driver -> scoreboard
    BurstBridgeTest   raises objection, runs the sequence, drops objection

The APB side is modelled by env.APBSlave (memory-backed), same as the other
cocotb tests.  Run with:  make -C cocotb/pyuvm_burst
"""

import random

import cocotb
from cocotb.clock import Clock

from pyuvm import (uvm_sequence_item, uvm_sequence, uvm_driver, uvm_sequencer,
                   uvm_subscriber, uvm_env, uvm_test, uvm_analysis_port,
                   uvm_root)

from env import (AXI4Driver, reset_dut, start_slaves,
                 BRESP_OKAY, BRESP_DECERR)

# Module-level result sink.  check_phase() records the scoreboard tallies here
# so the cocotb entry point can turn a UVM-side mismatch into a test failure
# (a logged uvm error alone does not fail the cocotb test).
RESULT = {}

FIXED = 0b00
INCR  = 0b01


class AxiTxn(uvm_sequence_item):
    """One AXI burst.  For a write, ``data`` holds the beats; for a read,
    ``n_beats`` says how many beats to fetch and ``rdata`` receives them."""

    def __init__(self, name="AxiTxn", is_write=True, addr=0, data=None,
                 n_beats=1, burst_type=INCR, wlast_at=None):
        super().__init__(name)
        self.is_write   = is_write
        self.addr       = addr
        self.data       = list(data) if data else []
        self.n_beats    = len(self.data) if self.data else n_beats
        self.burst_type = burst_type
        # wlast_at: if set on a write, the driver asserts WLAST at that beat and
        # then stops (compliant-master premature/missing WLAST) instead of a
        # normal full-length burst.  Left None for ordinary transfers.
        self.wlast_at   = wlast_at
        # Results filled in by the driver:
        self.resp  = None
        self.rdata = []

    def __str__(self):
        kind = "WR" if self.is_write else "RD"
        bt   = "FIXED" if self.burst_type == FIXED else "INCR"
        wl   = "" if self.wlast_at is None else f" wlast@{self.wlast_at}"
        return (f"{kind} addr=0x{self.addr:08x} beats={self.n_beats} {bt}{wl} "
                f"resp={self.resp}")


class AxiDriver(uvm_driver):
    """Drives AXI bursts by delegating to env.AXI4Driver, then broadcasts the
    completed transaction (with results) to any analysis subscribers."""

    def build_phase(self):
        self.ap = uvm_analysis_port("ap", self)
        # TOPLEVEL is the DUT itself, so cocotb.top is the DUT handle.  This
        # avoids ConfigDB, which run_test() clears along with all singletons.
        self.dut = cocotb.top

    async def run_phase(self):
        axi = AXI4Driver(self.dut, self.dut.ACLK)
        while True:
            txn = await self.seq_item_port.get_next_item()
            if txn.is_write and txn.wlast_at is not None:
                txn.resp = await axi.burst_write_wlast_at(
                    txn.addr, awlen=txn.n_beats - 1, wlast_at=txn.wlast_at,
                    burst_type=txn.burst_type)
            elif txn.is_write:
                txn.resp = await axi.burst_write(
                    txn.addr, txn.data, burst_type=txn.burst_type)
            else:
                txn.rdata = await axi.burst_read(
                    txn.addr, txn.n_beats, burst_type=txn.burst_type)
            self.logger.info(str(txn))
            self.ap.write(txn)
            self.seq_item_port.item_done()


class Scoreboard(uvm_subscriber):
    """Reference model of the dual-APB memory.  OKAY writes update the model;
    every read beat is checked against it.  DECERR writes must leave no trace."""

    def build_phase(self):
        self.model  = {}   # AXI byte address -> 64-bit word
        self.checks = 0
        self.errors = 0

    @staticmethod
    def _beat_addr(txn, i):
        # FIXED bursts hold the address; INCR advances 8 bytes per beat.
        return txn.addr if txn.burst_type == FIXED else txn.addr + i * 8

    def write(self, txn):
        if txn.is_write:
            if txn.resp == BRESP_OKAY:
                for i, beat in enumerate(txn.data):
                    self.model[self._beat_addr(txn, i)] = beat
            elif txn.resp == BRESP_DECERR:
                # A rejected burst must not have reached the APB memory; the
                # model is intentionally left unchanged so a later read of the
                # same address returns 0 and would flag any stray write.
                pass
        else:
            for i, got in enumerate(txn.rdata):
                addr = self._beat_addr(txn, i)
                exp  = self.model.get(addr, 0)
                self.checks += 1
                if got != exp:
                    self.errors += 1
                    self.logger.error(
                        f"read mismatch @0x{addr:08x}: got 0x{got:016x} "
                        f"exp 0x{exp:016x}")

    def check_phase(self):
        RESULT["checks"] = self.checks
        RESULT["errors"] = self.errors
        self.logger.info(f"scoreboard: {self.checks} beats checked, "
                         f"{self.errors} mismatches")


class BurstSeq(uvm_sequence):
    """Directed + constrained-random write/read-back over both APB ports,
    a FIXED burst, and a boundary-crossing burst that must return DECERR."""

    async def _do(self, txn):
        await self.start_item(txn)
        await self.finish_item(txn)
        return txn

    async def body(self):
        rng = random.Random(0xC0FFEE)

        # Directed: FIXED burst — last beat wins on read-back.
        await self._do(AxiTxn(is_write=True, addr=0x0000_0300,
                              data=[0xA1 << 56 | 1, 0xB2 << 56 | 2,
                                    0xC3 << 56 | 3, 0xD4 << 56 | 4],
                              burst_type=FIXED))
        rd = await self._do(AxiTxn(is_write=False, addr=0x0000_0300,
                                  n_beats=1, burst_type=FIXED))
        assert rd.rdata[0] == (0xD4 << 56 | 4), "FIXED read-back wrong beat"

        # Directed: boundary-crossing INCR write must be DECERR, no APB write.
        cr = await self._do(AxiTxn(is_write=True, addr=0x7FFF_FFF8,
                                  data=[0xDEAD_BEEF, 0xCAFE_F00D]))
        assert cr.resp == BRESP_DECERR, \
            f"crossing burst expected DECERR, got {cr.resp}"

        # Constrained-random: write-then-read bursts on both ports.
        for _ in range(12):
            port_base = rng.choice([0x0000_0000, 0x8000_0000])
            offset    = rng.randrange(0, 0x0000_8000, 8)  # 8-byte aligned
            base      = port_base + offset
            length    = rng.randint(1, 8)
            beats     = [rng.getrandbits(64) for _ in range(length)]

            await self._do(AxiTxn(is_write=True, addr=base, data=beats))
            await self._do(AxiTxn(is_write=False, addr=base, n_beats=length))


class BridgeEnv(uvm_env):
    def build_phase(self):
        self.seqr       = uvm_sequencer("seqr", self)
        self.driver     = AxiDriver("driver", self)
        self.scoreboard = Scoreboard("scoreboard", self)

    def connect_phase(self):
        self.driver.seq_item_port.connect(self.seqr.seq_item_export)
        self.driver.ap.connect(self.scoreboard.analysis_export)


class BurstBridgeTest(uvm_test):
    def build_phase(self):
        self.env = BridgeEnv("env", self)

    async def run_phase(self):
        self.raise_objection()
        seq = BurstSeq("seq")
        await seq.start(self.env.seqr)
        self.drop_objection()


@cocotb.test()
async def pyuvm_burst_test(dut):
    """cocotb entry point: bring up clock/reset + APB slaves, then run the
    PyUVM test.  Fails if the scoreboard saw no beats or any mismatch."""
    RESULT.clear()
    cocotb.start_soon(Clock(dut.ACLK, 10, units="ns").start())
    await reset_dut(dut, dut.ACLK)
    start_slaves(dut, dut.ACLK)

    await uvm_root().run_test("BurstBridgeTest")

    assert RESULT.get("checks", 0) > 0, "scoreboard checked no read beats"
    assert RESULT.get("errors", 1) == 0, \
        f"scoreboard reported {RESULT.get('errors')} mismatches"
