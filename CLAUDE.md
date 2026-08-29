# CLAUDE.md — IP-axi-to-2apbs

AXI4 → 2× APB4 bridge RTL with self-checking testbenches (directed SV, cocotb,
UVM, formal). One AXI transaction is serialized at a time into APB4 transfers on
one of two APB ports (address bit 31 selects the port). See `README.md` for the
architecture and `doc/PLAN.md` for the development plan.

## Verification flows

| Flow | Where | Simulator |
|------|-------|-----------|
| Directed SV | `sim/` (per `doc/PLAN.md`) | Icarus |
| cocotb | `cocotb/` | Icarus/Verilator |
| UVM | `uvm/sv`, `uvm/tb` | VCS + Xcelium; **open-source Verilator** via `uvm/vlt` |
| Formal | SymbiYosys | OSS CAD Suite |

## Active thread: UVM on open-source Verilator (`uvm/vlt`)

Runs the same UVM env under Verilator 5.050 (license-free), **green in CI**
(all tops: `tb_uvm_simple`, `tb_uvm_burst`, `tb_uvm_burst_ext`,
`tb_uvm_parameterized`, and all four `tb_uvm_regblock` tests build with
`--binary` and run scoreboard-clean — `UVM_ERROR: 0`, `UVM_FATAL: 0`). The
`uvm/vlt` `run` recipe fails on any `UVM_ERROR`/`UVM_FATAL`, so CI is a real
correctness gate. Tracked as near-term item 0 in `doc/PLAN.md` — **DONE
2026-08-28**. **Read `uvm/vlt/README.md` before touching this flow.**

Key facts an agent must know before working here:

- **Verilator must be UVM-capable ≥ 5.050.** The OSS CAD Suite's Verilator is
  NOT — use the standalone `~/verilator` (5.050). `UVM_HOME` =
  `~/verilator/test_regress/t/uvm`.
- **`unset VERILATOR_ROOT`** after sourcing `~/oss-cad-suite/environment` — the
  stale value it exports makes `~/verilator/bin/verilator` hard-error.
- **Local RAM ceiling:** this host is ~8 GB (WSL sees ~5.7 GB). `make -C uvm/vlt
  lint` is cheap (~330 MB) and safe. The full `--binary` build OOMs the VM/
  session — **run the heavy build in CI** (`.github/workflows/verilator-sim.yml`
  builds Verilator 5.050 from source and runs it on a runner), or locally only
  with `BUILD_JOBS=1` under a `ulimit -v` guard. Always lint before building.
- **`uvm/vlt/uvm_macros.svh` is a required tracked shim** — do not delete
  (without it a fresh checkout fails lint with cascading parse errors).
- The shared UVM sources use `` `ifndef VERILATOR `` guards: monitor decoupled,
  covergroup collector excluded under Verilator (scoreboard invariants still
  checked). Details in `uvm/vlt/README.md`.

## Repo/workflow gotchas

- **`origin` is SSH (`git@github.com:...`) and SSH auth fails in this env.** Push
  over HTTPS instead — `gh` is logged in as `markrthomas`:
  `git push https://github.com/markrthomas/IP-axi-to-2apbs.git main`
- `NOTES` is gitignored here (`.gitignore` line 38) — durable knowledge goes in
  tracked docs (`uvm/vlt/README.md`, `doc/`, this file), not a NOTES file.
- Commit narrowly: this repo often carries in-progress edits across several
  files; stage only what a change actually needs.

## Next steps (optional, none blocking)

- ✓ **Containerized UVM-on-Verilator gate (Docker / Railway) — DONE 2026-08-29**
  (PLAN item 7). Runs green end-to-end on Railway Hobby (8 GB); plumbing CI-tested
  (`docker-plumbing.yml`, `docker-image.yml`, `make check-docker`). Details +
  RAM knobs in `uvm/vlt/README.md`.
- **Current near-term focus: PLAN item 8 — unified metrics dashboard.** Aggregate
  every flow + compare/contrast run environments (local/container/Railway/CI) into
  `report/{metrics.json,report.md,report.html}` (`make report`/`report_check`),
  modeled on `~/proj/ucie_rdi_to_pcie6_pipe7`.
- ✓ CI runs all UVM tops (`simple`, `burst`, `burst_ext`, `parameterized`,
  `regblock-*`), all gated on `UVM_ERROR`/`UVM_FATAL`.
- Scoreboard invariants confirmed equivalent to VCS for all tops; coverage
  collectors excluded under Verilator but scoreboard checks still enforced.
- Fix the repeated CI Verilator cache miss (speed only).
- Cosmetic Verilator warnings left un-addressed: `!item.randomize()` WIDTHTRUNC
  (`bridge_rand_stim.sv:259`, `bridge_uvm_tests_pkg.sv:350`), int-unsigned width
  notes in `bridge_rand_stim.sv`.
