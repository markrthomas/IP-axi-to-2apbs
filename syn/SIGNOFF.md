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
| **T3** low-power | ◐ authored + OSS-lint | `make lp` → `syn/lp/upf_lint.tcl`; `syn/lp/axi_apb.upf`, `syn/lp/LP_PLAN.md` | IEEE-1801 UPF: PD_AON (always-on control) + switchable PD_APB (datapath), header switch + isolation + retention + P0/P1/P2 PST. Consistency lint PASS (2 domains/3 supplies/iso/ret/3 states). This is the kit's low-power template. Power-aware sim (VCS `-upf`) + RTL↔UPF LEC = `needs-license`. |
| **T4** DFT | ◐ **PASS** (scan-ready) | `make dft` → `syn/dft/reports/<top>.scan.rpt`; `syn/dft/DFT_PLAN.md` | OSS scan-readiness audit: latch-free + no combinational loops (hard), flop/scan-chain inventory (simple 415, burst 445), reset-controllability, async set/reset, 0 RAMs (no MBIST). Single-clock (ACLK) → one scan clock. This is the kit's template DFT run. Scan insertion + ATPG (DFT Compiler/TestMAX) = `needs-license`. |
| **T5** verif sign-off | ◑ strong | UVM-on-Verilator green in CI; 100% line cov; formal safety+liveness | Promote UVM to a licensed sim; document coverage model + exclusions (`doc/coverage_notes.md`). `needs-license` for the sign-off run. |
| **T6** GLS + PPA | ◐ **PASS** (zero-delay GLS + PPA proxy) | `make gls` → `syn/gls/reports/<top>.gls.rpt`; `make ppa` → `syn/ppa/reports/<top>.ppa.rpt`; `syn/gls/T6_PLAN.md` | **GLS:** both bridge tops synthesize to a generic-gate netlist that **simulates clean** — each block's own self-checking directed TB passes when driven against the netlist (Yosys `simcells`/`simlib` models), catching synth/sim mismatch + X-prop the RTL sim can't. **PPA proxy:** cells/flops + logic-depth(`ltp`) tracked per top (simple 806 cells/418 ff/depth 53; burst 1422/446/189). SDF-timing GLS, Liberty-mapped synth, real area/power/STA, and formal RTL↔netlist LEC = `needs-pdk` (recipe in T6_PLAN.md). |
| **T7** integration/pkg | ☐ open | `pkg/` (to author) | IP-XACT + register map + RAL + integration guide; becomes the kit's packaging template. |

Legend: ✅ passed · ◑ authored-not-run · ◐ partial/pathfind · ☐ not started.

## Promote-to-kit checklist
Once T1/T2 scaffolding here is reviewed, lift `syn/synth.sh` (parameterized by TOP +
RTL list), `syn/constraints/*.sdc`, `syn/sta/opensta.tcl`, and this `SIGNOFF.md` template
into the shared sign-off kit (dv-swarm-kit `signoff/` module per the program doc), then
instantiate on #4, #2, #1.
