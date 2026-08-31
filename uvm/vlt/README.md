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
scoreboard/`UVM_ERROR` gated). Run it on a RAM-generous container host (**~8 GB**
— see the RAM floor below); [Railway](https://railway.com) (Hobby plan) is wired
up via the repo-root `.railway/railway.ts` (Railway Infrastructure as Code;
validate/apply with `npm install railway && railway config plan`).
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

# Railway (one-shot job; restartPolicy NEVER in .railway/railway.ts):
make railway-run                # END TO END: login/link (first run) + up, then wait
#   and return to your prompt with a PASS/FAIL banner (no manual Ctrl-C).  Exits
#   non-zero on a red gate.  Raise the service memory limit to ~8 GB first
#   (dashboard) — see RAM floor below.  (Watcher: docker/railway-watch.sh.)
# Or the granular steps:
railway login && railway link   # once, to select the project/service
make railway-deploy             # railway up — builds the Dockerfile in the cloud
make railway-logs               # tail the run
```

Container/cloud specifics baked into the image + entrypoint:

- **`VERILATOR_ROOT` unset** — the launcher derives its root from the bundled
  install; the entrypoint drops any stale value defensively (a stale one
  hard-errors the launcher — see above).
- **RAM floor: ~8 GB.** The UVM precompiled-header compile (all of UVM in one
  g++ TU) needs several GB. A **1 GB instance cannot build it at all** (cc1plus
  is OOM-killed even at `-j1`); a Railway **Hobby** instance (up to 8 GB) clears
  it, matching the 7 GB GitHub runner. On Railway, raise the service memory limit
  (Settings → Resource Limits) before deploying.
- **Fail-fast preflight.** Before any `--binary` build, the entrypoint reads the
  container's cgroup memory limit and aborts in seconds (exit 3) if it is below
  the floor — so a too-small instance fails immediately with actionable guidance
  instead of OOM-killing cc1plus after ~10 minutes. Floor is 6144 MB; override
  with `-e UVM_MIN_MEM_MB=N`, or skip the check with `-e UVM_SKIP_RESCHECK=1`.
  Cheap `lint`/`clean` targets (~330 MB) are not gated.
- **`BUILD_JOBS=1` default** — each PCH compile needs several GB, so two at once
  OOM even an 8 GB box; serialize to one. Raise with `-e BUILD_JOBS=N` only where
  RAM is ample. (Two *separate* pools OOM independently: the Docker *builder*
  during the Verilator-from-source compile — bounded by the `VL_BUILD_JOBS` build
  arg, default 2 — and the *runtime* instance during the `--binary` build —
  bounded by `BUILD_JOBS`.)
- **`CFLAGS_MODEL` knob** — on a RAM-tight box (e.g. trying 4 GB instead of 8),
  `-e CFLAGS_MODEL='-O0 --param ggc-min-expand=1 --param ggc-min-heapsize=32768'`
  forces GCC to garbage-collect aggressively, cutting cc1plus peak RSS ~30–50% at
  the cost of compile time.
- **Railway log filter** — the build echoes a ~500-char `g++` line per generated
  file (thousands of files); Railway rate-limits log ingestion, so on Railway
  (auto-detected) the entrypoint forwards only signal lines (UVM report lines,
  banners, errors, PASS/FAIL) and tail-dumps the full transcript on failure.
  Override with `-e UVM_CI_QUIET=1/0`.
- **`z3`** is installed for run-time constraint solving; a **UTF-8 locale** is
  forced so non-ASCII report output does not crash on a C/POSIX log sink.

**CI coverage of this plumbing.** `.github/workflows/docker-plumbing.yml` runs on
every push/PR (seconds, no Docker build): `make check-docker`
(`docker/plumbing-test.sh`) — shell syntax + shellcheck, the `railway-watch.sh`
PASS/FAIL classifier self-test, and the entrypoint dispatch/preflight logic
against a mocked `make`. `.github/workflows/docker-image.yml` (path-gated to
`Dockerfile`/`docker/**`, or manual) actually builds the image and exercises the
entrypoint end-to-end (passthrough, preflight-abort exit 3, `make lint`). The UVM
*simulation* correctness is covered separately by `verilator-sim.yml`, which runs
the same tops directly on the runner.

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
