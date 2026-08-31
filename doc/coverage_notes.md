# Coverage Notes

This document records every deliberate coverage exclusion and every stimulus
addition made to improve coverage numbers, so a future reviewer can audit the
reported 100% line figures without digging through git history.

Run the report:

```
make cov-report                   # build, run, terminal table + coverage_report.html
COV_REPORT_HTML=my.html make cov-report
```

---

## Reported numbers

**Line coverage is the enforced signal.**  The second Verilator metric is
**toggle coverage**, not branch coverage — see §Toggle coverage for why it is
informational (and inherently low).

| Bridge | Line coverage | Toggle coverage |
|--------|--------------|-----------------|
| `axi4_to_apb4_2x_simple`   | **100%** (132/132) | ~59% (939/1601) |
| `axi4_to_apb4_2x_burst`    | **100%** (220/220) | ~62% (1242/2012) |
| `axi3lite_regblock`        | **100%** (101/101) | ~62% (262/424) |

Pooled toggle: **60.5%** (2443/4037).  (Measured 2026-08-31 with oss-cad-suite
Verilator 5.0x via `make coverage`.)  Toggle points are counted directly from
the lcov `BRDA` records; do **not** trust the `BRH` summary line
`verilator_coverage` writes — it is inconsistent with its own BRDA data (reports
~55 hit for `simple` where 939 BRDA points actually have `taken>0`) and would
under-report toggle ~10×.

---

## Exclusions

### `axi4_to_apb4_2x_simple.v` — `localparam EXPECTED_AXSIZE` dead-arm exclusion

**Location:** `src/axi4_to_apb4_2x_simple.v`, module body (after port list).

```verilog
// verilator coverage_off
localparam EXPECTED_AXSIZE = (DATA_WIDTH == 1024) ? 3'b111 :
                             ...
                             3'b000;
// verilator coverage_on
```

**Why excluded:** the `?:` chain has one live arm per `DATA_WIDTH`; the
others are compile-time-dead.  The pragma keeps those folded arms out of
the coverage denominator so they can't show as misses.  This is a small,
tidy exclusion — a handful of points, **not** the bulk of the metric.

> Correction (2026-08-31): earlier notes claimed this localparam generated
> ~1 600 / ~2 000 "synthetic branch points" dominating the denominator.
> That was wrong.  Verilator emits no control-flow branch coverage at all;
> the large `BRDA` denominator is **toggle** coverage of the 64-bit datapath
> (`WDATA`/`RDATA`/`PWDATA`/`PRDATA`/`wdata_reg` are 128 toggle points each),
> and this pragma does not materially change it.  See §Toggle coverage.

**Pragma used:** `// verilator coverage_off` / `// verilator coverage_on`
line-form directives (the `coverage_block_off` inline form only works
inside `begin`/`end` blocks; a `localparam` is module-level).  The
directives bracket only the `localparam` lines — no runtime-active logic
is within the exclusion window.

---

### `axi4_to_apb4_2x_burst.v` — `localparam EXPECTED_AXSIZE` dead-arm exclusion

**Location:** `src/axi4_to_apb4_2x_burst.v`, module body (after port list).

Same rationale and same 2026-08-31 correction as the simple bridge above.

---

### `axi4_to_apb4_2x_simple.v` — FSM `default` arm

**Location:** `src/axi4_to_apb4_2x_simple.v`, inside the `always @(posedge ACLK)` FSM block.

```verilog
default: begin /*verilator coverage_block_off*/ state <= ST_IDLE; end
```

**Why excluded:** The state register is 3 bits wide and only six named states
(`ST_IDLE` … `ST_READ_RESP`) are ever assigned.  Synthesis tools encode the
FSM in either binary or one-hot; neither encoding can produce a value outside
the named set through any legal AXI transaction sequence.  The `default` arm
is a defensive catch-all required by tool warnings; it is structurally
unreachable.

**Pragma used:** `/*verilator coverage_block_off*/` inside a `begin`/`end`
wrapper.  This removes the line from Verilator's instrumented denominator
so it does not appear as a miss.

**Verification of the claim:** The SymbiYosys formal proof
(`verification/formal/apb4_simple.sby`) proves mutual exclusion of the
PSEL0/PSEL1 signals and correct handshake sequencing under all reachable
states; no path to an out-of-range state exists in the bounded proof depth.

---

### `axi4_to_apb4_2x_burst.v` — APB FSM `default` arm

**Location:** `src/axi4_to_apb4_2x_burst.v`, inside the `always @(posedge ACLK)` APB sub-FSM block.

```verilog
default: begin /*verilator coverage_block_off*/ apb_state <= APB_IDLE; end
```

