# Stress Test Guide

This document describes the randomised stress test system for the AXI4-to-APB4
bridge.  The test exists in two forms that cover the same protocol behaviours:

- **Verilog TB** (`test/tb_stress_burst.v`) — Icarus Verilog, FST waveform,
  configurable via vvp plusargs.  Use this form for waveform-driven debug.
- **UVM mirror** (`test_bridge_stress`) — SystemVerilog/UVM, scoreboard-based
  data integrity, runs under VCS or Xcelium.  Use this form for regression and
  coverage collection.

Both forms exercise the burst bridge (`src/axi4_to_apb4_2x_burst.v`) across
both APB ports, with INCR and FIXED bursts, burst lengths 1–8, and random
write data.

---

## Three-phase test structure

Both the Verilog TB and the UVM sequence use the same three-phase approach:

| Phase | What happens |
|-------|--------------|
| **1 — Seed** | Write 16 (Verilog: 32) known words to each APB port at fixed addresses to give the read phase a valid data set. |
| **2 — Random** | Drive *N* transactions chosen randomly from: single/burst write, single/burst read, INCR/FIXED burst type, APB port 0 or 1, burst length 1–8.  Reads target only addresses that have been written. |
| **3 — Sweep** | Read back all seed words from both ports and verify. |

Data integrity is checked by a shadow model (Verilog) or the UVM scoreboard
(`bridge_scoreboard`) after every transaction.

---

## Verilog TB (`test/tb_stress_burst.v`)

### Configurable knobs

| plusarg | Default | Meaning |
|---------|---------|---------|
| `+N=<n>` | 200 | Number of random transactions in phase 2 |
| `+SEED=<s>` | 0 | `$srandom` seed (0 = simulator default) |
| `+WAIT0=<w>` | 1 | APB0 wait cycles per transfer (0 = no wait) |
| `+WAIT1=<w>` | 1 | APB1 wait cycles per transfer (0 = no wait) |
| `+BP=<b>` | 3 | Max random BREADY/RREADY back-pressure cycles |

### Makefile targets

```
make test-stress                        # run, no waveform
make wave-stress                        # run + write waves_stress.fst
make gtk-stress                         # run + launch GTKWave

# Override knobs:
make test-stress STRESS_N=500 STRESS_SEED=42 STRESS_WAIT0=2 STRESS_WAIT1=0 STRESS_BP=6
make wave-stress STRESS_N=100 WAVEFILE=my_run.fst
```

Top-level Makefile variables that map to plusargs:

| Variable | Default | plusarg |
|----------|---------|---------|
| `STRESS_N` | 200 | `+N=` |
| `STRESS_SEED` | 0 | `+SEED=` |
| `STRESS_WAIT0` | 1 | `+WAIT0=` |
| `STRESS_WAIT1` | 1 | `+WAIT1=` |
| `STRESS_BP` | 3 | `+BP=` |

### Waveform guidance

Open `waves_stress.fst` in GTKWave or Surfer.  Key signal groups to add:

- `ACLK`, `ARESETn`
- AXI write channel: `AWVALID`, `AWREADY`, `AWADDR`, `AWLEN`, `AWBURST`,
  `WVALID`, `WREADY`, `WDATA`, `WSTRB`, `WLAST`, `BVALID`, `BREADY`, `BRESP`
- AXI read channel: `ARVALID`, `ARREADY`, `ARADDR`, `ARLEN`, `ARBURST`,
  `RVALID`, `RREADY`, `RDATA`, `RRESP`, `RLAST`
- APB0: `PSEL0`, `PENABLE0`, `PWRITE0`, `PADDR0`, `PWDATA0`, `PREADY0`, `PRDATA0`
- APB1: `PSEL1`, `PENABLE1`, `PWRITE1`, `PADDR1`, `PWDATA1`, `PREADY1`, `PRDATA1`

The testbench prints `[ERROR]` on any data mismatch; search for this string in
the transcript to locate failing transactions, then zoom into the corresponding
waveform region.

### What the Verilog TB covers

- Single-beat and multi-beat INCR/FIXED bursts to both APB ports
- All burst lengths from 1 to 8
- Random byte-lane strobes on writes
- Variable APB slave wait states (WAIT0, WAIT1)
- Back-pressure on BREADY and RREADY (up to `+BP` cycles)
- 4 kB-boundary-safe addresses
- Data integrity via local shadow model with byte-strobe masking

---

## UVM mirror (`test_bridge_stress`)

The UVM test is implemented as `bridge_stress_seq` in
`uvm/sv/seq/bridge_rand_stim.sv` and the test class `test_bridge_stress` in
`uvm/sv/pkg/bridge_uvm_tests_pkg.sv`.

### Differences from the Verilog TB

| Feature | Verilog TB | UVM mirror |
|---------|-----------|------------|
| Simulator | Icarus (OSS) | VCS or Xcelium |
| Waveform | FST via `+wave` | simulator-native |
| Back-pressure | Yes (`+BP`) | No (BREADY/RREADY always 1) |
| APB wait states | Configurable (`+WAIT0/1`) | APB model in `apb_ext_mem_dual.sv` |
| Data integrity | Local shadow model | `bridge_scoreboard` |
| Seed phrase | `+SEED` | `+ntb_random_seed` (simulator-native) |
| Transaction count | `+N=` (default 200) | `+N=` (default 100) |

The UVM mirror deliberately omits back-pressure because `bridge_axi_stim_64`
drives BREADY and RREADY high throughout each transaction.  Coverage of
back-pressure scenarios is provided by the Verilog TB instead.

### Makefile targets

```
# VCS (requires: export UVM_HOME=/path/to/uvm)
make uvm-vcs-stress                     # default N=100
make uvm-vcs-stress STRESS_N=300

# Xcelium
make uvm-xcelium-stress
make uvm-xcelium-stress STRESS_N=300

# Run directly from the sub-Makefile:
cd uvm/vcs   && make sim_stress STRESS_N=200
cd uvm/xcelium && make sim_stress STRESS_N=200
```

### +UVM_TESTNAME override

The stress test can also be triggered inside any compiled `tb_uvm_burst_ext`
binary by passing `+UVM_TESTNAME=test_bridge_stress +N=<n>`.  The sub-Makefile
targets handle this automatically.

---

## Mirror-check CI gate

`scripts/uvm_mirror_check.py` verifies that the key symbols (`bridge_stress_seq`,
`test_bridge_stress`, `sh_written`, `mark_written`, `all_written`,
`STRESS TEST PASSED`) are present in the UVM source files whenever the Verilog
TB exists.  Run it with:

```
make check-uvm-mirror
```

This gate runs without VCS and is part of the `ci` target.

---

## Implementation notes

### Written-address tracking (`sh_written`)

Because reads must target addresses that have already been written, both the
Verilog TB (via `valid0`/`valid1` arrays) and the UVM sequence (via the
`sh_written` associative array) track which pages have been written before
issuing reads.

For INCR bursts the tracker marks every page touched by the burst
(`addr_page + 0` … `addr_page + burst_len`).  For FIXED bursts only
`addr_page` is marked.  A read is skipped (Verilog) or retried with a forced
write (UVM) if the required pages are not all in the written set.

### Address layout

Both tests use the same addressing scheme as the rest of the bridge test suite:

```
addr[31]    = APB port select (0 = APB0, 1 = APB1)
addr[30:16] = 0
addr[15:3]  = addr_page (13-bit word-group index)
addr[2:0]   = 0 (8-byte aligned)
```

INCR bursts keep `addr_page` below `13'h1000` (8 192 entries) so no burst
crosses the 0x8000_0000 port boundary.
