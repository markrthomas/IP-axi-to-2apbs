#!/usr/bin/env bash
# syn/gls/gls.sh — T6 gate-level simulation (OSS pathfinder, Yosys + Icarus).
#
# Part of the tapeout-readiness program (../../DESIGN_READINESS.md). This block
# (IP-axi-to-2apbs) is the program's *flow pathfinder*: the first place the shared
# T6 gate is stood up before promotion to the shared sign-off kit.
#
# What this proves HERE (real artifact, no PDK needed):
#   - each bridge top SYNTHESIZES to a generic gate netlist (Yosys), and
#   - that netlist SIMULATES CORRECTLY: the block's own self-checking directed
#     testbench passes when driven against the gate-level netlist (Yosys generic
#     cells modelled by the shipped simcells.v / simlib.v), not the RTL.
# This is zero-delay (functional) GLS — it catches synth/sim mismatch, lost
# initialization, and X-propagation that pure RTL sim and formal LEC can miss.
#
# What this does NOT do (needs a PDK / liberty + a vendor flow — see SIGNOFF.md):
#   - SDF back-annotated (timing) GLS, or mapping to a real standard-cell library.
#   Those are needs-pdk and are authored as a recipe in T6_PLAN.md.
#
# Usage:  syn/gls/gls.sh [TOP ...]   (default: both bridge variants)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT="$HERE/reports"
BUILD="$HERE/build"
mkdir -p "$OUT" "$BUILD"
cd "$ROOT"

# All RTL read for every top (regblock is an example slave, read to satisfy hierarchy).
RTL=(src/axi4_to_apb4_2x_simple.v src/axi4_to_apb4_2x_burst.v src/axi3lite_regblock.v)
# Per-top self-checking directed testbench.
declare -A TB=(
  [axi4_to_apb4_2x_simple]=test/tb_axi4_to_apb4_2x_simple.v
  [axi4_to_apb4_2x_burst]=test/tb_axi4_to_apb4_2x_burst.v
)
TOPS=("$@")
[ ${#TOPS[@]} -eq 0 ] && TOPS=(axi4_to_apb4_2x_simple axi4_to_apb4_2x_burst)

command -v yosys   >/dev/null || { echo "[GLS] yosys not on PATH — skipping (needs OSS CAD Suite)";   exit 0; }
command -v iverilog>/dev/null || { echo "[GLS] iverilog not on PATH — skipping (needs OSS CAD Suite)"; exit 0; }
command -v vvp     >/dev/null || { echo "[GLS] vvp not on PATH — skipping (needs OSS CAD Suite)";      exit 0; }
DAT="$(yosys-config --datdir 2>/dev/null || true)"
[ -f "$DAT/simcells.v" ] && [ -f "$DAT/simlib.v" ] || { echo "[GLS] yosys simcells.v/simlib.v not found under '$DAT' — skipping"; exit 0; }

rc=0
for TOP in "${TOPS[@]}"; do
  echo "[GLS] === $TOP ==="
  tb="${TB[$TOP]:-}"
  [ -n "$tb" ] || { echo "[GLS] $TOP: no testbench mapped — FAIL"; rc=1; continue; }

  net="$BUILD/$TOP.gls.v"; netp="$BUILD/$TOP.gls.param.v"; bin="$BUILD/sim_gls_$TOP"
  runlog="$OUT/$TOP.gls.log"; rpt="$OUT/$TOP.gls.rpt"

  # 1) synthesize to a generic gate netlist (same mapping as the T1 gate).
  rd=""; for f in "${RTL[@]}"; do rd="$rd $ROOT/$f"; done
  if ! yosys -q -l "$BUILD/$TOP.synth.log" -p "
      read_verilog -sv $rd
      hierarchy -check -top $TOP
      proc
      synth -top $TOP -flatten
      write_verilog -noattr $net
  "; then
    echo "[GLS] $TOP: FAIL — synthesis error (see $BUILD/$TOP.synth.log)"; rc=1; continue
  fi

  # 2) synth constant-folds the top's parameters away; the directed TB instantiates
  #    the DUT with named param overrides (at the RTL defaults). Re-insert the RTL
  #    top's parameter defaults as a no-op shim so that override stays legal. The
  #    defaults are read from the RTL header (not hard-coded) so this self-maintains.
  #    (RTL header is `module <top> #( parameter ... ) ( ports );` — ANSI params.)
  shim="$(awk -v top="$TOP" '
      $0 ~ "^[ \t]*module[ \t]+"top"[ \t]*[#(]" {m=1}
      m && /parameter/ {
          s=$0; sub(/.*parameter[ \t]+/,"",s); sub(/\/\/.*/,"",s); gsub(/[ \t\r]/,"",s); sub(/,+$/,"",s);
          if (s!="") p[++n]=s
      }
      m && /^[ \t]*\)/ { for(i=1;i<=n;i++) printf "%s%s",(i>1?", ":""),p[i]; exit }
  ' "$ROOT/src/$TOP.v")"
  if [ -n "$shim" ]; then
    awk -v top="$TOP" -v pl="  parameter $shim;" 'BEGIN{d=0}
      $0 ~ "^module "top"\\(" {m=1}
      {print}
      m && !d && /\);[ \t]*$/ {print pl; d=1; m=0}
    ' "$net" > "$netp"
  else
    cp "$net" "$netp"
  fi

  # 3) compile the self-checking TB against the gate netlist + Yosys sim models.
  if ! iverilog -g2012 -I"$ROOT/test" -o "$bin" "$ROOT/$tb" "$netp" "$DAT/simcells.v" "$DAT/simlib.v" 2> "$BUILD/$TOP.iverilog.log"; then
    echo "[GLS] $TOP: FAIL — gate-level compile error (see $BUILD/$TOP.iverilog.log):"
    grep -iE 'error:' "$BUILD/$TOP.iverilog.log" | head; rc=1; continue
  fi

  # 4) run; the TB is self-checking. PASS requires: the run reaches $finish, prints a
  #    PASSED line, and prints no FAIL/ERROR/MISMATCH.
  vvp "$bin" > "$runlog" 2>&1 || true
  if grep -qiE 'TEST PASSED|PASSED' "$runlog" && ! grep -qiE 'FAIL|ERROR|MISMATCH' "$runlog" && grep -qiE '\$finish' "$runlog"; then
    {
      echo "# $TOP — gate-level simulation report (T6, OSS zero-delay GLS)"
      echo "# generated $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "  netlist ........... generic Yosys gates (simcells/simlib models)"
      echo "  testbench ......... $tb (self-checking directed)"
      echo "  result ............ PASS ($(grep -iE 'PASSED' "$runlog" | head -1 | sed 's/^[[:space:]]*//'))"
    } > "$rpt"
    echo "[GLS] $TOP: PASS — gate-level netlist simulates clean (report: syn/gls/reports/$TOP.gls.rpt)"
  else
    echo "[GLS] $TOP: FAIL — gate-level sim did not pass (see $runlog):"
    tail -15 "$runlog"; rc=1
  fi
done
[ $rc -eq 0 ] && echo "[GLS] T6 gate-level simulation PASSED (OSS zero-delay; SDF-timing GLS + real PPA = needs-pdk)."
exit $rc
