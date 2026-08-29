# Development Plan — IP-axi-to-2apbs

**As of:** 2026-08-29

## Current baseline

| Area | Status |
|------|--------|
| RTL | Simple and burst bridge variants; 100% Verilator line coverage |
| Directed simulation | Icarus: simple, burst, burst-extended, wait-state (1–3), parameterized, stress |
| Cocotb | 18 tests across simple (5) and burst (13) bridges; runs in CI |
| UVM environment | Scoreboard, coverage collector, constrained-random sequences (`bridge_rand_seq`, `bridge_stress_seq`), VCS + Xcelium make targets; open-source Verilator flow (`uvm/vlt/`) **green in CI** — all tops (`simple`, `burst`, `burst_ext`, `parameterized`, regblock tests) build and run scoreboard-clean on Verilator 5.050 |
| Formal | SymbiYosys BMC (simple depth 30, burst depth 50) + cover; safety + liveness; all 4 proofs pass; CI gated |
| Coverage | Verilator C++ harnesses; 100% line; HTML report via `make cov-report`; exclusions documented in `doc/coverage_notes.md` |
| CI (GitHub Actions) | `regress` → `uvm-mirror` + `coverage` + `cocotb` + `formal` in parallel; coverage `.info` uploaded as artifact. Separate `UVM on Verilator` workflow (`verilator-sim.yml`) builds Verilator 5.050 from source and runs all UVM tops, gated on `UVM_ERROR`/`UVM_FATAL`. `docker-plumbing.yml` (fast: shell + entrypoint dispatch + watcher self-test on every push) and `docker-image.yml` (path-gated: builds the image, exercises the entrypoint) cover the container plumbing |
| Container / off-box compute | Repo-root `Dockerfile` + `docker/entrypoint.sh` + `railway.toml` package the UVM-on-Verilator gate; `make railway-run` deploys to Railway (Hobby, ~8 GB) and returns PASS/FAIL on its own; a startup **resource preflight** fails fast below the RAM floor (the UVM PCH compile needs several GB). See `uvm/vlt/README.md` |
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

### ~~2 — CI: publish the HTML coverage report as an artifact~~ ✓ DONE 2026-08-28

**What:** The CI `coverage` job already runs `make coverage` and uploads the
raw `.info` files, but never calls `scripts/cov_report.py`.  No human-readable
artifact is produced.

**Completed (2026-08-28):** Added `make cov-report` step after `make coverage`
in `.github/workflows/ci.yml` and a second `upload-artifact` step that publishes
`coverage_report.html` as an artifact named `coverage-report`.

---

### ~~3 — W-data stability assumption in formal~~ ✓ DONE (already present)

**What:** The formal assumptions enforce AWVALID/ARVALID/WVALID stability
(held until READY) but do not constrain WDATA or WSTRB to stay stable between
WVALID assertion and the WREADY handshake.  AXI4 spec §A3.2.1 requires both.
A solver is free to change WDATA mid-handshake, which could produce a false
proof of data-integrity properties.

**Completed:** Inspection of `verification/formal/apb4_burst_props.sv` (lines
166–169) and `apb4_simple_props.sv` (lines 201–204) confirmed that the
`S_AXI_WDATA` and `S_AXI_WSTRB` stability assumes are already present inline
within the existing W-channel stability block.  No code change was required.

---

### ~~4 — Wait states in Verilator C++ coverage harnesses~~ ✓ DONE 2026-08-28

**What:** Both `sim_main_simple.cpp` and `sim_main_burst.cpp` use a
zero-wait-state APB slave (`PREADY = PENABLE`).  The PREADY polling loops in
the RTL are exercised by the Verilog stress TB and cocotb, but not by the
Verilator harness used for coverage.  A reviewer cannot tell whether the 100%
line figure was obtained under realistic APB timing.

**Completed (2026-08-28):** Replaced the one-liner `PREADY = PENABLE` logic
with a per-port countdown (`g_ws_cnt0/1`) controlled by a global `g_wait_states`
variable (default 0, zero-wait-state behaviour unchanged). Added test cases 12
(simple) and 16 (burst) that set `g_wait_states = 2` and run one write + one
read (or 4-beat burst read) through the PREADY polling loop.

---

### ~~7 — Containerized UVM-on-Verilator gate (Docker / Railway)~~ ✓ DONE 2026-08-29

