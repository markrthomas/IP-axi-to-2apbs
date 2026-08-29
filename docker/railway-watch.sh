#!/usr/bin/env bash
# Watch a Railway deployment to completion, then exit with its result — so
# `make railway-run` returns to a prompt on its own instead of tailing logs
# forever (which never ends for a batch job and needs a manual Ctrl-C).
#
# Source of truth is the batch container's own exit line in the logs
# ("[exited with code N]"): N==0 -> PASS (exit 0), else FAIL (exit 1).  Build
# failures and the entrypoint's resource-preflight abort are caught too, with the
# service status as a backstop.  Ctrl-C only stops watching; the cloud run keeps
# going.
#
# Env knobs: RAILWAY (CLI name, default "railway"), RAILWAY_POLL (seconds between
# polls, default 20), RAILWAY_WATCH_TIMEOUT (max seconds to wait, default 3600).
#
# `docker/railway-watch.sh --self-test` runs the classifier against canned
# fixtures and needs no Railway/network — used by CI and local sanity checks.
set -u

RAILWAY="${RAILWAY:-railway}"
POLL="${RAILWAY_POLL:-20}"
TIMEOUT_S="${RAILWAY_WATCH_TIMEOUT:-3600}"
NOISE='Config as Code|Migrate:|Existing files keep working'

# classify "<logs>" "<status-line>" -> prints "VERDICT|reason"
# VERDICT is PASS, FAIL, or RUNNING.  Pure function: no I/O, easy to test.
classify() {
  logs="$1"; st="$2"

  # While the image is still building, runtime logs are empty or stale — don't
  # let a previous deployment's exit line trigger a false verdict.
  case "$st" in *Building*) echo "RUNNING|building image"; return;; esac

  code="$(printf '%s\n' "$logs" | grep -oE '\[exited with code [0-9]+\]' | tail -1 | grep -oE '[0-9]+')"
  if [ -n "$code" ]; then
    if [ "$code" = "0" ]; then echo "PASS|container exited 0"; else echo "FAIL|container exited $code"; fi
    return
  fi
  if printf '%s' "$logs" | grep -qE 'preflight\] ERROR'; then
    echo "FAIL|resource preflight aborted the run (instance too small)"; return
  fi
  if printf '%s' "$logs" | grep -qE 'UVM gate FAILED|Killed signal terminated program cc1plus'; then
    echo "FAIL|build/gate failure in logs"; return
  fi
  case "$st" in
    *Crashed*|*Failed*) echo "FAIL|deployment status:${st}"; return;;
    *Completed*)
      if printf '%s' "$logs" | grep -qE 'PASS: tb_uvm'; then echo "PASS|completed, gate PASS"
      else echo "PASS|completed (no gate line captured; treating exit as success)"; fi
      return;;
  esac
  echo "RUNNING|${st:-status unknown}"
}

self_test() {
  fail=0
  check() { # <name> <expected-verdict> <logs> <status>
    got="$(classify "$3" "$4")"; gv="${got%%|*}"
    if [ "$gv" = "$2" ]; then printf 'ok   %-22s -> %s\n' "$1" "$got"
    else printf 'FAIL %-22s -> %s (wanted %s)\n' "$1" "$got" "$2"; fail=1; fi
  }
  check green-exit0     PASS    "PASS: tb_uvm_regblock
[exited with code 0]"                                   "status: ● Completed"
  check gate-fail       FAIL    "FAIL: tb_uvm_simple reported UVM_ERROR
[exited with code 1]"                                   "status: ● Completed"
  check oom             FAIL    "g++: fatal error: Killed signal terminated program cc1plus
=== UVM gate FAILED (rc=2) ==="                         "status: ● Completed"
  check preflight       FAIL    "[preflight] ERROR: 1024 MB is below the 6144 MB floor" "status: ● Completed"
  check building-stale  RUNNING PASS:\ tb_uvm_regblock$'\n'"[exited with code 0]"        "status: ● Online · Building (4s)"
  check running-online  RUNNING "UVM_INFO ... running"                                   "status: ● Online"
  check build-failed    FAIL    ""                                                       "status: ● Failed"
  check completed-nolog PASS    "some truncated output"                                  "status: ● Completed"
  [ "$fail" = 0 ] && echo "ALL PASS" || echo "SELF-TEST FAILURES"
  return "$fail"
}

if [ "${1:-}" = "--self-test" ]; then self_test; exit $?; fi

echo "[watch] following the deployment to completion (poll ${POLL}s, timeout ${TIMEOUT_S}s)."
echo "[watch] Ctrl-C is safe — it only stops watching; the cloud run keeps going."
end=$(( $(date +%s) + TIMEOUT_S ))
last=""
while :; do
  logs="$(timeout 25 "$RAILWAY" logs 2>&1 | grep -vE "$NOISE")"
  st="$(timeout 20 "$RAILWAY" status 2>&1 | awk '/Linked service/{f=1} f&&/status:/{sub(/^[[:space:]]*/,"");print;exit}')"
  res="$(classify "$logs" "$st")"; verdict="${res%%|*}"; reason="${res#*|}"
  if [ "$verdict" != RUNNING ]; then
    echo
    echo "======================================================================"
    echo "  Railway run: ${verdict}  (${reason})"
    echo "======================================================================"
    printf '%s\n' "$logs" | grep -E 'PASS:|FAIL:|UVM_(ERROR|FATAL) :|Scoreboard (PASSED|FAILED)|preflight\]|Killed|UVM gate FAILED|\[exited with code' | tail -30
    [ "$verdict" = PASS ] && exit 0 || exit 1
  fi
  # show newest progress line so the wait isn't opaque
  prog="$(printf '%s\n' "$logs" | grep -E 'PASS:|FAIL:|Verilating|%Error|Compiling|make(\[[0-9]+\])?: \*\*\*' | tail -1 | cut -c1-100)"
  [ -n "$prog" ] && [ "$prog" != "$last" ] && { echo "[watch] $prog"; last="$prog"; }
  echo "[watch] $reason — next check in ${POLL}s"
  now=$(date +%s); [ "$now" -ge "$end" ] && { echo "[watch] TIMEOUT after ${TIMEOUT_S}s (last status: ${st:-?}). Cloud run may still be going; check the dashboard."; exit 2; }
  sleep "$POLL"
done
