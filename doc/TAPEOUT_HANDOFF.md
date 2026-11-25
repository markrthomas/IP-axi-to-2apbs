# TAPEOUT_HANDOFF.md — pick up the sign-off program from here

**As of:** 2026-11-25 · Repo: `IP-axi-to-2apbs` (block **#3**) · Role: **flow pathfinder**

This document lets another agent (or engineer) resume the tapeout-readiness program
cold, from the current state, and carry it to completion. It is a map, not a copy:
the authoritative plan and pass-criteria live in the documents it links. Read this
first, then the three anchors:

1. **Workspace program & sequencing** — [`../../DESIGN_READINESS.md`](../../DESIGN_READINESS.md)
   (the eight T-gates, tooling/PDK reality, cross-repo status matrix §6, exit criteria §7).
2. **This block's sign-off checklist** — [`../syn/SIGNOFF.md`](../syn/SIGNOFF.md)
   (per-gate status + artifact paths + the promote-to-kit checklist).
3. **This block's per-gate plan** — [`PLAN.md` → "Tapeout readiness"](PLAN.md) (§ at line ~254).

Working rules for an agent here are in [`../CLAUDE.md`](../CLAUDE.md) (repo) and
`~/proj/CLAUDE.md` (workspace SOP). **Read both before you touch anything.** The
non-negotiable doctrine is restated in [§5](#5-doctrine-non-negotiable) below.

---

## 1. One-paragraph orientation

Five design-track IP blocks are being taken from *OSS-verified IP* to *tapeout
sign-off* against eight common gates **T0–T7**. **#3 (this repo)** is the **pathfinder**:
every T-gate flow is stood up and proven here first, then promoted to the shared
**`dv-swarm-kit`** (`templates/signoff/{gls,ppa,pkg}` and the `syn/lp`, `syn/dft`
halves) and rolled onto the other blocks. As of this writing the kit has been rolled
onto **#1 `axi4_to_dfi_ddr`**, **#2 `tilelink_to_AXI4`**, and **#4 `cxl_lpddr5x_bridge`**.
The remaining rollout target is **#5 `ucie_rdi_to_pcie6_pipe7`** (private), blocked on a
GitHub Actions quota reset. Everything above the DV gate is OSS **pathfinding** —
license/PDK-gated sign-off runs are authored here as *collateral* and tagged
`needs-license` / `needs-pdk`, never faked green.

## 2. Current state of #3 (what is done, and the proof)

Every gate below has a committed artifact. Reproduce any of them with the `make`
target shown; all of `syn dft lp gls ppa pkg` also run in CI (`.github/workflows/ci.yml`,
the `signoff-reports` job) on every push — **public repo, so CI minutes are free**.

| Gate | Status | Reproduce | Committed artifact |
|------|--------|-----------|--------------------|
| **T0** spec freeze | ☐ open | — | `doc/design_contract.md` is the basis; not yet frozen/tagged |
| **T1** synth | ◐ pathfind PASS | `make syn` | `syn/reports/*.stat.txt` (latch-free) |
| **T2** STA | ◐ collateral | — (needs-pdk) | `syn/constraints/axi_apb.sdc`, `syn/sta/opensta.tcl` |
| **T3** low-power | ◐ authored + OSS-lint | `make lp` | `syn/lp/axi_apb.upf`, `syn/lp/LP_PLAN.md`, lint PASS |
| **T4** DFT | ◐ PASS (scan-ready) | `make dft` | `syn/dft/reports/<top>.scan.rpt`, `syn/dft/DFT_PLAN.md` |
| **T5** verif sign-off | ◑ strong | `make check` (UVM-on-Verilator) | 100% line cov; formal safety+liveness; `doc/coverage_notes.md` |
| **T6** GLS + PPA | ◐ PASS | `make gls`, `make ppa` | `syn/gls/reports/<top>.gls.rpt`, `syn/ppa/reports/<top>.ppa.rpt`, `syn/gls/T6_PLAN.md` |
| **T7** integration/pkg | ◐ PASS (gated) | `make pkg` | `pkg/ip-xact/*.xml`, `pkg/INTEGRATION.md`, `pkg/check_ipxact.sh` |

Pinned design facts (do not re-derive): single clock domain (`ACLK` + async `ARESETn`),
**no CDC**; two IP tops `axi4_to_apb4_2x_simple` and `axi4_to_apb4_2x_burst` (the regblock
is an example slave); latch-free. T6 proxy baselines: simple **806 cells / 418 ff / depth 53**,
burst **1422 / 446 / 189**. T7 port-sync: both tops **53/53**.

`◐`/`◑` both read as **T-pending**: a real artifact exists for the OSS layer, but the
silicon sign-off run of that gate is gated on a license/PDK this environment does not have.

## 3. What remains — the rest of the plan to completion

Two tracks run in parallel. Neither is authorized to start without the owner's
go-ahead (see §5); this section is the map of *what* remains, not a licence to begin.

### Track A — finish #3 itself to a signed, tagged release

Ordered; the first item is the only one with no external dependency.

1. **T0 — freeze the spec.** Freeze the AXI profile (AXI3-Lite regblock + AXI4 burst
   variants), both APB4 slave maps, and the parameter set, with each decision traced to
   a cited AMBA AXI/APB clause. Basis: `doc/design_contract.md`. Deliverable: a frozen
   contract + a version tag. **This is doable now, here, with no license/PDK** — it is
   the highest-value next step for #3 and the one that unblocks a clean T7 release tag.
2. **T2/T6 silicon run `[needs-pdk]`.** Take the block through OpenLane/OpenROAD on an
   open PDK (sky130/gf180 — viable for a block this small) for a real GDS, then port to
   the target library: Liberty-mapped synth, SDF-annotated (timing) GLS, OpenSTA/PrimeTime
   STA against `syn/constraints/axi_apb.sdc`, post-P&R area/power, and RTL↔netlist LEC.
   Recipe in `syn/gls/T6_PLAN.md`.
3. **T3 power-aware run `[needs-license]`.** Run the authored UPF (`syn/lp/axi_apb.upf`,
   PD_AON + switchable PD_APB) on a power-aware sim (VCS `-upf`) and close RTL↔UPF LEC.
4. **T4 ATPG `[needs-license]`.** Scan insertion + ATPG (DFT Compiler/TestMAX) on the
   scan-ready netlist; hit the stuck-at/transition targets in `syn/dft/DFT_PLAN.md`.
5. **T5 licensed sign-off `[needs-license]`.** Promote the UVM env to a licensed simulator
   run, keep the UVM-on-Verilator gate, and sign off the coverage model + exclusions
   (`doc/coverage_notes.md`).
6. **T7 release.** Once T0 is frozen: regblock register map + RAL, finalize
   `pkg/INTEGRATION.md`, run `IPXACT_XSD=… make pkg` for full XSD validation, and cut a
   **versioned, tagged release with a deliverable manifest** — this becomes the template
   release the other blocks copy.
7. **Sign `syn/SIGNOFF.md`** — fill artifact path + pass date + reviewer per gate.

### Track B — roll the kit onto the rest of the program

- **#5 `ucie_rdi_to_pcie6_pipe7` T6/T7** — the only outstanding kit rollout. **Blocked**
  on the GitHub Actions quota reset (it is a *private* repo, so it consumes included
  minutes; public #1/#2/#4 were free). Its GLS is `slang`-based (not iverilog). **Do not
  publish** any controlled PIPE 7.1 / PCIe 6.x material — #5 is private for that reason.
- **#5 T0 Phase J** — convert the illustrative PIPE §7 encodings to real spec-accurate
  ones (items 51–54), under license, in the private repo. Long-lead, access-gated.
- **Per-block silicon runs** — each of #1/#2/#4 carries the same `needs-pdk`/`needs-license`
  tail as #3 Track A items 2–5, plus two authored-but-unrun follow-ups already documented:
  **#4** a clean SDF-GLS run (its OSS zero-delay GLS reads X from an unreset dual-clock
  async-FIFO RAM — *pessimism, not a bug*; left `needs-pdk`, not forced green) and **#2**
  the Verilator-netlist GLS recipe (its TBs are C++ Verilator harnesses, so the iverilog
  gate is genuinely n/a — no hollow `make gls` was wired).
- **#1 `axi4_to_dfi_ddr`** also carries real **RTL-completion** debt behind its passing
  synth sanity — see its `doc/FULL_FUNCTIONALITY_PLAN.md`.

### Program-level exit criteria (from `DESIGN_READINESS.md` §7)
Done = for each block: all eight gates passed with cited artifacts **or** explicitly
declared sign-off-ready collateral for any license/PDK-gated gate; a signed
`syn/SIGNOFF.md`; a versioned tagged release + manifest; correct controlled-spec
provenance and repo visibility.

### Standing workspace items (not gate work)
Flip `ENFORCE_CEILINGS=1` once baselines are trusted; wire `sync.sh` to vendor the
signoff kit workspace-wide.

## 4. How to work in THIS repo (the gotchas that will bite you)

From [`../CLAUDE.md`](../CLAUDE.md) — the ones that cause silent failure:

- **Push over HTTPS.** `origin` is SSH and SSH auth fails in this environment:
  `git push https://github.com/markrthomas/IP-axi-to-2apbs.git <branch>` (`gh` is logged
  in as `markrthomas`).
- **`NOTES` is gitignored here** — durable knowledge goes in tracked docs (this file,
  `doc/`, `uvm/vlt/README.md`, `CLAUDE.md`), never a NOTES file. (At the workspace root
  `~/proj/NOTES` is the user's private file — never commit it.)
- **UVM-on-Verilator (T5):** needs the standalone `~/verilator` (≥5.050, UVM-capable),
  **not** the OSS CAD Suite's. `unset VERILATOR_ROOT` after sourcing the OSS env.
  The full `--binary` build OOMs this ~8 GB host — **lint locally, build in CI**. Full
  detail in `uvm/vlt/README.md` (read it before touching that flow).
- **Commit narrowly.** This repo often carries in-progress edits across files; stage only
  what the change needs.
- **The sign-off scripts are the kit templates' origin.** If you improve `syn/gls/gls.sh`,
  `syn/ppa/ppa.sh`, or `pkg/check_ipxact.sh` here, the fix belongs upstream in
  `dv-swarm-kit` and re-synced — do not fork kit logic into this repo.

## 5. Doctrine (non-negotiable)

From both CLAUDE.md files; every agent on this program is bound by it:

- **No artifact = not verified.** A gate passes only with a cited, reproducible artifact.
- **Never weaken, skip, or fake a checker to get green.** A skip is **"not run"**, not a
  pass; a fail is a fail. Report it honestly.
- **Tag honestly.** License/PDK-gated layers are `needs-license` / `needs-pdk` collateral,
  authored here and run where the tools exist — never claimed as passed.
- **DUT behaviour changes are the owner's call** — write them up, do not merge them.
- **Controlled material stays private.** Never publish #5's PIPE 7.1 / PCIe 6.x spec
  content; never send proprietary/private IP to external model providers (e.g. kimi/Moonshot).
- **Workspace SOP:** open PRs *ready for review* (not draft); finish what you open —
  review the diff, merge, and delete the branch once CI is green; branches
  `signoff/<date>-<topic>` for this work. Stop and leave a PR open instead when there is a
  real chance of a mistake (RTL/behaviour changes, anything unverifiable end-to-end, red CI).

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)