**What:** Run the `uvm/vlt` license-free gate off-box, since the `--binary` UVM
build OOMs a RAM-constrained (~8 GB) local host. Package the flow so it runs on
any RAM-generous container host and, in particular, on [Railway](https://railway.com).

**Completed (2026-08-29):** Repo-root `Dockerfile` (multi-stage: builds
UVM-capable Verilator 5.050 from source, bundles the Accellera UVM library),
`docker/entrypoint.sh` (injects toolchain overrides, filters the chatty build
log under Railway's rate limit, and **fails fast via a cgroup resource preflight**
below the RAM floor), and `railway.toml`. Makefile targets `docker-uvm-build`/
`docker-uvm-run`, `railway-deploy`/`railway-logs`, and the one-shot `railway-run`
(login/link + up + a `docker/railway-watch.sh` poller that returns a PASS/FAIL
banner and matching exit code). Validated green end-to-end on Railway Hobby
(8 GB): full `ci` gate — lint + all tops + all four regblock tests — exits 0.
Plumbing is CI-tested (`docker-plumbing.yml`, `docker-image.yml`; `make
check-docker`). RAM findings and knobs (`BUILD_JOBS`, `VL_BUILD_JOBS`,
`CFLAGS_MODEL`, `UVM_MIN_MEM_MB`) documented in `uvm/vlt/README.md`.

---

### ~~8 — Unified metrics collection + HTML dashboard (compare & contrast)~~ ✓ DONE 2026-08-29

**What:** There is no single place that aggregates the suite's verification and
performance metrics, and nothing captures *where/how* a run executed. Build one
report that both (a) rolls up results across every flow — directed SV (Icarus),
cocotb/pyUVM, the UVM tops on Verilator, formal, and coverage — and (b) compares
and contrasts the same work across **run environments**: the local box, the
Docker container, Railway, and GitHub CI (build time, peak RAM, walltime, sim
speed, pass/fail). Emit a self-contained HTML dashboard.

Modeled on `~/proj/ucie_rdi_to_pcie6_pipe7` (`scripts/gen_report.py` +
`report/{metrics.json,report.md,report.html}`, driven by `make report` /
`make report_check`, with an advisory `scripts/report_thresholds.json`).

**Completed (2026-08-29):** `scripts/gen_report.py` aggregates coverage (three
`coverage_*.info`, line + branch, DUT-only), the UVM tops' `run.log` (status +
UVM counts + walltime + peak MB), cocotb JUnit (all `cocotb/*/results.xml`),
formal, and perf into `report/{metrics.json,report.md,report.html}`, degrading
gracefully on missing inputs. The **compare/contrast** axis auto-detects the run
environment (local / container / railway / ci, or `--env`) and merges per-top
metrics — plus any `report/env-*.json` fragments — into `environments.json`,
rendered as a per-top × per-environment table (walltime / peak RSS). `make report`
runs the feasible flows then aggregates; `make report_check` is the advisory
threshold gate (`scripts/report_thresholds.json`), **not** wired into the required
`ci`. CI publishes the dashboard: `verilator-sim.yml` runs `gen_report --env ci`
and uploads the `metrics-report` artifact; the container entrypoint emits and
echoes an `env-*.json` fragment (the container FS is ephemeral) so a Docker/Railway
run can contribute its environment to a combined report.

**Original work items (all addressed above):**

- `scripts/gen_report.py` — aggregate, with graceful degradation on missing
  inputs:
  - **Coverage:** `coverage.info` (LCOV) → total + per-DUT-file line/branch %.
  - **UVM tops:** each `uvm/vlt/obj/<top>/run.log` → `UVM_INFO/WARNING/ERROR/
    FATAL` counts, and the Verilator `$finish` line → sim walltime / speed.
  - **Formal:** SymbiYosys log → per-proof PASS/FAIL + depth.
  - **cocotb:** `results.xml` (JUnit) → per-test pass/fail + timing.
  - **Directed SV:** regress log → `[TAG] PASS` matrix + `[PERF]` lines.
- **Run-environment metadata** (the compare/contrast axis): capture build time,
  peak RSS (`/usr/bin/time -v` or cgroup peak), walltime, and pass/fail per
  environment. The container entrypoint emits a `metrics.json` fragment from the
  gate run so local / container / Railway / CI runs feed the same schema and can
  be diffed side by side (e.g. `tb_uvm_simple` build RAM: local vs Railway vs CI).
- **Outputs:** `report/{metrics.json, report.md, report.html}`; the HTML has a
  per-flow results table, a coverage table, and a run-environment compare/contrast
  section.
- **Targets:** `make report` (run the flows into `report/logs/`, then aggregate)
  and `make report_check` (advisory perf/quality threshold gate over
  `report/metrics.json` — **not** part of the required `ci` gate; a sim-timing
  wobble must not red the build).
- **CI:** upload `report.html` as an artifact; have the container `docker-image`
  path and/or a report job produce it.

**Exit:** `make report` produces `report/report.html` summarizing every flow and
comparing the run environments; the report is published as a CI artifact.

---

## Medium-term

### ~~5 — Exclude `localparam` branch artefact from coverage~~ ✓ DONE 2026-08-28

**What:** The `localparam EXPECTED_AXSIZE` decode chain generates ~1 600 / 2 000
synthetic branch points (one per `?:` sub-expression per `DATA_WIDTH` variant)
that are compile-time-false for `DATA_WIDTH = 64`.  They make up ~97% of the
branch denominator, rendering the branch metric meaningless.

**Completed (2026-08-28):** Both RTL files (`src/axi4_to_apb4_2x_simple.v` and
`src/axi4_to_apb4_2x_burst.v`) now bracket the `localparam EXPECTED_AXSIZE`
block with `// verilator coverage_off` / `// verilator coverage_on` line-form
directives (the `coverage_block_off` inline pragma only works inside
`begin`/`end` blocks; `localparam` is module-level).  Exclusion documented in
`doc/coverage_notes.md` with rationale and pragma choice explained.  Branch
metric expected to rise to high 80–90% on next CI run.

---

### ~~6 — Multi-ID serialization test~~ ✓ DONE 2026-08-28

**What:** The design contract specifies single-outstanding transactions
(property P10 in the formal spec).  No directed test explicitly checks that
two back-to-back transactions with *different* AXI IDs do serialize — that the
first fully completes before the second is accepted.

**Completed (2026-08-28):** Added `test_id_serialization` to
`cocotb/test_burst_bridge.py`.  The test issues AW+W for ID=1 (withholding
BREADY to keep the bridge in the B-response phase), then immediately asserts
AWVALID for ID=2.  A per-cycle monitor tracks whether AWREADY fires for ID=2
before the BVALID+BREADY handshake of ID=1 completes and fails with an
explicit message if the serialization guarantee is broken.  The UVM scoreboard
already enforces single-outstanding-transaction invariants for all UVM tops;
the cocotb test provides a complementary lightweight directed proof.

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
