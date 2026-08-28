# Development Plan — IP-axi-to-2apbs

**As of:** 2026-05-14

## Current baseline

| Area | Status |
|------|--------|
| RTL | Simple and burst bridge variants; 100% Verilator line coverage |
| Directed simulation | Icarus: simple, burst, burst-extended, wait-state (1–3), parameterized, stress |
| Cocotb | 18 tests across simple (5) and burst (13) bridges; runs in CI |
| UVM environment | Scoreboard, coverage collector, constrained-random sequences (`bridge_rand_seq`, `bridge_stress_seq`), VCS + Xcelium make targets; open-source Verilator flow (`uvm/vlt/`) **green in CI** — all tops (`simple`, `burst`, `burst_ext`, `parameterized`, regblock tests) build and run scoreboard-clean on Verilator 5.050 |
| Formal | SymbiYosys BMC (simple depth 30, burst depth 50) + cover; safety + liveness; all 4 proofs pass; CI gated |
| Coverage | Verilator C++ harnesses; 100% line; HTML report via `make cov-report`; exclusions documented in `doc/coverage_notes.md` |
| CI (GitHub Actions) | `regress` → `uvm-mirror` + `coverage` + `cocotb` + `formal` in parallel; coverage `.info` uploaded as artifact |
| Documentation | `design_contract.md`, `stress_test.md`, `coverage_notes.md`, UVM READMEs, PDF targets |

---

## Near-term

### ~~0 — UVM on open-source Verilator (`uvm/vlt/`)~~ ✓ DONE 2026-08-28

**What:** Run the *same* SystemVerilog UVM env (`uvm/sv`, `uvm/tb`) under
open-source Verilator 5.050 (the first Verilator that can elaborate/run UVM) with
the bundled Accellera UVM 2020.3.1 library, giving a license-free CI path
alongside the VCS/Xcelium flows. Verilator's `--timing` scheduler resolves some
constructs differently from VCS, so the env carries `` `ifndef VERILATOR ``
guards where behavior must diverge.

**Completed (2026-08-28):** All UVM tops build and run scoreboard-clean on
Verilator 5.050 in CI (`tb_uvm_simple`, `tb_uvm_burst`, `tb_uvm_burst_ext`,
`tb_uvm_parameterized`, and all four `tb_uvm_regblock` tests). The `run` recipe
fails on any `UVM_ERROR`/`UVM_FATAL`. The `regblock_cov_collector` covergroup
class was excluded under Verilator (`` `ifndef VERILATOR `` guard in
`regblock_uvm_env_pkg.sv`), matching the pattern used for `bridge_cov_collector`.
Scoreboard invariants confirmed equivalent to VCS for all tops. Divergences
documented in `uvm/vlt/README.md`.

---

### ~~1 — Formal: liveness properties and deeper proof~~ ✓ DONE 2026-05-14

**What:** The existing BMC proofs establish safety (nothing wrong happens) but
not liveness (transactions always complete). A deadlock taking more than 30
cycles would not be caught.  The burst bridge also has the tightest timing: an
8-beat INCR burst through an APB slave with 2 wait states per beat takes roughly
`2 + 8 × (2 + 2) = 34` cycles, just outside the current depth.

**Work items:**

- Add progress properties for each AXI channel:
  ```systemverilog
  // AWVALID accepted within N cycles
  property p_aw_progress;
    S_AXI_AWVALID |-> ##[1:20] S_AXI_AWREADY;
  endproperty
  assert property (p_aw_progress);
  ```
  Repeat for W, B, AR, R channels.
- Bump `depth` from 30 to 50 in `apb4_burst.sby` (simple bridge can stay at 30).
- Add a CI job (`formal:`) that runs `make formal` using the OSS CAD Suite
  SymbiYosys install (`pip install symbiyosys yosys-smtbmc` or the pre-built
  tarball).

**Exit:** `make formal` passes with liveness assertions at depth 50; CI gates
every PR.

---

### 2 — CI: publish the HTML coverage report as an artifact

**What:** The CI `coverage` job already runs `make coverage` and uploads the
raw `.info` files, but never calls `scripts/cov_report.py`.  No human-readable
artifact is produced.

**Work items:**

- Add `make cov-report` after `make coverage` in `.github/workflows/ci.yml`.
- Upload `coverage_report.html` as an artifact named `coverage-report`.

**Exit:** Every CI run produces a browsable `coverage_report.html` accessible
from the Actions summary page.

---

