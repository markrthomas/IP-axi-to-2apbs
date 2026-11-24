# DFT_PLAN.md — IP-axi-to-2apbs (T4)

Design-for-test plan for the tapeout-readiness program (`../../DESIGN_READINESS.md`).
This block is the program's **flow pathfinder** — this plan is also the template the
sign-off kit promotes.

Two layers, per the program doctrine (*no artifact = not verified*):

1. **Scan-readiness audit — OSS, runs here now** (`make dft` → `syn/dft/scan_readiness.sh`).
   A structural check on the synthesized generic netlist of the conditions that must
   hold *before* scan insertion. Emits `syn/dft/reports/<top>.scan.rpt`.
2. **Scan insertion + ATPG — `needs-license`** (DFT Compiler / TestMAX or Tessent + a
   PDK). Authored here as the recipe; run where the tools and library exist.

## Design facts

- **Single clock** (`ACLK`) + **async active-low reset** (`ARESETn`). One scan clock;
  no multi-clock lockup-latch strategy needed.
- Tops: `axi4_to_apb4_2x_simple`, `axi4_to_apb4_2x_burst` (address bit 31 selects APB
  port). `axi3lite_regblock` is an example slave read only for hierarchy.
- No RAM/memory arrays (audit reports `mem=0`) → **no MBIST** required.

## Scan-readiness audit — what it gates (entry criteria to scan)

HARD (fail ⇒ not scan-ready):
- **Latch-free** — a transparent D-latch cannot sit on a scan chain. (`select -assert-none`.)
- **No combinational loops** — ATPG cannot justify/propagate through a comb loop.
  (`check -assert`.)

REPORTED (scan-planning inputs):
- flip-flop count = **scan-chain length estimate** (simple ≈ 415, burst ≈ 445);
- set/reset controllability split (flops with no set/reset rely on scan to control X);
- async set/reset flop count (scan mode must hold set/reset inactive);
- memory/RAM count (MBIST candidates) — none here.

Current result: both tops **scan-ready** (0 latches, 0 comb loops, 0 memories).

## Scan insertion + ATPG recipe (`needs-license`)

1. **Scan style:** full-scan, muxed-D flip-flops. One scan chain per top at this size
   (split into N balanced chains at integration for test-time; add compression —
   DFTMAX / TestMAX codec — if pin budget demands).
2. **Scan clock:** `ACLK` drives all flops → single scan clock, no clock mixing.
3. **Async reset in scan:** `ARESETn` is a set/reset port; **gate it with scan-enable**
   so shift/capture is not corrupted (reset held inactive during scan). Add a test
   control point if `ARESETn` is not directly controllable at the test interface.
4. **Uninitialized flops:** the no-set/reset flops are fine for stuck-at (scan loads
   them) but matter for the **power-on reset test** — include a reset-dominance pattern.
5. **Coverage targets:** stuck-at ≥ 99%, transition (at-speed) ≥ 90%; untestable faults
   accounted for (scan-enable, clock, reset trees).
6. **Flow:** `read_verilog` → `set_scan_configuration` → `insert_dft` (DFT Compiler) →
   LEC pre/post-scan (Conformal/Formality) → `TestMAX` ATPG (stuck-at then transition) →
   write patterns (STIL/WGL) → GLS of patterns (SDF) as the sign-off artifact.

## Exit criteria (T4)

- Scan-readiness audit PASS on every top (here now).
- Post-scan LEC clean; ATPG coverage targets met; pattern GLS clean (needs-license).
- DFT constraints (scan-enable, test-clock, reset-gating) captured in the SDC/UPF and
  carried into T2/T3.
