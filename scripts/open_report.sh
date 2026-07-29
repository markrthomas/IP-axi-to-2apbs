#!/usr/bin/env bash
# Open an HTML report in the platform's default browser, best-effort.
# Usage: scripts/open_report.sh <file.html>
# Prints the resolved path and never fails the build if no opener exists
# (e.g. headless CI) — it just reports where the file is.
set -u

f="${1:-}"
if [ -z "$f" ] || [ ! -f "$f" ]; then
    echo "[open] no such report: ${f:-<none>}" >&2
    exit 0
fi

# Resolve to an absolute path for the "file://" URL and the printed hint.
abs="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
echo "[open] report: $abs"

open_cmd=""
if command -v xdg-open >/dev/null 2>&1; then
    open_cmd="xdg-open"           # Linux desktop
elif command -v wslview >/dev/null 2>&1; then
    open_cmd="wslview"            # WSL (wslu)
elif command -v powershell.exe >/dev/null 2>&1; then
    open_cmd="powershell.exe -NoProfile Start-Process"  # WSL fallback
elif command -v open >/dev/null 2>&1; then
    open_cmd="open"              # macOS
fi

if [ -n "$open_cmd" ]; then
    # shellcheck disable=SC2086
    $open_cmd "$abs" >/dev/null 2>&1 &
    echo "[open] launched via ${open_cmd%% *}"
else
    echo "[open] no browser opener found; open the path above manually"
fi
exit 0