### 3 — W-data stability assumption in formal

**What:** The formal assumptions enforce AWVALID/ARVALID/WVALID stability
(held until READY) but do not constrain WDATA or WSTRB to stay stable between
WVALID assertion and the WREADY handshake.  AXI4 spec §A3.2.1 requires both.
A solver is free to change WDATA mid-handshake, which could produce a false
proof of data-integrity properties.

**Work items:**

- In `apb4_burst_props.sv`, add assume blocks parallel to the existing
  W-channel stability assumes:
  ```systemverilog
  if ($past(S_AXI_WVALID) && !$past(S_AXI_WREADY)) begin
      assume (S_AXI_WDATA == $past(S_AXI_WDATA));
      assume (S_AXI_WSTRB == $past(S_AXI_WSTRB));
  end
  ```
- Re-run proofs and confirm no new counter-examples.

**Exit:** Formal props file updated; proofs still pass; stability assumption
noted in a comment citing AXI4 spec section.

---

### 4 — Wait states in Verilator C++ coverage harnesses

**What:** Both `sim_main_simple.cpp` and `sim_main_burst.cpp` use a
zero-wait-state APB slave (`PREADY = PENABLE`).  The PREADY polling loops in
the RTL are exercised by the Verilog stress TB and cocotb, but not by the
Verilator harness used for coverage.  A reviewer cannot tell whether the 100%
line figure was obtained under realistic APB timing.

**Work items:**

- Add a `wait_states` parameter (default 0) to the `apb_slave()` helper in
  both harnesses.
- Run at least one write and one read with `wait_states = 2` (matching the
  `WAIT_CYCLES = 2` default used elsewhere).
- No change to coverage numbers expected — the polling branch is already hit —
  but the harness becomes more representative.

**Exit:** Both harnesses compile and run cleanly with `wait_states = 2`; `make cov-report` still reports 100%.

---

## Medium-term

### 5 — Exclude `localparam` branch artefact from coverage

**What:** The `localparam EXPECTED_AXSIZE` decode chain generates ~1 600 / 2 000
synthetic branch points (one per `?:` sub-expression per `DATA_WIDTH` variant)
that are compile-time-false for `DATA_WIDTH = 64`.  They make up ~97% of the
branch denominator, rendering the branch metric meaningless.

**Work items:**

- Wrap the `localparam EXPECTED_AXSIZE` block in both RTL files with
  `/*verilator coverage_block_off*/` / `/*verilator coverage_block_on*/`.
- Document the exclusion in `doc/coverage_notes.md` with the same format used
  for the FSM `default` arms.
- Rerun `make cov-report`; verify the branch number rises to a meaningful
  value (expected: high 80–90% range).

**Exit:** Branch metric is interpretable; exclusion is documented with rationale.

---

### 6 — Multi-ID serialization test

**What:** The design contract specifies single-outstanding transactions
(property P10 in the formal spec).  No directed test explicitly checks that
two back-to-back transactions with *different* AXI IDs do serialize — that the
first fully completes before the second is accepted.

**Work items:**

- Add a cocotb test `test_id_serialization` to `cocotb/test_burst_bridge.py`:
  issue AW with ID=1, then immediately issue AW with ID=2 (without waiting for
  B on the first); assert that the second AWREADY is not asserted until after
  BVALID+BREADY for the first.
- Add a matching UVM directed test or sequence that verifies the same invariant
  via the scoreboard.

**Exit:** Test passes; documents the serialization guarantee explicitly.

---

## Longer horizon

| Theme | Aim |
|-------|-----|
| APB3 compatibility mode | Optional `PPROT`/`PSTRB` tie-offs for APB3 peripherals that ignore extensions |
| Synthesis flow | Yosys gate-count baseline; timing-constraint template for FPGA integration |
| Peripheral model library | Stub APB4 UART, GPIO, timer responders for system-level integration testing |
| Parameterized DATA_WIDTH harnesses | Run Verilator coverage for DATA_WIDTH ∈ {32, 64, 128} to validate the AXSIZE decode for each width |
| AXI back-pressure stress | Randomize AWREADY/ARREADY deassertion in the coverage harnesses to exercise the VALID-must-hold requirement |

---

## How to use this file

- Promote a longer-horizon item to near/medium-term when scope is clear.
- Update **Current baseline** when a milestone lands.
- Convert near-term items to GitHub issues with acceptance criteria before starting.
- `make md-pdfs` rebuilds this and all other `doc/*.md` files as PDFs.
