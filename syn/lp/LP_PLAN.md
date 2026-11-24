# LP_PLAN.md — IP-axi-to-2apbs low-power (T3)

Low-power intent for the tapeout-readiness program (`../../DESIGN_READINESS.md`). This
block is the flow pathfinder, so this plan + `axi_apb.upf` are the sign-off kit's
low-power TEMPLATE.

Two layers (program doctrine — *no artifact = not verified*):

1. **UPF consistency lint — OSS, runs here now** (`make lp` → `upf_lint.tcl axi_apb.upf`).
   No OSS tool models UPF power *semantics*; this catches a malformed/inconsistent UPF
   (dangling domains, supplies, iso/retention strategies, power-state tables) before the
   licensed flow. Current result: **PASS** (2 domains, 3 supplies, iso + retention, 3 PST
   states).
2. **Power-aware simulation + LEC — `needs-license`** (VCS `-upf`; Conformal/Formality
   RTL↔UPF LEC). Authored here as the recipe; the `ucie_rdi_to_pcie6_pipe7` repo has a
   runnable Verilator *skeleton* (`make verilator_upf`, control/PMU only, no power intent)
   that this block can adopt as the next step.

## Power architecture

| Domain | Rail | Contents | Rationale |
|--------|------|----------|-----------|
| **PD_AON** | `VDD` (always-on) | AXI4 slave interface + command decode/arbitration | must stay up to accept the access that wakes the datapath |
| **PD_APB** | `VDD_SW` (switched) | both APB master port engines + example regblock | power-gated when the bridge is idle (no outstanding transaction) |

- **Header switch** `apb_hdr_sw`: `VDD → VDD_SW`, gated by `pmu_apb_pwr_en`.
- **Isolation** `apb_iso`: clamp PD_APB outputs crossing into PD_AON to 0 when off
  (`pmu_apb_iso_en`, active-high, parent location) — AON never samples a floating net.
- **Retention** `apb_ret`: save/restore the APB-side config/status state across a power
  cycle (`pmu_apb_save`/`pmu_apb_restore`) so the datapath resumes without reconfigure.

## Power states

| Mode | VDD | VDD_SW | Meaning |
|------|-----|--------|---------|
| **P0 run**     | ON | ON  | normal operation |
| **P1 iso**     | ON | ON  | PD_APB isolated, still powered — drain/clean handoff before shutoff |
| **P2 shutoff** | ON | OFF | PD_APB rail off, state retained |

Sign-off sequence to run: **P0 → P1 → P2 → P1 → P0**, asserting (a) isolation clamps
before `pmu_apb_pwr_en` deasserts, (b) retention save before off / restore after on,
(c) no AON corruption while PD_APB is down, (d) functional resume after P0.

## Control (PMU) contract

The power controller (PMU — in PD_AON) must drive, in order for power-down:
`pmu_apb_save` ↑ → `pmu_apb_iso_en` ↑ → `pmu_apb_pwr_en` ↓; and reverse for power-up:
`pmu_apb_pwr_en` ↑ → (settle) → `pmu_apb_restore` ↑ → `pmu_apb_iso_en` ↓. These signals are
the UPF control ports above. A gate-level PMU + the P0→P2→P0 testbench are the next
authored artifact (adopt the ucie `verilator_upf` skeleton).

## Exit criteria (T3)

- UPF consistency lint PASS (here now).
- VCS `-upf` power-aware sim of the P0→P2→P0 sequence clean; RTL↔UPF LEC clean;
  isolation/retention timing vs. the PMU sequence verified (needs-license).
- `-elements` instance paths in `axi_apb.upf` confirmed against the synthesized hierarchy.
