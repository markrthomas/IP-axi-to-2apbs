#!/usr/bin/env bash
# syn/synth.sh — T1 synthesizability gate (OSS pathfinder, Yosys).
#
# Part of the tapeout-readiness program (../DESIGN_READINESS.md in the workspace).
# This block (IP-axi-to-2apbs) is the program's *flow pathfinder*: the first place
# the shared syn/ gate is stood up before it is promoted to the shared sign-off kit.
#
# What this proves HERE (real artifact, no PDK needed):
#   - every bridge top elaborates and synthesizes to a generic gate netlist;
#   - the design is LATCH-FREE (yosys `select -assert-none` aborts if any D-latch
#     is inferred — the gate fails);
#   - a cell/flop inventory is emitted to syn/reports/.
# What this does NOT do (needs a PDK / liberty + OpenSTA/OpenROAD — see SIGNOFF.md):
#   - map to a real standard-cell library, timing (STA), area/power, or P&R/GDS.
#
# Usage:  syn/synth.sh [TOP ...]   (default: both bridge variants)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
RPT="$HERE/reports"
mkdir -p "$RPT"

# IP deliverable tops (the two bridge variants). The regblock is an example slave
# and is read only to satisfy hierarchy; it is not a synth top here.
RTL=("src/axi4_to_apb4_2x_simple.v" "src/axi4_to_apb4_2x_burst.v" "src/axi3lite_regblock.v")
TOPS=("$@")
[ ${#TOPS[@]} -eq 0 ] && TOPS=("axi4_to_apb4_2x_simple" "axi4_to_apb4_2x_burst")

command -v yosys >/dev/null || { echo "[SYN] yosys not on PATH"; exit 127; }

rc=0
for TOP in "${TOPS[@]}"; do
  echo "[SYN] === $TOP ==="
  rd=""; for f in "${RTL[@]}"; do rd="$rd $ROOT/$f"; done
  if yosys -q -l "$RPT/$TOP.synth.log" -p "
      read_verilog -sv $rd
      hierarchy -check -top $TOP
      proc; opt -full
      select -assert-none t:\$dlatch t:\$_DLATCH_*
      synth -top $TOP -flatten
      tee -o $RPT/$TOP.stat.txt stat
  "; then
    dff=$( (grep -oE '[0-9]+ +\$_DFF[A-Z0-9_]*' "$RPT/$TOP.stat.txt" || true) | awk '{s+=$1} END{print s+0}')
    echo "[SYN] $TOP: PASS — latch-free, flops=$dff (report: syn/reports/$TOP.stat.txt)"
  else
    echo "[SYN] $TOP: FAIL — see syn/reports/$TOP.synth.log (latch inferred or elaboration error)"
    rc=1
  fi
done
[ $rc -eq 0 ] && echo "[SYN] T1 synthesizability gate PASSED (OSS pathfinder)."
exit $rc
