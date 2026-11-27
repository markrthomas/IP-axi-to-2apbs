# SIGNOFF.md — IP-axi-to-2apbs tapeout sign-off checklist

Tracks the eight T-gates from the workspace program (`~/proj/DESIGN_READINESS.md`, workspace-only, not in this repo) for this
block. This repo is the program's **flow pathfinder** — the gate scaffolding here is
promoted to the shared sign-off kit once proven. A gate passes only with a cited
**artifact** (*no artifact = not verified*); `needs-license` / `needs-pdk` items are
authored here and run where the tools/PDK exist.

> **Picking up this program cold?** Read [`../doc/TAPEOUT_HANDOFF.md`](../doc/TAPEOUT_HANDOFF.md)
> first — it maps the current state, the reproduce-each-artifact commands, and the ordered
> plan to completion (this block + the cross-repo rollout).

**Design facts pinned by the pathfinder:** single clock domain (`ACLK` + async
`ARESETn`), no CDC. Two IP tops: `axi4_to_apb4_2x_simple`, `axi4_to_apb4_2x_burst`
(regblock is an example slave). Latch-free. Flops (PPA baseline, `make ppa`): simple 418,
burst 446. `make syn` reports 343/443 (`$_DFF*` only) and `make dft` 415/445 (scan-chain
length); see the flop-count table in `doc/TAPEOUT_HANDOFF.md` §2.

Reports under `syn/**/reports/` are generated and **gitignored**. CI uploads them as the
`signoff-reports` artifact. The T7 release bundle (`make release`) archives every gate report present at build time, with its SHA-256 in `MANIFEST.json`; cite the bundle when signing a gate.