**Why excluded:** Same rationale as the simple bridge.  `apb_state` is a
2-bit register with three named states (`APB_IDLE`, `APB_SETUP`,
`APB_ACCESS`); the fourth encoding (2'b11) is never assigned.

**Verification of the claim:** The SymbiYosys formal proof
(`verification/formal/apb4_burst.sby`) proves APB handshake timing and
mutual exclusion for all reachable states.

---

## Toggle coverage

The second column in the coverage reports is **toggle coverage**, not branch
coverage.  Two facts make this so:

1. `make coverage` runs Verilator with `--coverage`, which is
   `--coverage-line --coverage-toggle --coverage-user`.  **Verilator emits no
   control-flow branch coverage** — there is no branch metric to report.
2. `verilator_coverage --write-info` has no lcov record type for toggle points,
   so it writes each one as a `BRDA` (branch-data) record.  Our report scripts
   read `BRDA` and — correctly — label it toggle coverage.

A toggle point is one signal bit changing in one direction, so a 64-bit bus is
`64 × 2 = 128` points.  The three DUTs have wide datapaths (`WDATA`, `RDATA`,
`PWDATA0/1`, `PRDATA0/1`, `wdata_reg`, …), which is why the denominators are in
the thousands.  Measured toggle coverage is **~60% pooled** (58.7% simple, 61.7%
burst, 61.8% regblock): control signals, handshakes, FSM state bits and the low
address/data bits toggle freely, while the high bits of the wide busses do not
flip both ways under the current stimulus — expected for a pass-through datapath
and not a defect.

Toggle **is** gated advisorily: `scripts/report_thresholds.json` sets
`min_toggle_coverage_pct` to `55.0`, a floor with margin below the 60.5%
baseline, so a large regression is caught while normal run-to-run jitter is not.
Line coverage (100%) remains the primary enforced signal.

Counting note: toggle % is computed **directly from the `BRDA` records** (one per
signal-bit edge) in both `scripts/cov_report.py` and `scripts/gen_report.py`.
The `BRF`/`BRH` summary lines `verilator_coverage` emits are ignored because its
`BRH` is inconsistent with the BRDA data it writes.

To push toggle higher, target the *upper* data/address bits with a few extra
patterns (all-ones, walking-ones); chasing every datapath bit with random data
is low value for a bridge that does not transform data.

---

## Stimulus additions (what was added to reach 100%)

The C++ harnesses (`sim_main_simple.cpp`, `sim_main_burst.cpp`) were
extended beyond the initial "happy path" tests to reach every reachable
line.  The additions are legitimate functional tests — each one exercises
a distinct RTL path.

### `sim_main_simple.cpp`

| Stimulus added | RTL path covered |
|---------------|-----------------|
| `read_single` with `arlen=1` | `ST_READ_RESP` error path (lines 152–153): single-beat-only bridge rejects multi-beat AR with RRESP=DECERR |
| `write_single` / `read_single` with `g_slverr_port=0` (APB0) | `PSLVERR0 ? 2'b10 : 2'b00` branch in write and read response paths |
| `write_single` / `read_single` with `g_slverr_port=1` (APB1) | Same branch on APB1 side |
| `write_single` / `read_single` with non-zero `AWPROT`/`ARPROT` to **both** slaves | `prot_reg` capture and `PPROT0`/`PPROT1` output assignment |

PSLVERR injection mechanism: the `apb_slave()` helper drives `PSLVERRx=1`
while `PENABLEx` is asserted (the APB access phase), which is exactly when
the bridge samples it.  The flag is cleared after the B or R handshake
completes so subsequent transactions are clean.

### `sim_main_burst.cpp`

| Stimulus added | RTL path covered |
|---------------|-----------------|
| `do_read` with `arburst=2` (WRAP) | `txn_decerr` read path (lines 281–286): RRESP=DECERR for illegal burst type |
| `do_aw` addr=`0x7FFFFFE8`, `awlen=3`, INCR write + matching read | `aw_cross_apb`/`ar_cross_apb` wires (lines 116–117): INCR burst whose last address crosses the 0x80000000 port boundary → `txn_decerr` |
| `g_slverr_port=0`, `g_slverr_beats=1` write then read | `pslverr_acc` accumulator (line 96); `BRESP=SLVERR` and `rresp_fifo` write path (line 194) |
| `g_slverr_port=1` write | APB1 PSLVERR path |
| 4-beat write with WLAST forced on beat 1 of 4 | `wlast_err` register (line 97, line 185): bridge detects misplaced WLAST and folds it into BRESP=SLVERR |
| `AWPROT`/`ARPROT` non-zero to **both** slaves | `axi_prot_reg` capture; `PPROT0` and `PPROT1` output assignment |

Address calculation for the crossing stimulus:

```
addr      = 0x7FFF_FFE8
awlen     = 3  (4 beats)
awsize    = 3  (8 bytes per beat)
last_addr = 0x7FFF_FFE8 + (3 × 8) = 0x8000_0000
addr[31]  = 0,  last_addr[31] = 1  →  aw_cross_apb = 1
```

---

## What is NOT excluded or adjusted

- The `PPROT` and `PSLVERR` port declarations that Verilator counts as
  needing both values (0 and 1) are covered by the PROT and SLVERR
  stimulus above — no exclusion needed.
- The `ARLEN`/`ARPROT`/`AWPROT` input ports: covered by the stimulus
  additions.
- All state-machine states in both FSMs are now visited.
- No RTL logic was altered to make it easier to cover; only the
  `default` arms received the `coverage_block_off` pragma.
