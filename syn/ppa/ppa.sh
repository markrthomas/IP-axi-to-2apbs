#!/usr/bin/env bash
# syn/ppa/ppa.sh — T6 PPA (power/performance/area) proxy baseline (OSS, Yosys).
#
# Part of the tapeout-readiness program (../../DESIGN_READINESS.md). Real PPA needs a
# PDK: a standard-cell library (area/power per cell), Liberty timing, and a place&route
# flow. Those are needs-pdk (see PPA_PLAN.md for the authored OpenROAD/sky130 + OpenSTA
# recipe). What runs HERE, no PDK, is a technology-independent PROXY baseline that is a
# real, tracked artifact and moves monotonically with the real numbers:
#   - AREA proxy  = generic cell count + flop count (post-synth, flattened).
#   - TIMING proxy= longest topological logic path (`ltp`), i.e. combinational depth.
#   - POWER proxy = flop count (switching surface) — informational.
# These are the same kind of ceilings the T1 gate already calibrates; this consolidates
# them into a per-top PPA table for tracking across revisions.
#
# Usage:  syn/ppa/ppa.sh [TOP ...]   (default: both bridge variants)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT="$HERE/reports"
mkdir -p "$OUT"
cd "$ROOT"

RTL=(src/axi4_to_apb4_2x_simple.v src/axi4_to_apb4_2x_burst.v src/axi3lite_regblock.v)
TOPS=("$@")
[ ${#TOPS[@]} -eq 0 ] && TOPS=(axi4_to_apb4_2x_simple axi4_to_apb4_2x_burst)

command -v yosys >/dev/null || { echo "[PPA] yosys not on PATH — skipping"; exit 0; }

rc=0
for TOP in "${TOPS[@]}"; do
  echo "[PPA] === $TOP ==="
  log="$OUT/$TOP.ppa.log"; rpt="$OUT/$TOP.ppa.rpt"
  rd=""; for f in "${RTL[@]}"; do rd="$rd $ROOT/$f"; done
  if ! yosys -q -l "$log" -p "
      read_verilog -sv $rd
      hierarchy -check -top $TOP
      proc
      synth -top $TOP -flatten
      tee -o $OUT/$TOP.ppa.stat.txt stat
      tee -o $OUT/$TOP.ppa.ltp.txt ltp
  "; then
    echo "[PPA] $TOP: FAIL — synthesis error (see $log)"; rc=1; continue
  fi
  cells=$( (grep -oE '[0-9]+ +cells' "$OUT/$TOP.ppa.stat.txt" || true) | tail -1 | grep -oE '[0-9]+' || echo "?")
  flops=$( (grep -oE '[0-9]+ +\$_(S?DFF|DLATCH)[A-Z0-9_]*' "$OUT/$TOP.ppa.stat.txt" || true) | awk '{s+=$1} END{print s+0}')
  depth=$( (grep -oiE 'length=[0-9]+' "$OUT/$TOP.ppa.ltp.txt" || true) | tail -1 | grep -oE '[0-9]+' || echo "?")
  {
    echo "# $TOP — PPA proxy baseline (T6, OSS technology-independent)"
    echo "# generated $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "  AREA proxy   — generic cells ........ ${cells}"
    echo "  AREA proxy   — flip-flops ........... ${flops}"
    echo "  TIMING proxy — logic depth (ltp) .... ${depth}"
    echo "  real PPA (ns / mW / um^2) ........... needs-pdk (see PPA_PLAN.md)"
  } > "$rpt"
  echo "[PPA] $TOP: cells=${cells} flops=${flops} logic-depth=${depth} (report: syn/ppa/reports/$TOP.ppa.rpt)"
done
[ $rc -eq 0 ] && echo "[PPA] T6 PPA proxy baseline emitted (OSS; real node PPA = needs-pdk)."
exit $rc
