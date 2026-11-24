#!/usr/bin/env bash
# syn/dft/scan_readiness.sh — T4 DFT scan-readiness audit (OSS pathfinder, Yosys).
#
# Part of the tapeout-readiness program (../../DESIGN_READINESS.md). This block
# (IP-axi-to-2apbs) is the program's flow pathfinder — the first place the shared
# T4 audit is stood up before promotion to the sign-off kit.
#
# Real scan insertion + ATPG need commercial tools (DFT Compiler / TestMAX / Tessent)
# and a PDK — see syn/SIGNOFF.md and syn/dft/DFT_PLAN.md (needs-license). What runs HERE,
# no PDK, is the structural scan-readiness audit: the conditions that must hold BEFORE
# scan insertion, checked on the synthesized generic-gate netlist.
#
# HARD gates (fail => NOT scan-ready):
#   - latch-free: a transparent D-latch is not scannable (it breaks a scan chain).
#   - no combinational loops: ATPG cannot justify/propagate through a comb loop
#     (yosys `check -assert` aborts if one exists).
# REPORTED (scan-planning inputs, not pass/fail):
#   - flop inventory + reset controllability (flops with no set/reset rely on scan to
#     control their X at test time);
#   - async set/reset flop count (scan mode must hold set/reset inactive);
#   - memory/RAM count (MBIST candidates);
#   - scan-chain length estimate (= total scannable flops).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"           # syn/
TOPDIR="$(cd "$ROOT/.." && pwd)"         # repo root
RPT="$HERE/reports"; mkdir -p "$RPT"

# Same RTL/tops as the T1 synth gate (single-clock: ACLK + async ARESETn).
RTL=("src/axi4_to_apb4_2x_simple.v" "src/axi4_to_apb4_2x_burst.v" "src/axi3lite_regblock.v")
TOPS=("$@"); [ ${#TOPS[@]} -eq 0 ] && TOPS=("axi4_to_apb4_2x_simple" "axi4_to_apb4_2x_burst")
command -v yosys >/dev/null || { echo "[DFT] yosys not on PATH"; exit 127; }

rc=0
for TOP in "${TOPS[@]}"; do
  echo "[DFT] === $TOP ==="
  rd=""; for f in "${RTL[@]}"; do rd="$rd $TOPDIR/$f"; done
  log="$RPT/$TOP.dft.log"; stat="$RPT/$TOP.stat.txt"; rpt="$RPT/$TOP.scan.rpt"
  # Hard gates: elaborate + synth + latch-free + no combinational loops.
  if ! yosys -q -l "$log" -p "
      read_verilog -sv $rd
      hierarchy -check -top $TOP
      proc; opt -full
      synth -top $TOP -flatten
      select -assert-none t:\$dlatch t:\$_DLATCH_*
      check -assert
      tee -o $stat stat
  "; then
    echo "[DFT] $TOP: FAIL — latch inferred or combinational loop (see syn/dft/reports/$(basename "$log"))"
    rc=1; continue
  fi
  # Classify the synthesized flop inventory from stat (generic gate-level cell names:
  # $_DFF_P_/$_DFFE_PP_ = no set/reset; a 0/1 token = async reset; $_SDFF* = sync reset;
  # $_DFFSR* = set+reset).
  read -r tot nores async lat mem < <(awk '
    $2 ~ /^\$_DLATCH/                     {lat+=$1}
    $2 ~ /^\$_S?DFF/                      {tot+=$1;
        if ($2 ~ /^\$_DFF_[NP]_$/ || $2 ~ /^\$_DFFE_[NP][NP]_$/) nores+=$1;
        if ($2 ~ /^\$_DFFSR/ || $2 ~ /^\$_DFF_[NP][NP][01]_$/ || $2 ~ /^\$_DFFE_[NP][NP][01][NP]_$/) async+=$1 }
    $2 ~ /^\$mem/                         {mem+=$1}
    END{printf "%d %d %d %d %d\n", tot+0, nores+0, async+0, lat+0, mem+0}' "$stat") || true
  res=$(( tot - nores ))
  pct=0; [ "$tot" -gt 0 ] && pct=$(( res * 100 / tot ))
  {
    echo "# $TOP — scan-readiness report (T4, OSS structural audit)"
    echo "# generated $(date -u +%Y-%m-%dT%H:%M:%SZ) by syn/dft/scan_readiness.sh"
    echo
    echo "HARD GATES"
    echo "  latch-free (scan-chain integrity) .......... PASS (0 D-latches)"
    echo "  no combinational loops (ATPG justifiable) .. PASS (yosys check -assert)"
    echo
    echo "SCAN-PLANNING INVENTORY (synthesized generic netlist)"
    echo "  scannable flip-flops (scan-chain length) ... $tot"
    echo "    with set/reset (reset-controllable) ...... $res (${pct}%)"
    echo "    no set/reset (scan controls test X) ...... $nores"
    echo "    async set/reset (hold inactive in scan) .. $async"
    echo "  inferred latches (must be 0) ............... $lat"
    echo "  memory arrays (MBIST candidates) ........... $mem"
    echo
    echo "NOTES"
    echo "  - Single clock domain (ACLK) + async ARESETn: one scan clock; the async"
    echo "    reset is a set/reset port that scan mode must hold inactive (scan-enable"
    echo "    gated reset). No multi-clock lockup-latch strategy needed."
    echo "  - $nores flop(s) have no set/reset: acceptable (scan initializes them), but"
    echo "    they contribute uninitialized X at power-on — relevant to the reset test."
    echo "  - Full scan stitching, compression, and ATPG pattern gen are needs-license"
    echo "    (DFT Compiler / TestMAX); see syn/dft/DFT_PLAN.md. This audit is the entry gate."
  } > "$rpt"
  echo "[DFT] $TOP: scan-ready — flops=$tot reset-controllable=${pct}% async_sr=$async mem=$mem (report: syn/dft/reports/$TOP.scan.rpt)"
done
[ $rc -eq 0 ] && echo "[DFT] T4 scan-readiness audit PASSED (OSS pathfinder; scan insertion + ATPG = needs-license)."
exit $rc
