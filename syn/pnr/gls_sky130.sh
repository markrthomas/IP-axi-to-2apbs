#!/usr/bin/env bash
# gls_sky130.sh — functional GLS of the routed sky130 netlist (T6, post-P&R).
#
#   syn/pnr/gls_sky130.sh <top> [run-tag]
#
# Simulates LibreLane's final netlist (syn/pnr/<top>/runs/<tag>/final/nl/<top>.nl.v)
# with the sky130_fd_sc_hd cell models from the ciel PDK (FUNCTIONAL, unit delay),
# running the same self-checking directed TB + AXI/APB compliance bench as the
# generic GLS (syn/gls/gls.sh). Report: syn/pnr/reports/<top>.gls.rpt.
# SDF-annotated (timing) GLS is not run here (see syn/gls/T6_PLAN.md).
set -euo pipefail
TOP="${1:?usage: gls_sky130.sh <top> [run-tag]}"
TAG="${2:-${PNR_RUN_TAG:-ci}}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PDK_ROOT="${PDK_ROOT:-$HOME/.ciel}"

NL="$ROOT/syn/pnr/$TOP/runs/$TAG/final/nl"
[ -f "$NL/$TOP.nl.v" ] || { echo "[GLS] FAIL — no routed netlist at $NL/$TOP.nl.v (run syn/pnr/run_pnr.sh first)"; exit 1; }

# The PDK LibreLane used is the one recorded in the run's resolved config, if present.
PDK_DIR=""
RES="$ROOT/syn/pnr/$TOP/runs/$TAG/resolved.json"
if [ -f "$RES" ]; then
  PDK_DIR="$(python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); print(c.get("PDK_ROOT","")+"/"+c.get("PDK","sky130A"))' "$RES" 2>/dev/null || true)"
fi
[ -d "$PDK_DIR/libs.ref/sky130_fd_sc_hd/verilog" ] || \
  PDK_DIR="$(find -L "$PDK_ROOT" -maxdepth 4 -type d -name sky130A -path '*sky130*' 2>/dev/null | head -1)"
V="$PDK_DIR/libs.ref/sky130_fd_sc_hd/verilog"
[ -f "$V/primitives.v" ] && [ -f "$V/sky130_fd_sc_hd.v" ] || {
  echo "[GLS] FAIL — sky130_fd_sc_hd Verilog models not found (looked in '$V')"; exit 1; }
echo "[GLS] sky130 cell models: $V"

GLS_NETLIST_DIR="$NL" \
GLS_CELL_MODELS="$V/primitives.v $V/sky130_fd_sc_hd.v" \
GLS_DEFINES="-DFUNCTIONAL -DUNIT_DELAY=#1" \
GLS_LABEL="sky130_fd_sc_hd routed netlist (LibreLane final/nl, functional, unit delay)" \
GLS_OUT="$ROOT/syn/pnr/reports" \
  bash "$ROOT/syn/gls/gls.sh" "$TOP"
