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
- ✓ **Unified metrics dashboard — DONE 2026-08-29** (PLAN item 8).
  `scripts/gen_report.py` + `make report`/`report_check` aggregate every flow into
  `report/{metrics.json,report.md,report.html}` and compare/contrast run
  environments (local/container/Railway/CI) via `environments.json` + `env-*.json`
  fragments. CI publishes the `metrics-report` artifact (`verilator-sim.yml`);
  container entrypoint echoes an env fragment. Modeled on
  `~/proj/ucie_rdi_to_pcie6_pipe7`.
- ✓ CI runs all UVM tops (`simple`, `burst`, `burst_ext`, `parameterized`,
  `regblock-*`), all gated on `UVM_ERROR`/`UVM_FATAL`.
- Scoreboard invariants confirmed equivalent to VCS for all tops; coverage
  collectors excluded under Verilator but scoreboard checks still enforced.
- Fix the repeated CI Verilator cache miss (speed only).
- Cosmetic Verilator warnings left un-addressed: `!item.randomize()` WIDTHTRUNC
  (`bridge_rand_stim.sv:259`, `bridge_uvm_tests_pkg.sv:350`), int-unsigned width
  notes in `bridge_rand_stim.sv`.

## Agent swarms (repo notes)
The swarm itself is the shared kit described in the block below; this repo's profile is `.claude/swarm.env`
(envs: `test-all cocotb pyuvm`; gate: `make check`; no cross-check target). The tuned UVM-on-Verilator `docker/entrypoint.sh` and
`.railway/railway.ts` are **repo-owned** (`KIT_KEEP`); the kit only added `swarm` / `agent` modes to the entrypoint.
No random regression yet: `RR_STATUS=bootstrap`, so the first Swarm B run builds it under `test/random/` (rr-bootstrap skill).

<!-- swarm-kit:begin (managed by markrthomas/dv-swarm-kit sync.sh — edit the kit, not this block) -->
## Agent swarms, run targets and tokens (swarm-kit)

This repo carries the shared **DV swarm kit** (`markrthomas/dv-swarm-kit`, version in `.claude/swarm-kit.version`).
Its repo-specific settings are **`.claude/swarm.env`** (`make swarm-profile` prints them); everything else in the
kit is identical across repos — change it in the kit and re-sync, never fork it here.

- **Swarm A** — end-to-end re-verification: `make swarm` (`docker/swarm-task.md`; swarm-manager + one
  dv-env-tester per `DV_ENVS` entry + infra-agent + dv-runner).
- **Swarm B** — random regression: `make swarm-rr` (`docker/rr-swarm-task.md`; rr-manager + rr-runner / rr-triage /
  rr-debugger / rr-test-author). With `RR_STATUS=bootstrap` it first builds `make rr-build/rr/rr-triage/rr-replay`
  (the `rr-bootstrap` skill), then flips the flag to `present`.
- **Plan-driven swarm** — write `docs/SWARM_PLAN.md` with front-matter `status: ready` and push it to `main`
  (`.github/workflows/plan-swarm.yml` runs `docker/plan-swarm-task.md`; reset to `status: draft` after it lands).
- Model provider: `SWARM_MODEL_PROVIDER=anthropic` (default) or `kimi` (`docker/provider-env.sh`; kimi sends repo
  contents to Moonshot - never for proprietary IP). One-off headless task: `docker/entrypoint.sh agent "<task>"`.
- Status board: `make board`; workers report via `python3 tools/swarm/board.py` (the `board-report` skill).
- Heavy targets (`HEAVY_TARGETS`) run one at a time: `make heavy T=<target>`. Headless Bash is limited to
  `.claude/settings.json`. `make swarm-dry` shows what a swarm run would execute; `make swarm-kit-check` checks drift.

Doctrine (all agents): verify every claim against a real artifact ("no artifact = not verified"); never weaken or skip
a checker to get green; a skip is "not run", not a pass; keep the RTL assertion-free; DUT behaviour changes are the
owner's call (write them up, don't merge them); branches `swarm/<date>-<topic>`; never push to `main`, never force-push.
Return findings as verdict + evidence (file:line / command + 3-10 line excerpt) + next step — no log dumps.

**Where it runs** (same image everywhere: the Dockerfile `tools` stage, plus the repo for `full`):
| where | how | credentials |
|---|---|---|
| GitHub Actions | Actions → **swarm** → Run workflow (task: Swarm A or B) | repo secret `CLAUDE_CODE_OAUTH_TOKEN` |
| Codespaces | open a Codespace (`.devcontainer/`), then `make swarm`, `make swarm-rr` or `make batch` | Codespaces secret `CLAUDE_CODE_OAUTH_TOKEN`; `GITHUB_TOKEN` is injected |
| Railway | batch service built from `railway.toml` (weekly cron); swarm service: start command `docker/entrypoint.sh swarm [--task docker/rr-swarm-task.md]` | service variables `CLAUDE_CODE_OAUTH_TOKEN` (swarm only) and `GITHUB_TOKEN` (fine-grained PAT: this repo, Contents read+write) |

Batch results go to the `metrics-data` branch (`runs/<UTC>-<sha>/`), never to `main`: automatically on Railway
(when `GITHUB_TOKEN` is set), elsewhere only with `PUBLISH_METRICS=1`. Tokens live only in
GitHub/Codespaces/Railway secret stores — never in the repo, the image, a log or a chat.
<!-- swarm-kit:end -->
