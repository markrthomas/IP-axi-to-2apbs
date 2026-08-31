#!/usr/bin/env bash
# Offline tests for the Docker/Railway plumbing — no Docker build, no network:
#   - bash -n syntax on the shell scripts
#   - shellcheck (error severity) when available
#   - railway-watch.sh --self-test (PASS/FAIL classifier fixtures)
#   - entrypoint.sh dispatch + resource-preflight behaviour (with a mocked `make`)
#   - `make -n railway-run` sanity
# Run locally with `make check-docker`; also run in CI (.github/workflows/
# docker-plumbing.yml).  Exits non-zero if any check fails.
set -uo pipefail
cd "$(dirname "$0")/.."                 # repo root
ROOT="$PWD"
EP="$ROOT/docker/entrypoint.sh"
WATCH="$ROOT/docker/railway-watch.sh"
rc=0
note() { printf '\n== %s ==\n' "$1"; }
fail() { echo "FAIL: $1"; rc=1; }

note "bash -n (syntax)"
bash -n "$EP"    && echo "ok  entrypoint.sh"    || fail "entrypoint.sh syntax"
bash -n "$WATCH" && echo "ok  railway-watch.sh" || fail "railway-watch.sh syntax"

note "shellcheck (error severity; skipped if not installed)"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S error "$EP" "$WATCH" && echo "ok  shellcheck" || fail "shellcheck errors"
else
  echo "shellcheck not installed — skipping"
fi

note "railway-watch.sh --self-test (classifier fixtures)"
bash "$WATCH" --self-test || fail "railway-watch self-test"

note "entrypoint dispatch + preflight (mocked make)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
printf '#!/usr/bin/env bash\ntouch "%s/make.ran"\necho "[mock make] $*"\nexit 0\n' "$TMP" > "$TMP/make"
chmod +x "$TMP/make"

# ep_case <name> <expected_rc> <expected_make: yes|no> <env-and-command...>
ep_case() {
  local name="$1" exp_rc="$2" exp_make="$3"; shift 3
  rm -f "$TMP/make.ran"
  PATH="$TMP:$PATH" "$@" >/dev/null 2>&1
  local got=$? ran=no
  [ -f "$TMP/make.ran" ] && ran=yes
  if [ "$got" = "$exp_rc" ] && [ "$ran" = "$exp_make" ]; then
    printf 'ok   %-22s rc=%s make-ran=%s\n' "$name" "$got" "$ran"
  else
    printf 'FAIL %-22s rc=%s(want %s) make-ran=%s(want %s)\n' "$name" "$got" "$exp_rc" "$ran" "$exp_make"
    rc=1
  fi
}
#        name             rc  make  command
ep_case heavy-under-floor 3   no   env UVM_MIN_MEM_MB=99999999 bash "$EP" make simple
ep_case heavy-bypass      0   yes  env UVM_SKIP_RESCHECK=1     bash "$EP" make simple
ep_case cheap-lint        0   yes  env UVM_MIN_MEM_MB=99999999 bash "$EP" make lint
ep_case noargs-ci         3   no   env UVM_MIN_MEM_MB=99999999 bash "$EP"
ep_case heavy-ok          0   yes  env UVM_MIN_MEM_MB=1        bash "$EP" make simple
ep_case passthrough       0   no   env UVM_MIN_MEM_MB=99999999 bash "$EP" true

note "make -n railway-run (target parses)"
make -n railway-run >/dev/null 2>&1 && echo "ok  railway-run" || fail "make -n railway-run"

note "result"
if [ "$rc" = 0 ]; then echo "ALL PLUMBING CHECKS PASSED"; else echo "PLUMBING CHECKS FAILED"; fi
exit "$rc"
