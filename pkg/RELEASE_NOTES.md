# axi4-to-2apbs v1.0.0

First tagged release of the AXI4 → 2× APB4 bridge. It implements **design contract `1.0`**
(tag `contract-v1.0`).

## IP

- Two tops with identical 53-port interfaces:
  - `axi4_to_apb4_2x_simple`: single-beat traffic.
  - `axi4_to_apb4_2x_burst`: `INCR`/`FIXED`, 1–256 beats.
- `addr[31]` selects APB0 or APB1. One transaction is in flight at a time.
- Frozen configuration: 32-bit address, 64-bit data, `ID_WIDTH` 4, select bit 31.

## Changes since the pre-release design (T0 review, #33 and #34)

- **AW/AR deadlock fixed.** Writes now have priority when AW and AR are valid together.
  Before, a compliant manager could hang the bridge. A continuous stream of writes can delay
  reads (integration requirement R7).
- **`PSTRB` is all zero on APB reads** (APB 3.2).
- **simple, decode-error writes:** every W beat is accepted before `BRESP`. Before, leftover
  beats could be paired with the next write, and AW-before-W deadlocked.
- **simple, decode-error reads:** all `ARLEN + 1` `DECERR` beats are returned. Before, only
  one beat came back.

## Verification

- Directed SV (Icarus), including the AXI/APB compliance benches (`make test-compliance`).
  Each fix was shown to fail before and pass after.
- cocotb, and UVM on Verilator 5.050 for all tops; 100% line coverage.
- Formal (SymbiYosys):
  - safety properties;
  - bounded liveness, with fairness for write priority;
  - beat counting for decode-error reads;
  - an idle-acceptance check that catches the original deadlock.

## Collateral and gates

The T0–T7 status is in `syn/SIGNOFF.md`, and the release bundle archives the gate reports.

- **T0:** spec freeze PASS.
- **T1, T4, T6:** pass at the OSS pathfinding level: synthesis, scan readiness, zero-delay
  GLS and a PPA proxy.
- **T7:** IP-XACT (IEEE 1685-2014, XSD-validated) and the integration guide.
- **Not in this release:** items that need a PDK or a licensed tool (real STA, SDF GLS, ATPG,
  power-aware sim).

## Integration requirements

- **R3:** addresses must be 8-byte aligned.
- **R4:** bursts must not cross `addr[31]`.
- **R6:** use only the frozen parameter set.
- **R7:** reads have lower priority than writes.

See `pkg/INTEGRATION.md`.
