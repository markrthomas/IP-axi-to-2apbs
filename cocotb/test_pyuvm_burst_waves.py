"""
Randomized PyUVM test for axi4_to_apb4_2x_burst, built for waveform viewing.

This reuses the component hierarchy from ``test_pyuvm_burst`` (AxiTxn, AxiDriver,
Scoreboard, BridgeEnv) and drives a longer, seed-controlled random stream so the
resulting trace shows a representative mix of behaviour: INCR and FIXED bursts of
varied length on both APB ports, boundary-crossing DECERR rejections, and the
occasional compliant premature-WLAST write (SLVERR, no deadlock).

Run it with waveform capture via the Makefile target:

    make pyuvm-waves            # dumps sim_build/axi4_to_apb4_2x_burst.fst
    make pyuvm-wave-view        # + opens it in GTKWave

The seed is taken from the PYUVM_SEED environment variable when set (for a
reproducible trace) and is always logged so any run can be replayed with
``PYUVM_SEED=<n> make pyuvm-waves``.  It is self-checking: the same Scoreboard
verifies every read beat, so a bad trace also fails the test.
"""

import os
import random

import cocotb
from cocotb.clock import Clock

from pyuvm import uvm_sequence, uvm_test, uvm_root

# Reuse the whole component stack from the directed PyUVM testbench.
from test_pyuvm_burst import (AxiTxn, BridgeEnv, RESULT, FIXED, INCR)
from env import reset_dut, start_slaves, BRESP_DECERR, BRESP_SLVERR

N_TXN = int(os.environ.get("PYUVM_WAVE_TXNS", "24"))


class RandomSeq(uvm_sequence):
    """Seed-controlled random stimulus with a self-checking write/read-back
    backbone plus periodic error-path transactions."""

    def __init__(self, name="RandomSeq", seed=0):
        super().__init__(name)
        self.seed = seed

    async def _do(self, txn):
        await self.start_item(txn)
        await self.finish_item(txn)
        return txn

    async def body(self):
        rng = random.Random(self.seed)

        for i in range(N_TXN):
            roll = rng.random()

            if roll < 0.10:
                # Boundary-crossing INCR write -> DECERR (no APB side effects).
                cr = await self._do(AxiTxn(is_write=True, addr=0x7FFF_FFF8,
                                          data=[rng.getrandbits(64),
                                                rng.getrandbits(64)]))
                assert cr.resp == BRESP_DECERR, \
                    f"crossing burst expected DECERR, got {cr.resp}"
                continue

            if roll < 0.20:
                # Compliant premature-WLAST write -> SLVERR, must not deadlock.
                awlen    = rng.randint(1, 4)
                wlast_at = rng.randint(0, awlen - 1)
                base     = rng.choice([0x0000_0000, 0x8000_0000]) + 0x0B00
                wl = await self._do(AxiTxn(is_write=True, addr=base,
                                          n_beats=awlen + 1, wlast_at=wlast_at))
                assert wl.resp == BRESP_SLVERR, \
                    f"premature WLAST expected SLVERR, got {wl.resp}"
                continue

            # Normal write then read-back on a random port, checked by the SB.
            port_base = rng.choice([0x0000_0000, 0x8000_0000])
            offset    = rng.randrange(0, 0x0000_8000, 8)
            base      = port_base + offset
            length    = rng.randint(1, 16)
            burst     = rng.choice([INCR, FIXED])
            beats     = [rng.getrandbits(64) for _ in range(length)]

            await self._do(AxiTxn(is_write=True, addr=base, data=beats,
                                 burst_type=burst))
            # A FIXED write leaves only the last beat at PADDR; read it back as a
            # single beat.  An INCR write spreads beats, so read them all back.
            if burst == FIXED:
                await self._do(AxiTxn(is_write=False, addr=base, n_beats=1,
                                     burst_type=FIXED))
            else:
                await self._do(AxiTxn(is_write=False, addr=base, n_beats=length,
                                     burst_type=INCR))


class PyUVMWaveTest(uvm_test):
    def build_phase(self):
        self.env  = BridgeEnv("env", self)
        self.seed = int(os.environ.get("PYUVM_SEED", random.randrange(1 << 30)))

    async def run_phase(self):
        self.raise_objection()
        self.logger.info(f"random seed = {self.seed} "
                        f"(replay with PYUVM_SEED={self.seed})")
        seq = RandomSeq("seq", seed=self.seed)
        await seq.start(self.env.seqr)
        self.drop_objection()


@cocotb.test()
async def pyuvm_burst_waves(dut):
    """Randomized, self-checking PyUVM run intended for waveform capture."""
    RESULT.clear()
    cocotb.start_soon(Clock(dut.ACLK, 10, units="ns").start())
    await reset_dut(dut, dut.ACLK)
    # Mild, asymmetric APB wait states give the trace some stall variety.
    start_slaves(dut, dut.ACLK, wait0=1, wait1=0)

    await uvm_root().run_test("PyUVMWaveTest")

    assert RESULT.get("checks", 0) > 0, "scoreboard checked no read beats"
    assert RESULT.get("errors", 1) == 0, \
        f"scoreboard reported {RESULT.get('errors')} mismatches"