| Gate | Status | Artifact / where | Notes |
|------|--------|------------------|-------|
| **T0** spec freeze | ✅ **PASS** — tag `contract-v1.0` @ `de98fe8` (2026-11-26) | `doc/design_contract.md` §T0; `make test-compliance` | Profile, APB0/APB1 map and parameter set frozen as decisions D1–D21, each traced to [AXI] IHI0022E / [APB] IHI0024C clauses (clause numbers owner-checked 2026-11-26). All five review decisions closed: O1–O3 (#33) and O5 (#34) fixed in RTL with fail-before/pass-after compliance TBs and formal checks; O4 = integration requirement. |
| **T1** synthesizable | ◐ **pathfind PASS** | `syn/reports/*.stat.txt`, `make syn` | Yosys generic synth, latch-free asserted. Liberty-mapped synth = `needs-pdk`. |
| **T2** STA | ◐ collateral | `syn/constraints/axi_apb.sdc`, `syn/sta/opensta.tcl` | SDC authored (single clock, async-reset false path, I/O budgets). Run = `needs-pdk` (OpenSTA/PrimeTime + liberty). |
| **T3** low-power | ◐ authored + OSS-lint | `make lp` → `syn/lp/upf_lint.tcl`; `syn/lp/axi_apb.upf`, `syn/lp/LP_PLAN.md` | IEEE-1801 UPF: PD_AON (always-on control) + switchable PD_APB (datapath), header switch + isolation + retention + P0/P1/P2 PST. Consistency lint PASS (2 domains/3 supplies/iso/ret/3 states). This is the kit's low-power template. Power-aware sim (VCS `-upf`) + RTL↔UPF LEC = `needs-license`. |
| **T4** DFT | ◐ **PASS** (scan-ready) | `make dft` → `syn/dft/reports/<top>.scan.rpt`; `syn/dft/DFT_PLAN.md` | OSS scan-readiness audit: latch-free + no combinational loops (hard), flop/scan-chain inventory (simple 415, burst 445), reset-controllability, async set/reset, 0 RAMs (no MBIST). Single-clock (ACLK) → one scan clock. This is the kit's template DFT run. Scan insertion + ATPG (DFT Compiler/TestMAX) = `needs-license`. |
| **T5** verif sign-off | ◑ strong | UVM-on-Verilator green in CI; 100% line cov; formal safety+liveness | Promote UVM to a licensed sim; document coverage model + exclusions (`doc/coverage_notes.md`). `needs-license` for the sign-off run. |
| **T6** GLS + PPA | ◐ **PASS** (zero-delay GLS + PPA proxy) | `make gls` → `syn/gls/reports/<top>.gls.rpt`; `make ppa` → `syn/ppa/reports/<top>.ppa.rpt`; `syn/gls/T6_PLAN.md` | **GLS:** both bridge tops synthesize to a generic-gate netlist that **simulates clean** — each block's own self-checking directed TB passes when driven against the netlist (Yosys `simcells`/`simlib` models), catching synth/sim mismatch + X-prop the RTL sim can't. **PPA proxy:** cells/flops + logic-depth(`ltp`) tracked per top (simple 806 cells/418 ff/depth 42; burst 1396/446/189; CI `synth` job on `e6aca15`, Yosys-version dependent). SDF-timing GLS, Liberty-mapped synth, real area/power/STA, and formal RTL↔netlist LEC = `needs-pdk` (recipe in T6_PLAN.md). |
| **T7** integration/pkg | ✅ **PASS** — released **v1.0.0** (2026-11-27, `fff41d7`) | `make pkg` / `make pkg-xsd` → `pkg/check_ipxact.sh`; `make release` → `dist/axi4-to-2apbs-<ver>.tar.gz` + `MANIFEST.json`; `pkg/ip-xact/*.xml`, `pkg/INTEGRATION.md`, `pkg/RELEASE.md` | IP-XACT (IEEE 1685-2014) components for both tops (bus interfaces: AXI4 slave + 2× APB4 master + clock + reset; full 53-port model; `addr[31]` memory map; parameter set), **validated against the 1685-2014 XSD in CI** (`make pkg-xsd`, schema fetched from Accellera). `make pkg` gates well-formedness + structure + **IP-XACT↔RTL port-sync** (fails on drift); both tops 53/53. Integration guide (`pkg/INTEGRATION.md`) written against contract 1.0. No CSR RAL: pure protocol bridge, so the "register map" is the `addr[31]` APB decode (regblock map documented as an example slave). **Release bundle:** deterministic tarball of the deliverables + archived gate reports + `MANIFEST.json` (SHA-256 per file, commit, contract tag, gate status); CI rebuilds it twice, checks byte-identity, verifies, and uploads it (`release-bundle`). **Released:** [v1.0.0](https://github.com/markrthomas/IP-axi-to-2apbs/releases/tag/v1.0.0), built and published by CI (`.github/workflows/release.yml`) from tag `v1.0.0` @ `fff41d7`: all gates re-run on the runner, then `axi4-to-2apbs-1.0.0.tar.gz` (40 files incl. 22 gate reports; sha256 `521c0fe0…cfb9b`) verified against its `MANIFEST.json`. Re-verified after download. The bundle's own copy of this table predates publication, so its T7 row says "release tag pending". This is the kit's packaging + release template. |

Legend: ✅ passed · ◑ authored-not-run · ◐ partial/pathfind · ☐ not started.

## Promote-to-kit checklist
Once the scaffolding here is reviewed, lift into the shared sign-off kit (dv-swarm-kit
`signoff/` module per the program doc), then instantiate on #4, #2, #1, #5:
- **T1/T2:** `syn/synth.sh` (parameterized by TOP + RTL list), `syn/constraints/*.sdc`, `syn/sta/opensta.tcl`.
- **T3/T4:** `syn/lp/upf_lint.tcl`, `syn/dft/scan_readiness.sh`.
- **T6:** `syn/gls/gls.sh` (netlist GLS vs the block's self-checking TB) + `syn/ppa/ppa.sh` (PPA proxy).
- **T7:** `pkg/check_ipxact.sh` + the `pkg/ip-xact/*.xml` + `pkg/INTEGRATION.md` templates.
- This `SIGNOFF.md` template.
