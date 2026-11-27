# T6 — GLS + PPA plan (IP-axi-to-2apbs, flow pathfinder)

T6 is the post-synthesis sign-off: prove the **gate netlist** (not just the RTL) is
functionally correct and characterise its **PPA** (power / performance / area). This
block is the program's flow pathfinder, so T6 is stood up here first, then promoted to
the shared sign-off kit.

## What runs here (OSS, no PDK) — real artifacts

| Step | Command | Artifact | Proves |
|------|---------|----------|--------|
| **Zero-delay GLS** | `make gls` (`syn/gls/gls.sh`) | `syn/gls/reports/<top>.gls.rpt` | The synthesized generic-gate netlist **simulates correctly**: each block's own self-checking directed testbench passes when driven against the netlist (Yosys `simcells.v`/`simlib.v` model the generic cells), not the RTL. Catches synth/sim mismatch, lost initialization, and X-propagation. |
| **PPA proxy** | `make ppa` (`syn/ppa/ppa.sh`) | `syn/ppa/reports/<top>.ppa.rpt` | Technology-independent PPA baseline: generic cell count + flop count (area proxy), longest topological logic path / `ltp` (timing proxy). Moves monotonically with real numbers; tracked across revisions. |

GLS mechanics (pathfinder notes): `synth` constant-folds the top's parameters away, but
the directed TBs instantiate the DUT with named parameter overrides (at the RTL
defaults). `gls.sh` re-inserts the RTL top's parameter defaults as a no-op shim (read
from the RTL header, so it self-maintains) to keep the override legal. Netlists and sim
binaries land in `syn/gls/build/` (gitignored); only the `.rpt` summaries are the tracked
artifact, and CI uploads the full `reports/` tree.

## What runs on an open PDK (sky130, CI) — real artifacts

| Step | Command | Artifact | Proves |
|------|---------|----------|--------|
| **RTL-to-GDS** | `make pnr` (`syn/pnr/run_pnr.sh`, LibreLane Classic, sky130A / sky130_fd_sc_hd; CI `silicon` workflow) | GDS, routed netlist, SPEF/SDF (CI artifact `sky130-<top>`); `syn/pnr/reports/<top>.pnr.rpt` | Liberty-mapped synthesis, P&R, DRC (router/Magic/KLayout), LVS, antenna; post-P&R area + power; post-route STA at 9 corners against `syn/constraints/axi_apb.sdc` (setup/hold WNS/TNS, Fmax). |
| **Post-route GLS** | `make gls-sky130` (`syn/pnr/gls_sky130.sh` → `syn/gls/gls.sh` external-netlist mode) | `syn/pnr/reports/<top>.gls.rpt` | The **routed** sky130 netlist simulates correctly with the sky130_fd_sc_hd cell models (functional, unit delay): directed TB + AXI/APB compliance bench. |

Result on 2026-11-27 (`d884d57`): both tops DRC/LVS clean, hold met everywhere, setup NOT
met at the 5.0 ns placeholder (tt Fmax ≈ 189 MHz simple / 181 MHz burst), post-route GLS
PASS. Numbers are in `syn/SIGNOFF.md` (T2, T6).

## What is deferred — `needs-pdk` (target library) / `needs-license`

On sky130, steps 1, 3 and 4 below are now done with open tools; what remains is running
them on the **target** library and closing the items the OSS flow does not cover
(SDF-timing GLS, activity-based power, LEC).

Real T6 sign-off needs a standard-cell library + a place-and-route flow. These are
authored here as the recipe and run where a PDK exists (open: sky130 + OpenROAD/OpenSTA;
or a foundry PDK + PrimeTime/PrimePower/Fusion Compiler):

1. **Liberty-mapped synthesis** — `yosys ... abc -liberty <pdk>.lib` → a real standard-cell
   netlist (vs the generic-cell netlist used here).
2. **SDF-annotated (timing) GLS** — re-run the TBs on the mapped netlist with
   `$sdf_annotate` back-annotation from STA; proves functional correctness *at timing*,
   including setup/hold and glitch behaviour the zero-delay GLS here cannot see.
3. **STA sign-off** — OpenSTA/PrimeTime with the Liberty + the `syn/constraints/axi_apb.sdc`
   already authored at T2: setup+hold clean at PVT corners, Fmax per clock.
4. **Area + power** — post-P&R area (µm²) and power (mW) from OpenROAD/PrimePower using
   switching activity (VCD/SAIF) captured from the GLS run.
5. **RTL↔netlist LEC** — formal equivalence of the mapped netlist vs RTL
   (Cadence Conformal / Synopsys Formality; the OSS `yosys equiv` flow does not close on
   the generic netlist here because generic `synth` re-encodes state — bounded-equivalence
   BMC is a possible OSS follow-up, but formal LEC sign-off is a licensed-tool step).

## Promote-to-kit

Once reviewed, lift `syn/gls/gls.sh` (parameterized by TOP + the per-top self-checking TB)
and `syn/ppa/ppa.sh` into the shared sign-off kit's `signoff/` module alongside the
existing `synth.sh` / `scan_readiness.sh` / `upf_lint.tcl`, then instantiate on #4/#2/#1/#5.
(On a slang-frontend block such as #5, the GLS reads the netlist from its slang-based synth
and the same simcells/simlib models apply.)
