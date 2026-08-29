#!/usr/bin/env bash
# Entrypoint for the IP-axi-to-2apbs UVM-on-Verilator image.
#
# The image bundles UVM-capable Verilator 5.050 (built from source) and the
# Accellera UVM library.  This wrapper appends the flow's toolchain overrides to
# every `make` call so the bundled tools are always used, and (on Railway) trims
# the very chatty --binary build log down to the signal lines so it stays under
# the cloud's log-ingestion rate limit.
#
#   (no args)        -> make -C uvm/vlt ci        <overrides>   (full UVM gate)
#   make <targets>   -> make -C uvm/vlt <targets> <overrides>
#   <anything else>  -> exec verbatim (shell, verilator --version, ...)
set -euo pipefail

# A stale VERILATOR_ROOT hard-errors the launcher; the uvm/vlt flow doesn't need
# it (verilator derives its root from its own path).  Drop it defensively.
unset VERILATOR_ROOT || true

MAKE_ARGS=(
  "VERILATOR=${VERILATOR:-/opt/verilator/bin/verilator}"
  "UVM_HOME=${UVM_HOME:-/opt/verilator/uvm}"
  "BUILD_JOBS=${BUILD_JOBS:-1}"
)

# --- resource preflight: fail fast before the RAM-heavy --binary build --------
# The UVM precompiled-header compile (all of UVM in one g++ TU) needs several GB;
# a too-small instance only OOM-kills cc1plus after minutes of building.  Read the
# container's cgroup memory limit up front and abort in seconds with actionable
# guidance instead of burning a full build.  Empirically: 1 GB can't build it at
# all, ~5.7 GB OOMs, a 7 GB CI runner / 8 GB Railway Hobby clears it — so the
# floor is 6144 MB.  Override the floor with UVM_MIN_MEM_MB; bypass entirely with
# UVM_SKIP_RESCHECK=1.  Only the heavy (--binary) targets are gated — lint/clean,
# which need ~330 MB, are not.
container_mem_mb() {
  local lim=""
  if [ -r /sys/fs/cgroup/memory.max ]; then                 # cgroup v2
    lim="$(cat /sys/fs/cgroup/memory.max 2>/dev/null)"
  elif [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then  # cgroup v1
    lim="$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null)"
  fi
  # "max" (v2) or an enormous sentinel (v1 unlimited) -> no cap; use host MemTotal.
  if [ -z "${lim}" ] || [ "${lim}" = "max" ] || { [ "${lim}" -gt 1000000000000 ] 2>/dev/null; }; then
    awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null
  else
    echo "$(( lim / 1024 / 1024 ))"
  fi
}

preflight_resources() {
  [ -n "${UVM_SKIP_RESCHECK:-}" ] && return 0
  local min_mb="${UVM_MIN_MEM_MB:-6144}"
  local mem_mb cpus
  mem_mb="$(container_mem_mb)"
  cpus="$(nproc 2>/dev/null || echo '?')"
  echo "[preflight] container memory: ${mem_mb:-?} MB (floor ${min_mb} MB) | vCPUs: ${cpus} | BUILD_JOBS=${BUILD_JOBS:-1}"
  if [ -n "${mem_mb}" ] && [ "${mem_mb}" -lt "${min_mb}" ] 2>/dev/null; then
    echo "[preflight] ERROR: ${mem_mb} MB is below the ${min_mb} MB floor for the UVM --binary build;" >&2
    echo "[preflight]   the UVM precompiled-header compile OOM-kills cc1plus below this." >&2
    echo "[preflight]   Fix: raise instance memory (Railway: service Settings -> Resource Limits, ~8 GB)." >&2
    echo "[preflight]   ~4 GB box? export CFLAGS_MODEL='-O0 --param ggc-min-expand=1 --param ggc-min-heapsize=32768'," >&2
    echo "[preflight]   lower the floor via UVM_MIN_MEM_MB, or bypass the check with UVM_SKIP_RESCHECK=1." >&2
    exit 3
  fi
}

# Heavy iff any make goal is not a cheap (lint/clean) target.  Args are the make
# goals only (no -C/dir, no VAR=val overrides).
goals_need_ram() {
  local g
  for g in "$@"; do
    case "${g}" in
      lint|lint-*|clean) ;;   # elaborate-only / rm: ~330 MB, no --binary build
      *) return 0 ;;          # anything else builds C++ -> needs the RAM floor
    esac
  done
  return 1
}

# --- log-volume control for rate-limited cloud log sinks ---------------------
# `make -C uvm/vlt ci` is very chatty: the --binary build echoes a ~500-char g++
# command PER generated file (~2.6k files per top, across every UVM top).  Railway
# rate-limits log INGESTION, so an unfiltered gate maxes the limit and buries the
# useful banners.  On Railway (auto-detected) forward only the SIGNAL — UVM report
# lines, [BRACKET] banners, errors/warnings, PASS/FAIL, $finish, make's failure
# line — to the stream, while the FULL transcript is tee'd to a file and, on
# failure, tail-dumped so a red run is still debuggable.  Everywhere else (local
# `docker run`, CI) the gate streams verbatim.  Override with UVM_CI_QUIET=1/0.
# The exit status is always make's (via PIPESTATUS), never grep's.
if [ -n "${UVM_CI_QUIET:-}" ]; then
  _quiet="${UVM_CI_QUIET}"
elif [ -n "${RAILWAY_SERVICE_ID:-}${RAILWAY_PROJECT_ID:-}${RAILWAY_ENVIRONMENT:-}" ]; then
  _quiet=1
else
  _quiet=0
fi

_LOG="${UVM_CI_LOG:-/tmp/uvm-ci-full.log}"
# Signal lines: UVM_* report lines, [BRACKET] banners (e.g. [RNTST]), Verilator
# %Error/%Warning, generic error/warning, PASS/FAIL, $finish, and make's *** line.
_SIGNAL_RE='(UVM_(INFO|WARNING|ERROR|FATAL))|(\[[A-Z][A-Z0-9_ -]+\])|(%Error)|(%Warning)|([Ee]rror)|([Ww]arning)|(PASS)|(FAIL)|(\$finish)|(make(\[[0-9]+\])?: \*\*\*)'

run_make() {
  if [ "${_quiet}" != "1" ]; then
    exec make "$@"          # verbatim, unchanged behavior (local / CI)
  fi
  set +e
  make "$@" 2>&1 | tee "${_LOG}" | grep --line-buffered -E "${_SIGNAL_RE}"
  local rc=${PIPESTATUS[0]}
  set -e
  if [ "${rc}" -ne 0 ]; then
    echo "=== UVM gate FAILED (rc=${rc}) — last 200 lines of full transcript ==="
    tail -n 200 "${_LOG}" 2>/dev/null || true
  fi
  exit "${rc}"
}

if [ "$#" -eq 0 ]; then
  preflight_resources                       # default `ci` always builds --binary
  run_make -C uvm/vlt ci "${MAKE_ARGS[@]}"
elif [ "$1" = "make" ]; then
  shift
  if goals_need_ram "$@"; then preflight_resources; fi
  run_make -C uvm/vlt "$@" "${MAKE_ARGS[@]}"
else
  exec "$@"
fi
