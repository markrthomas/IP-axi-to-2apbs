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
  "BUILD_JOBS=${BUILD_JOBS:-2}"
)

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
  run_make -C uvm/vlt ci "${MAKE_ARGS[@]}"
elif [ "$1" = "make" ]; then
  shift
  run_make -C uvm/vlt "$@" "${MAKE_ARGS[@]}"
else
  exec "$@"
fi
