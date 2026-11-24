# syn/ — synthesis & sign-off flow (tapeout-readiness pathfinder)

This directory stands up the T1/T2 sign-off flow for `IP-axi-to-2apbs`, the **flow
pathfinder** for the workspace tapeout-readiness program (`../DESIGN_READINESS.md`).

## What runs here (OSS, no PDK)
```sh
make syn          # or: syn/synth.sh
```
Yosys generic synthesis of both bridge tops, with a hard **latch-free** assertion and a
cell/flop inventory written to `syn/reports/`. This is a real **T1 synthesizability**
artifact — it does not need a standard-cell library or foundry PDK.

## What is collateral (run where the tools/PDK exist)
- `constraints/axi_apb.sdc` — timing constraints (single `ACLK` domain, async-reset
  false path, I/O budgets). Used by STA and by a liberty-mapped synth.
- `sta/opensta.tcl` — STA driver for OpenSTA (open pathfind) or PrimeTime (sign-off);
  needs a target liberty + a mapped netlist (`needs-pdk`).
- `SIGNOFF.md` — the T0–T7 checklist with artifact paths and current status.

## Tool status in this workspace
`yosys` ✅ · `sby` ✅ · `verilator` ✅ — `openroad` / `opensta` / `openlane` ✗, no PDK.
So T1 is pathfindable here; T2/T6 (STA, P&R, GDS, PPA) are authored collateral.

## Next (promote to the shared kit)
See the promote-to-kit checklist at the bottom of `SIGNOFF.md`.
