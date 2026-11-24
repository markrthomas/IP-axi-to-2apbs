# SIGNOFF.md — IP-axi-to-2apbs tapeout sign-off checklist

Tracks the eight T-gates from the workspace program (`../DESIGN_READINESS.md`) for this
block. This repo is the program's **flow pathfinder** — the gate scaffolding here is
promoted to the shared sign-off kit once proven. A gate passes only with a cited
**artifact** (*no artifact = not verified*); `needs-license` / `needs-pdk` items are
authored here and run where the tools/PDK exist.

**Design facts pinned by the pathfinder:** single clock domain (`ACLK` + async
`ARESETn`), no CDC. Two IP tops: `axi4_to_apb4_2x_simple`, `axi4_to_apb4_2x_burst`
(regblock is an example slave). Latch-free. Flop count: simple ≈ 343, burst ≈ 443.

| Gate | Status | Artifact / where | Notes |
|------|--------|------------------|-------|
| **T0** spec freeze | ☐ open | `doc/design_contract.md` | Freeze AXI profile + both APB4 maps + param set; cite AMBA AXI/APB. |
| **T1** synthesizable | ◐ **pathfind PASS** | `syn/reports/*.stat.txt`, `make syn` | Yosys generic synth, latch-free asserted. Liberty-mapped synth = `needs-pdk`. |
| **T2** STA | ◐ collateral | `syn/constraints/axi_apb.sdc`, `syn/sta/opensta.tcl` | SDC authored (single clock, async-reset false path, I/O budgets). Run = `needs-pdk` (OpenSTA/PrimeTime + liberty). |
| **T3** low-power | ☐ open | `lp/` (to author) | Small/none — APB peripheral gating if any. Good first UPF template for the kit. `needs-license` to validate. |
| **T4** DFT | ☐ open | `dft/` (to author) | Scan + ATPG; template DFT run for the kit. `needs-license`. |
| **T5** verif sign-off | ◑ strong | UVM-on-Verilator green in CI; 100% line cov; formal safety+liveness | Promote UVM to a licensed sim; document coverage model + exclusions (`doc/coverage_notes.md`). `needs-license` for the sign-off run. |
| **T6** GLS + PPA | ☐ open | — | GLS on pathfinder netlist + PPA baseline; `needs-pdk` for target-node PPA. |
| **T7** integration/pkg | ☐ open | `pkg/` (to author) | IP-XACT + register map + RAL + integration guide; becomes the kit's packaging template. |

Legend: ✅ passed · ◑ authored-not-run · ◐ partial/pathfind · ☐ not started.

## Promote-to-kit checklist
Once T1/T2 scaffolding here is reviewed, lift `syn/synth.sh` (parameterized by TOP +
RTL list), `syn/constraints/*.sdc`, `syn/sta/opensta.tcl`, and this `SIGNOFF.md` template
into the shared sign-off kit (dv-swarm-kit `signoff/` module per the program doc), then
instantiate on #4, #2, #1.
