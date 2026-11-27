#!/usr/bin/env bash
# syn/gls/gls.sh — T6 gate-level simulation (Icarus).
#
# This block (IP-axi-to-2apbs) is the program's flow pathfinder: the shared T6 gate is
# stood up here first, then promoted to the shared sign-off kit.
#
# Two netlist sources, same testbenches:
#
#  1. Generic (default, `make gls`): Yosys synthesizes each top to a generic gate
#     netlist, simulated with Yosys' simcells.v / simlib.v. No PDK needed.
#  2. sky130 routed netlist (`make gls-sky130`, CI: silicon workflow): set
#       GLS_NETLIST_DIR  dir holding <TOP>.nl.v (LibreLane runs/<tag>/final/nl)
#       GLS_CELL_MODELS  cell model files (sky130_fd_sc_hd primitives.v + cell .v)
#       GLS_DEFINES      e.g. "-DFUNCTIONAL -DUNIT_DELAY=#1"
#       GLS_LABEL        text for the report (e.g. "sky130 routed netlist")
#       GLS_OUT          report dir (default syn/gls/reports)
#     Here a missing tool is a FAIL, not a skip: the run was asked for explicitly.
#
# Each top runs its self-checking directed TB AND the AXI/APB compliance bench
# (test/tb_compliance_*.v); all must pass. This is functional GLS (zero/unit delay):
# it catches synth/sim mismatch, lost initialization and X-propagation. SDF-annotated
# timing GLS is a separate step (see syn/gls/T6_PLAN.md).
#
# Usage:  syn/gls/gls.sh [TOP ...]   (default: both bridge variants)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT="${GLS_OUT:-$HERE/reports}"
BUILD="$HERE/build${GLS_NETLIST_DIR:+-ext}"
mkdir -p "$OUT" "$BUILD"
cd "$ROOT"

