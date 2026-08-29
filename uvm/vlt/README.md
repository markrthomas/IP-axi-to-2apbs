# UVM on open-source Verilator (`uvm/vlt`)

Runs the **same** SystemVerilog UVM environment as the VCS/Xcelium flows
(`../sv`, `../tb`) under **open-source Verilator 5.050** — the first Verilator
that can elaborate and run UVM — using the Accellera UVM 2020.3.1 library
bundled in the Verilator source tree (`test_regress/t/uvm`, mirror:
`chipsalliance/uvm-verilator`). This gives a license-free correctness/CI path
alongside the commercial simulators.

Status: **green in CI** — all tops (`tb_uvm_simple`, `tb_uvm_burst`,
`tb_uvm_burst_ext`, `tb_uvm_parameterized`, and all four `tb_uvm_regblock`
tests) build with `--binary` and run scoreboard-clean, 0 UVM_ERROR/UVM_FATAL.
See `doc/PLAN.md` near-term item 0.

## Toolchain requirements

- **Verilator ≥ 5.050, UVM-capable.** The OSS CAD Suite's bundled Verilator
  does **not** run UVM — use a standalone build. Local reference install:
  `~/verilator/bin/verilator` (Verilator 5.050).
- **`VERILATOR_ROOT` must be UNSET.** Sourcing the OSS CAD Suite
  (`~/oss-cad-suite/environment`) exports a stale `VERILATOR_ROOT` pointing at
  *its* Verilator, which makes `~/verilator/bin/verilator` hard-error
  (`VERILATOR_ROOT is set to inconsistent path`). `unset VERILATOR_ROOT` after
  sourcing that env.
- **`UVM_HOME`** = the directory holding `uvm_pkg_all_v2020_3_1_dpi.svh` and
  `v2020_3_1/dpi/uvm_dpi.cc`. For the local install that is
  `~/verilator/test_regress/t/uvm`.

## Usage

```sh
# From the repo root. VERILATOR/UVM_HOME override the Makefile defaults.
V=~/verilator/bin/verilator
U=~/verilator/test_regress/t/uvm

# RAM-safe elaborate-only smoke check (~330 MB, seconds) — do this first.
( unset VERILATOR_ROOT; make -C uvm/vlt lint VERILATOR=$V UVM_HOME=$U )

# Full build + run of one top (see targets below).
( unset VERILATOR_ROOT; make -C uvm/vlt simple VERILATOR=$V UVM_HOME=$U )
```

Targets: `lint` / `lint-<top>` (elaborate only); `simple`, `burst`,
`burst_ext`, `parameterized`, and the `regblock-*` tests (build + run);
`all` = simple+burst+burst_ext+parameterized; `clean`.

`BUILD_JOBS` (default `1`) sets both `-j` and `--build-jobs`; the C++ side is
built at `-O0`. Both defaults keep the (large) UVM C++ compile within a modest
RAM budget.

## The RAM ceiling — build the `--binary` step in CI, not on an 8 GB host

`--lint-only` is cheap (~330 MB). The full `--binary` build generates ~2.6k C++
files, and `g++` compiling them is the memory-heavy step. On a RAM-constrained
host (e.g. an ~8 GB WSL2 box, which only exposes ~5.7 GB) it **OOMs and can take
down the whole session/VM**. Options:

- **Preferred:** run the full build in CI — see
  `.github/workflows/verilator-sim.yml`, which builds UVM-capable Verilator
  5.050 from source on a GitHub runner and runs `make -C uvm/vlt lint` +
  `simple`. On the runner the `--binary` build peaks ~340 MB / ~76 s.
- **Locally on a small box:** `make ... simple BUILD_JOBS=1` under swap, guarded
  by `ulimit -v` in a subshell so a blowup dies alone instead of killing the VM.
  Lint locally, build heavy in the cloud.

## Files

- `Makefile` — the flow (build/run/lint targets).
- `uvm_macros.svh` — **required, tracked.** An intentionally empty include-shim
  that satisfies the sources' `` `include "uvm_macros.svh" ``; the monolithic
  UVM header (listed first on the command line) already defines every `` `uvm_* ``
  macro. It lives only on this flow's `+incdir`. **Do not delete** — without it a
  fresh checkout fails lint with cascading parse errors (the VCS/Xcelium flows
  use the real header from `UVM_HOME` and never see this file).
- `obj/` — build output (gitignored).

## Docker / Railway — run the heavy build off-box

The `--binary` build OOMs an ~8 GB host (see above). Besides GitHub Actions, the
repo-root **`Dockerfile`** packages the whole flow — it builds UVM-capable
Verilator 5.050 from source, bundles the UVM library at `UVM_HOME`, and its
entrypoint (`docker/entrypoint.sh`) runs `make -C uvm/vlt ci` (lint + every top,
scoreboard/`UVM_ERROR` gated). Run it on any RAM-generous container host;
[Railway](https://railway.com) is wired up via the repo-root `railway.toml`.
(This mirrors the sibling `axi-on-ucie-to-mem` image, except that flow pins
oss-cad-suite's Verilator — here we must build 5.050 from source because the
oss-cad-suite Verilator is not UVM-capable.)

```sh
# Local container run (needs a host with enough RAM for the --binary build):
make docker-uvm-build          # build the image (root Dockerfile)
make docker-uvm-run            # build + run the full UVM gate in the container
#   DOCKER=podman  UVM_IMAGE=name:tag   # override the CLI / image tag

# One top only (entrypoint injects VERILATOR/UVM_HOME/BUILD_JOBS):
docker run --rm ip-axi-2apbs-uvm:latest make simple

# Railway (one-shot job; restartPolicy NEVER in railway.toml):
railway login && railway link   # once, to select the project/service
make railway-deploy             # railway up — builds the Dockerfile in the cloud
make railway-logs               # tail the run
```

Container/cloud specifics baked into the image + entrypoint:

- **`VERILATOR_ROOT` unset** — the launcher derives its root from the bundled
  install; the entrypoint drops any stale value defensively (a stale one
  hard-errors the launcher — see above).
- **`BUILD_JOBS=2` default** — cloud builders advertise many cores but little
  RAM, so the `--binary` compile at `-j $(nproc)` OOM-kills `g++`. Override with
  `-e BUILD_JOBS=N`.
- **Railway log filter** — the build echoes a ~500-char `g++` line per generated
  file (thousands of files); Railway rate-limits log ingestion, so on Railway
  (auto-detected) the entrypoint forwards only signal lines (UVM report lines,
  banners, errors, PASS/FAIL) and tail-dumps the full transcript on failure.
  Override with `-e UVM_CI_QUIET=1/0`.
- **`z3`** is installed for run-time constraint solving; a **UTF-8 locale** is
  forced so non-ASCII report output does not crash on a C/POSIX log sink.

## Verilator-specific divergences in the shared env

The shared UVM sources carry `` `ifndef VERILATOR `` guards where behavior must
differ from VCS. Three to be aware of when reasoning about parity:

- **`bridge_axi_monitor`** decouples channel collection — Verilator's `--timing`
  scheduler resolves cross-channel blocking differently than VCS.
- **`bridge_cov_collector`** (the covergroup-based collector) is **excluded**
  under Verilator; VCS/Xcelium still build it. So the Verilator run does not
  collect functional coverage — it validates the scoreboard invariants only.
- **`regblock_cov_collector`** (covergroup-based, in `regblock_uvm_env_pkg.sv`)
  is likewise excluded under Verilator. The `regblock_env` scoreboard invariants
  (shadow-memory read-back checks, SLVERR-path detection) are still verified.
