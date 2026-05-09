# Development Plan — IP-axi-to-2apbs

**As of:** 2026-05-09

## Current baseline

| Area | Status |
|------|--------|
| RTL | Simple and burst AXI-to-APB4 bridge variants; dual-APB4 arbiter |
| Directed tests | Icarus: single-beat, burst, wait-state sweep (`WAIT_CYCLES` 1–3), param coverage |
| UVM | `uvm/`: UVM monitor environment; lint, TB, VCS targets |
| Documentation | `doc/design_contract.md`, UVM README maps, PDF-friendly trees, `readme-md-pdfs` Make target |
| State | `main`, clean working tree |

## Near-term (small, self-contained)

### 1 — UVM sequence and scoreboard closure

The UVM monitor is in place (`uvm/sv/`). The next step is an active driver (APB4
responder agent) and a scoreboard that queues AXI transactions and verifies
per-beat APB4 read/write handshakes:

- Add a constrained-random AXI driver sequence (burst length, address, strobe).
- Add an APB4 slave agent with configurable wait-states to replace the current
  tie-off.
- Wire a scoreboard: expected APB4 commands come from the AXI driver; observed
  come from the APB4 monitor.
- Add functional coverage groups: burst length, PSEL/PENABLE/PWRITE combos,
  wait-cycle depth, address boundary crossing.

Exit: `make -C uvm vcs-run` passes; scoreboard reports PASS with no mismatches.

### 2 — Negative / protocol-error tests

The design contract (`doc/design_contract.md`) specifies illegal conditions but
no directed negative tests exist:

- AXI SLVERR: illegal burst type (FIXED/WRAP), out-of-range address, unaligned
  burst crossing 4 KB boundary.
- APB4 protocol violation inject: PREADY held deasserted for more than the
  parameterized wait limit; verify the bridge responds with SLVERR and doesn't hang.

### 3 — Makefile CI target

Add a `make ci` target that runs:

1. `make lint` — Verilator `-Wall` across all TBs.
2. `make test-simple-ws-sweep` — wait-state 1/2/3 directed suite.
3. `make test-burst` — burst bench.

Wire to a GitHub Actions job (`ci.yml`) so every PR is gated on lint + directed
smoke.

## Medium-term (moderate scope)

### 4 — Formal verification

Use SymbiYosys (open-source) to prove key bridge properties:

- **APB4 handshake:** PSEL → PENABLE within one cycle; PREADY accepted only
  when PENABLE is high; no overlapping transactions on the same APB4 slave port.
- **AXI response ordering:** same-ID responses emerge in order; no beat is lost
  or duplicated across the two APB4 legs.
- **No deadlock:** a BMC-style reachability proof that the bridge can always
  drain an in-flight AXI burst.

Target: `make formal` in `formal/` using a thin `.sby` wrapper around the bridge
RTL and a property module.

### 5 — Burst bridge: INCR multi-beat coverage

The burst bridge today handles AWLEN/ARLEN but the wait-state sweep only covers
the simple bridge. Add:

- Burst-length sweep (1, 4, 8, 16 beats) to the directed test suite.
- WSTRB partial-write coverage test.
- Read-burst with per-beat wait-state variation (randomized PREADY deassert depth).

### 6 — Second APB4 slave stress

The dual-output arbiter selects which of the two APB4 buses receives a given
AXI transaction based on address decode. Add:

- Concurrent write to slave-0 and read to slave-1 stress test.
- Address-decode boundary tests (transactions that hit the exact upper/lower
  address of each slave range).

## Longer horizon

| Theme | Aim |
|-------|-----|
| AXI4 QoS / ID tagging | Propagate `AWID`/`ARID` and verify response ID matching under concurrent IDs |
| APB3 compatibility mode | Optional `prot` / `strb` tie-offs for APB3 peripherals that don't support extensions |
| Synthesis flow | Yosys gate-count baseline; timing-constraint template for FPGA integration |
| Peripheral model library | Stub APB4 UART, GPIO, timer responders for integration testing |

## How to use this file

- Convert line items into GitHub issues with acceptance criteria before starting.
- Update the **Current baseline** table when major milestones land.
- `make -C doc pdf` (once wired) rebuilds this file alongside `design_contract.pdf`.