RTL=(src/axi4_to_apb4_2x_simple.v src/axi4_to_apb4_2x_burst.v src/axi3lite_regblock.v)
# Per-top self-checking testbenches (all must pass).
declare -A TBS=(
  [axi4_to_apb4_2x_simple]="test/tb_axi4_to_apb4_2x_simple.v test/tb_compliance_simple.v"
  [axi4_to_apb4_2x_burst]="test/tb_axi4_to_apb4_2x_burst.v test/tb_compliance_burst.v"
)
TOPS=("$@")
[ ${#TOPS[@]} -eq 0 ] && TOPS=(axi4_to_apb4_2x_simple axi4_to_apb4_2x_burst)

EXT=0; [ -n "${GLS_NETLIST_DIR:-}" ] && EXT=1
need() {  # need <tool>: skip in generic mode (OSS CAD Suite absent), FAIL in external mode
  command -v "$1" >/dev/null && return 0
  if [ $EXT -eq 1 ]; then echo "[GLS] FAIL — $1 not on PATH"; exit 1; fi
  echo "[GLS] $1 not on PATH — skipping (needs OSS CAD Suite)"; exit 0
}
need iverilog; need vvp
if [ $EXT -eq 1 ]; then
  read -r -a MODELS <<< "${GLS_CELL_MODELS:?GLS_CELL_MODELS must list the cell model files}"
  for f in "${MODELS[@]}"; do [ -f "$f" ] || { echo "[GLS] FAIL — cell model $f not found"; exit 1; }; done
  read -r -a DEFS <<< "${GLS_DEFINES:-}"
  LABEL="${GLS_LABEL:-external netlist}"
else
  need yosys
  DAT="$(yosys-config --datdir 2>/dev/null || true)"
  [ -f "$DAT/simcells.v" ] && [ -f "$DAT/simlib.v" ] || { echo "[GLS] yosys simcells.v/simlib.v not found under '$DAT' — skipping"; exit 0; }
  MODELS=("$DAT/simcells.v" "$DAT/simlib.v"); DEFS=()
  LABEL="generic Yosys gates (simcells/simlib models)"
fi

rc=0
for TOP in "${TOPS[@]}"; do
  echo "[GLS] === $TOP ($LABEL) ==="
  read -r -a tbs <<< "${TBS[$TOP]:-}"
  [ ${#tbs[@]} -gt 0 ] || { echo "[GLS] $TOP: no testbench mapped — FAIL"; rc=1; continue; }

  netp="$BUILD/$TOP.gls.param.v"; rpt="$OUT/$TOP.gls.rpt"
  if [ $EXT -eq 1 ]; then
    net="$GLS_NETLIST_DIR/$TOP.nl.v"
    [ -f "$net" ] || { echo "[GLS] $TOP: FAIL — netlist $net not found"; rc=1; continue; }
  else
    # 1) synthesize to a generic gate netlist (same mapping as the T1 gate).
    net="$BUILD/$TOP.gls.v"
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
  fi

  # 2) Synthesis constant-folds the top's parameters away, but the TBs instantiate the
  #    DUT with named parameter overrides (at the RTL defaults). Re-insert the RTL
  #    top's parameter defaults as a no-op shim so the overrides stay legal. They are
  #    read from the RTL header, so this maintains itself.
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
      $0 ~ "^[ \t]*module[ \t]+"top"[ \t]*\\(" {m=1}
      {print}
      m && !d && /\);[ \t\r]*$/ {print pl; d=1; m=0}
    ' "$net" > "$netp"
    grep -q "^  parameter " "$netp" || { echo "[GLS] $TOP: FAIL — could not insert the parameter shim"; rc=1; continue; }
  else
    cp "$net" "$netp"
  fi

  # 3) compile and run each self-checking TB against the netlist. PASS requires: the
  #    run reaches $finish, prints a PASSED line, and prints no FAIL/ERROR/MISMATCH.
  results=(); top_ok=1
  for tb in "${tbs[@]}"; do
    name="$(basename "$tb" .v)"; bin="$BUILD/sim_gls_${TOP}_$name"; runlog="$OUT/$TOP.$name.gls.log"
    if ! iverilog -g2012 "${DEFS[@]}" -I"$ROOT/test" -o "$bin" "$ROOT/$tb" "$netp" "${MODELS[@]}" \
         2> "$BUILD/$TOP.$name.iverilog.log"; then
      echo "[GLS] $TOP/$name: FAIL — compile error (see $BUILD/$TOP.$name.iverilog.log):"
      grep -iE 'error' "$BUILD/$TOP.$name.iverilog.log" | head; top_ok=0; results+=("$name: FAIL (compile)"); continue
    fi
    vvp -n "$bin" > "$runlog" 2>&1 || true
    if grep -qiE 'PASSED' "$runlog" && ! grep -qiE 'FAIL|ERROR|MISMATCH' "$runlog" && grep -qiE '\$finish' "$runlog"; then
      results+=("$name: PASS ($(grep -iE 'PASSED' "$runlog" | head -1 | sed 's/^[[:space:]]*//'))")
      echo "[GLS] $TOP/$name: PASS"
    else
      results+=("$name: FAIL (see $(basename "$runlog"))"); top_ok=0
      echo "[GLS] $TOP/$name: FAIL — see $runlog:"; tail -12 "$runlog"
    fi
  done
  {
    echo "# $TOP — gate-level simulation report (T6, functional GLS)"
    echo "# generated $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "  netlist ........... $LABEL${GLS_NETLIST_DIR:+ ($net)}"
    [ ${#DEFS[@]} -gt 0 ] && echo "  defines ........... ${DEFS[*]}"
    for r in "${results[@]}"; do echo "  testbench ......... $r"; done
    echo "  result ............ $([ $top_ok -eq 1 ] && echo PASS || echo FAIL)"
  } > "$rpt"
  [ $top_ok -eq 1 ] || rc=1
done
[ $rc -eq 0 ] && echo "[GLS] T6 gate-level simulation PASSED ($LABEL)."
exit $rc
