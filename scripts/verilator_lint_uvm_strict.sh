#!/usr/bin/env bash
# Strict Verilator lint for UVM-mirror SV (no UVM libs):
#   - Each APB model compiled alone with explicit --top-module.
#   - Interfaces use tiny module shims under uvm/lint/ (bundles are passive TB hooks).
#   - bridge_stimulus_pkg + interfaces + shim elaborates the package bodies.
# Flags: -Wall --quiet-stats, warnings are errors. Interface-only passes add
#   -Wno-UNUSEDSIGNAL -Wno-UNDRIVEN (expected for undriven bundle nets in lint-only).
# Override tool: VERILATOR=/path/to/verilator
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

V="${VERILATOR:-verilator}"
Flags=(--lint-only -Wall --quiet-stats)
# Passive interface bundles: no protocol driver in lint-only shims.
IfWaiver=(-Wno-UNUSEDSIGNAL -Wno-UNDRIVEN)

"$V" --version >/dev/null

for mod in apb_dual_mem_simple apb_dual_mem_burst apb_dual_mem_ws apb_dual_mem_param apb_ext_mem_dual; do
  "$V" "${Flags[@]}" --top-module "$mod" "uvm/sv/models/${mod}.sv"
done

"$V" "${Flags[@]}" "${IfWaiver[@]}" --top-module vlint_shim_axi4_master_if \
  uvm/lint/vlint_shim_axi4_master_if.sv \
  uvm/sv/interfaces/axi4_master_if.sv

"$V" "${Flags[@]}" "${IfWaiver[@]}" --top-module vlint_shim_apb_burst_ext_side_if \
  uvm/lint/vlint_shim_apb_burst_ext_side_if.sv \
  uvm/sv/interfaces/apb_burst_ext_side_if.sv

"$V" "${Flags[@]}" "${IfWaiver[@]}" --top-module vlint_shim_apb_sel_tracker_if \
  uvm/lint/vlint_shim_apb_sel_tracker_if.sv \
  uvm/sv/interfaces/apb_sel_tracker_if.sv

"$V" "${Flags[@]}" "${IfWaiver[@]}" --top-module vlint_shim_bridge_stimulus_pkg \
  uvm/sv/interfaces/axi4_master_if.sv \
  uvm/sv/interfaces/apb_burst_ext_side_if.sv \
  uvm/sv/interfaces/apb_sel_tracker_if.sv \
  uvm/sv/pkg/bridge_stimulus_pkg.sv \
  uvm/lint/vlint_shim_bridge_stimulus_pkg.sv

echo "verilator_lint_uvm_strict: OK"
