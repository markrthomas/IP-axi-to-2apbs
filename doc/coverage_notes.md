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

| Bridge | Line coverage | Branch coverage |
|--------|--------------|-----------------|
| `axi4_to_apb4_2x_simple` | **100%** (132/132) | ~3% |
| `axi4_to_apb4_2x_burst`  | **100%** (215/215) | ~7% |

Branch coverage is structurally low for a reason explained in §Branch artefact
below; the number is not a meaningful signal for this codebase.

---

## Exclusions

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

## Branch coverage artefact

Verilator instruments every sub-expression of a conditional as a separate
branch point.  Both bridges contain:

```verilog
localparam EXPECTED_AXSIZE =
    (DATA_WIDTH == 1024) ? 3'b111 :
    (DATA_WIDTH == 512)  ? 3'b110 :
    ...
    3'b011;  // DATA_WIDTH = 64 (the only instantiated width)
```

For `DATA_WIDTH=64` all arms except the last are compile-time-false.
Verilator still counts each `?:` operand as a separate branch — roughly
1 600 branch points for `simple` and 2 000 for `burst` — all permanently
zero because Verilator folds the dead arms.  These synthetic points make
up ~97% of the branch denominator and cannot be covered by any stimulus.

**Decision:** no exclusion pragma applied to the `localparam` block.
Adding `coverage_block_off` there would also suppress coverage of the
runtime-active boolean expressions that happen to be nearby.  The branch
metric is therefore treated as not meaningful for this codebase and is
displayed for informational purposes only.

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
