# AXI4 to 2x APB4 Bridge Design Contract

| | |
|---|---|
| **Contract version** | `1.0` (T0 **frozen** in content, 2026-11-26) |
| **Status** | All five review decisions are closed ([§T0.4](#t04-open-decisions-owner)): O1–O3 and O5 fixed in RTL (#33, #34), O4 an integration requirement. **One step left before the `contract-v1.0` tag:** the owner checks the [AXI]/[APB] clause numbers against his own copies (§T0.1). |
| **Applies to RTL** | `src/axi4_to_apb4_2x_simple.v`, `src/axi4_to_apb4_2x_burst.v` **with the #33 (O1–O3) and #34 (O5) fixes**; `src/axi3lite_regblock.v` (example slave, [§T0.3](#t03-example-slave-axi3lite_regblock)) |

This document defines the target behavior for the fully functional bridge.
It is the reference contract for RTL cleanup, verification, and integration
documentation. The T0 sections below freeze the profile; the sections after them
(Scope onward) are the detailed behavioural contract and are part of the freeze.

## T0. Spec freeze

### T0.1 Normative references

| Ref | Document | Issue used for clause numbers |
|-----|----------|-------------------------------|
| **[AXI]** | AMBA AXI and ACE Protocol Specification, ARM IHI 0022 | **E** (AXI3/AXI4/AXI4-Lite) |
| **[APB]** | AMBA APB Protocol Specification, ARM IHI 0024 | **C** (APB v2.0 = APB4) |

Clause numbers below follow those issues. Later AXI issues renumber and, from Issue J,
drop AXI3/AXI4 content, so keep citations pinned to Issue E. **Sign-off check:** the
owner confirms every clause number against his own copy before the `contract-v1.0` tag.

### T0.2 Frozen decisions

Each row is the behaviour of the RTL at the version above, traced to the spec clause it
implements or deliberately restricts. "Restriction" means the bridge supports less than
the spec allows; the integrator must respect it ([§T0.5](#t05-integration-requirements)).

| ID | Decision | simple | burst | Spec trace |
|----|----------|:------:|:-----:|-----------|
| D1 | AXI4 subordinate, 32-bit address, 64-bit data | ✓ | ✓ | [AXI] A2 signal lists; restriction to one width |
| D2 | Ports present: AW/W/B/AR/R with `ID`, `ADDR`, `LEN`, `SIZE`, `BURST`, `PROT`, `DATA`, `STRB`, `LAST`, `RESP` + handshakes (53 ports incl. APB). **Absent:** `AxLOCK`, `AxCACHE`, `AxQOS`, `AxREGION`, `xUSER`. No exclusive access, so never `EXOKAY` | ✓ | ✓ | [AXI] A2; A7 (exclusive access is optional for a subordinate) |
| D3 | One transaction in flight. A new AW/AR is accepted only when idle, with no response pending | ✓ | ✓ | [AXI] A3.2.1 (subordinate may hold `READY` low) |
| D4 | Transfer size: `AxSIZE` must equal the bus width (`3'b011`); narrow transfers → `DECERR` | ✓ | ✓ | [AXI] A3.4.1 burst size; restriction |
| D5 | Burst length: simple supports `AxLEN == 0` only (else `DECERR`); burst supports `AxLEN` 0–255 (1–256 beats) | ✓ | ✓ | [AXI] A3.4.1 burst length |
| D6 | Burst type: burst supports `FIXED` + `INCR`; `WRAP` and reserved → `DECERR`. Simple ignores `AxBURST` (single beat) | — | ✓ | [AXI] A3.4.1 burst type; restriction |
| D7 | `FIXED` length is not range-checked. The spec limits `FIXED` to 16 beats; the burst top accepts up to 256 (tolerant, not an error) | — | ✓ | [AXI] A3.4.1 (FIXED/WRAP ≤ 16) |
| D8 | `INCR` address step = `1 << AxSIZE` = 8 bytes; `FIXED` keeps the address | — | ✓ | [AXI] A3.4.1 burst address |
| D9 | APB port select = `addr[31]` (`APB_ADDR_BIT = 31`): APB0 = `0x0000_0000`–`0x7FFF_FFFF`, APB1 = `0x8000_0000`–`0xFFFF_FFFF`. An `INCR` burst whose last-beat address flips bit 31 → `DECERR` | ✓ | ✓ | Design decision (no AXI clause). Note: a compliant master never crosses a 4 KB boundary ([AXI] A3.4.1), so the crossing check only fires for a non-compliant master. It still guards against one |
| D10 | `WSTRB` → `PSTRB` per beat, unchanged | ✓ | ✓ | [AXI] A3.4.3 write strobes; [APB] 3.2 |
| D11 | `AxPROT` → `PPROT` unchanged | ✓ | ✓ | [AXI] A4.7; [APB] 3.5 |
| D12 | `PSLVERR` → `SLVERR`. Write: one `BRESP` for the burst, `SLVERR` if any beat erred. Read: per-beat `RRESP` | ✓ | ✓ | [APB] 3.4, 3.4.3 (mapping to AXI); [AXI] A3.4.4 |
| D13 | Unsupported parameters and window crossing → `DECERR`. A decode-error read returns `AxLEN + 1` beats of `DECERR`, `RDATA = 0`, correct `RLAST` (simple since the O5 fix, #34) | ✓ | ✓ | [AXI] A3.4.4. `DECERR` is normally an interconnect response; using it for unsupported parameters is the existing design choice, and the TBs check for it. Switching to `SLVERR` would be an owner decision |
| D14 | Malformed `WLAST` (early or missing) → `SLVERR`, and the write-data phase ends on `WLAST` or on beat `AWLEN + 1`, whichever comes first. `DECERR` outranks `SLVERR` | — | ✓ | [AXI] A3.4.1 (write data count must match `AWLEN`); robustness beyond spec |
| D15 | APB4 transfers: SETUP then ACCESS; completes on `PREADY`; `PADDR/PPROT/PWRITE/PWDATA/PSTRB` stable through wait states; only one `PSEL` ever asserted | ✓ | ✓ | [APB] 3.1, 3.3, 4.1 |
| D16 | Response signals held stable while `xVALID && !xREADY`; `BID`/`RID` = accepted `AxID` | ✓ | ✓ | [AXI] A3.2.1; A5 (ID) |
| D17 | Single clock `ACLK`, active-low async-assert `ARESETn`; all `VALID` outputs low in reset | ✓ | ✓ | [AXI] A3.1.2 reset |
| D18 | AW vs AR arbitration: **fixed priority, write wins** (resolves O1). `AWREADY` (and simple's `WREADY`) never wait on `ARVALID`; `ARREADY` waits for `!AWVALID` (simple: also `!WVALID`). A continuous write stream can delay reads indefinitely (no starvation guard) | ✓ | ✓ | [AXI] A3.2.1, A3.3 |
| D19 | `PSTRB` = 0 for the whole of every APB read (resolves O2) | ✓ | ✓ | [APB] 2.1 Table 2-1, 3.2 |
| D20 | A `DECERR` write takes every W beat (until `WLAST` or `AWLEN + 1` beats) before `BVALID` (resolves O3 for simple; burst already did this, D14) | ✓ | ✓ | [AXI] A3.3.1 (B after last W), A3.4.1 |
| D21 | Addresses are not alignment-checked; integrators must issue 8-byte-aligned addresses (resolves O4 as integration requirement R3) | ✓ | ✓ | [AXI] A3.4.1 burst address |

**Frozen parameter set** (the only configuration covered by verification and sign-off):

| Parameter | Frozen value | Notes |
|-----------|-------------|-------|
| `ADDR_WIDTH` | 32 | |
| `DATA_WIDTH` | 64 | `EXPECTED_AXSIZE` is derived from it; other widths are unverified |
| `ID_WIDTH` | 4 | Pass-through only, so other widths ≥ 1 are expected to work, but every TB (incl. `tb_parameterized_config`) uses 4: other widths are **unverified** |
| `APB_ADDR_BIT` | 31 | The RTL exposes it as a parameter, but other values are unverified and unsupported |

### T0.3 Example slave: `axi3lite_regblock`

The regblock is a test/demo slave, **not** a deliverable IP top, and is not in the T1–T7
sign-off. It is frozen only so its tests have a stable reference:

- "AXI3-Lite" is a **repo-defined profile, not an ARM-defined one**: AXI4-Lite signalling
  ([AXI] B1) plus AXI3 IDs and `WID` (which must equal `AWID`, else `SLVERR`).
- 32 × 32-bit RW registers at byte offsets `0x00`–`0x7C`; out-of-range → `SLVERR`;
  `WSTRB` byte enables; all registers reset to 0. `DATA_WIDTH = 32` only (the strobe
  logic is hard-coded to 4 lanes).
- Synchronous reset (the bridge tops use asynchronous reset).

### T0.4 Open decisions (owner)

Code review for this freeze found five behaviours where the RTL does not do what a
compliant AXI master or APB4 completer expects. Each is a DUT behaviour change and
the owner's call. O1–O4 were decided on 2026-11-25 and O5 on 2026-11-26 (the recommended
option in each case). O5 was found while fixing O3.

| ID | Finding | Decision / status | Evidence |
|----|---------|-------------------|----------|
| **O1** | **AW/AR deadlock.** With `AWVALID` and `ARVALID` both high, neither READY asserted, and a compliant master (which must hold VALID, [AXI] A3.2.1/A3.3) waited forever. Simple also deadlocked on `WVALID` + `ARVALID`. Formal hid it with `assume (!(AWVALID && ARVALID))` | **Resolved (#33):** fixed priority, write wins → D18. Formal assumption replaced by a narrower fairness assumption (no *new* write starts while an AR waits), used only for bounded AR liveness. Simple L3 worst case measured at 27 cycles (bound < 30). New burst **L0** check (idle ⇒ immediate AW/AR acceptance) catches the deadlock, which the depth-relative bounds could not | `test/tb_compliance_{simple,burst}.v` O1a/O1b: deadlock before, pass after. Formal fails on the pre-fix RTL (simple frame 27, burst L0 frame 1) and passes after |
| **O2** | **`PSTRB` not driven low on reads**: it kept the previous write's strobes ([APB] 3.2) | **Resolved (#33):** `PSTRB <= 0` at read setup → D19. UVM scoreboard now flags a non-zero read `PSTRB` | compliance TBs' continuous `PSTRB` monitor: errors before, clean after |
| **O3** | **simple DECERR write left W beats behind**: `B` after one beat, leftover beats paired with the next write. And with AW before W on that path, `WREADY` never asserted (deadlock); the handshake-based formal assumption had made those traces infeasible | **Resolved (#33):** `ST_ERR_RESP` drains W until `WLAST` / `AWLEN + 1` → D20. Simple formal now assumes `AWLEN == 0` (its profile) and still covers the DECERR path via `AWSIZE` | `tb_compliance_simple` O3a/O3b: early B + deadlock before, pass after |
| **O4** | **Unaligned start address** not checked; burst `INCR` steps the unaligned address | **Resolved (no RTL change):** integration requirement R3 → D21 | — |
| **O5** | **simple: decode-error read returns one beat.** For `ARLEN != 0`, simple returns a single `DECERR` beat with `RLAST = 1`; AXI requires `ARLEN + 1` beats ([AXI] A3.4.1), and D13 promises that. A compliant master waits for the remaining beats | **Resolved (#34):** a new `ST_RERR_RESP` state streams `ARLEN + 1` `DECERR` beats (`RDATA = 0`, `RID = ARID`, `RLAST` only on the last) → D13 ✓ for simple. Formal: new R1 check (`RLAST` exactly on beat `ARLEN`) and R2 check (`RRESP`/`RID` hold across beats); P5 now applies to the `RLAST` beat; simple props assume `ARLEN ≤ 3`; L3 bound re-measured (worst case 34 → < 37) | `tb_compliance_simple` O5a/O5b: `RLAST` on beat 0 of 4, then deadlock before (CI `regress` on #34's first commit); pass after. Formal R1 fails on the pre-O5 RTL (frame 3) |

### T0.5 Integration requirements

- **R3**: all AXI addresses must be 8-byte aligned (`AxADDR[2:0] == 0`). Unaligned
  addresses are passed to APB unchanged and are not supported.
- **R4**: bursts must not cross the APB window (`addr[31]`); a crossing gets `DECERR`, not split.
- **R6**: only the frozen parameter set (§T0.2) is supported.
- **R7**: reads have lower priority than writes (D18). If read latency matters, the
  system must not keep a write always pending.

(Retired by the RTL fixes: R1 "no simultaneous AW/AR" (O1), R5 "don't use `PSTRB` on reads" (O2) and R2 "simple: `AxLEN == 0` only" (O3 for writes, O5 for reads). Multi-beat requests to the simple top are still unsupported, but they now get a protocol-correct `DECERR`.)

## Scope

The production bridge is a restricted AXI4 slave to two APB4 master bridge.
It accepts one AXI transaction at a time and serializes each AXI beat into one
APB transfer on either APB0 or APB1.

The intended production scope is:

- 32-bit AXI/APB address bus.
- 64-bit AXI/APB data bus.
- AXI write and read IDs preserved on `BID` and `RID`.
- One outstanding AXI transaction at a time.
- AXI `FIXED` and `INCR` bursts.
- AXI burst size fixed at 8 bytes per beat: `AxSIZE == 3'b011`.
- APB target selected by address bit 31:
  - `addr[31] == 1'b0`: APB0.
  - `addr[31] == 1'b1`: APB1.
- Bursts must stay within one APB target window.
- APB wait states supported on reads and writes.
- APB `PSLVERR` propagated to AXI as `SLVERR`.

The bridge is intentionally not a full AXI interconnect. It does not reorder,
interleave, pipeline multiple outstanding transactions, arbitrate between
multiple AXI masters, or split a single AXI burst across both APB ports.

## AXI Support

### Write Address Channel

The bridge accepts `AWVALID` only when no read, write, or response transaction
is in progress. On `AWVALID && AWREADY`, it captures:

- `AWID`
- `AWADDR`
- `AWLEN`
- `AWSIZE`
- `AWBURST`
- `AWPROT`

Supported write parameters:

- `AWSIZE == 3'b011`
- `AWBURST == 2'b00` (`FIXED`) or `AWBURST == 2'b01` (`INCR`)
- `AWLEN` may request 1 to 256 beats
- the first and last beat addresses must select the same APB port

Unsupported write parameters cause a decode error response. The bridge must
still handle the write data channel predictably so the AXI master is not left
stalled mid-transaction. (Both tops meet this; the simple top since the O3 fix, D20.)

### Write Data Channel

The bridge accepts exactly `AWLEN + 1` write data beats for an accepted write.
For valid transactions:

- each `WVALID && WREADY` beat creates one APB write transfer
- `WSTRB` maps directly to APB `PSTRB`
- `WLAST` must be asserted on the final beat only
- APB address increments by 8 bytes for `INCR` bursts
- APB address remains fixed for `FIXED` bursts

The final implementation must detect early or missing `WLAST`. The response
policy for malformed `WLAST` is `SLVERR` unless the address/control phase was
already a decode error, in which case `DECERR` takes priority.

The write-data phase terminates on `WLAST` (the authoritative end of the burst)
rather than purely on the expected beat count. A compliant master stops driving
`W` after asserting `WLAST`; a premature `WLAST` must therefore complete the
transaction with a single `SLVERR` response and must not leave `WREADY` parked
waiting for beats the master will never send. If `WLAST` is missing entirely,
the phase still terminates once `AWLEN + 1` beats have been accepted, again with
`SLVERR`.

### Write Response Channel

The bridge returns one `BVALID` response per accepted write transaction.
`BID` must match the accepted `AWID`.

`BRESP` policy:

- `OKAY`: all beats completed without APB error.
- `SLVERR`: at least one APB write beat completed with `PSLVERR`, or the write
  data channel was malformed.
- `DECERR`: unsupported AXI write parameters or APB target-window crossing.

`BID` and `BRESP` must remain stable while `BVALID && !BREADY`.

### Read Address Channel

The bridge accepts `ARVALID` only when no read, write, or response transaction
is in progress. On `ARVALID && ARREADY`, it captures:

- `ARID`
- `ARADDR`
- `ARLEN`
- `ARSIZE`
- `ARBURST`
- `ARPROT`

Supported read parameters:

- `ARSIZE == 3'b011`
- `ARBURST == 2'b00` (`FIXED`) or `ARBURST == 2'b01` (`INCR`)
- `ARLEN` may request 1 to 256 beats
- the first and last beat addresses must select the same APB port

Unsupported read parameters cause a decode error read response stream.

### Read Data Channel

The bridge returns exactly `ARLEN + 1` read data beats for an accepted read.
For valid transactions:

- each AXI read beat is sourced by one APB read transfer
- APB address increments by 8 bytes for `INCR` bursts
- APB address remains fixed for `FIXED` bursts
- `RID` matches the accepted `ARID`
- `RLAST` asserts only on the final read beat

`RID`, `RDATA`, `RRESP`, and `RLAST` must remain stable while
`RVALID && !RREADY`.

`RRESP` policy:

- `OKAY`: corresponding APB read beat completed without APB error.
- `SLVERR`: corresponding APB read beat completed with `PSLVERR`.
- `DECERR`: unsupported AXI read parameters or APB target-window crossing.

For a decode-error read, the bridge returns `ARLEN + 1` read beats with
`RRESP == DECERR`, zero `RDATA`, and correct `RLAST`. (Both tops; the simple top since the O5 fix.)

## APB4 Behavior

For every valid AXI beat, the bridge issues one APB transfer:

- setup phase: `PSELx == 1'b1`, `PENABLEx == 1'b0`
- access phase: `PSELx == 1'b1`, `PENABLEx == 1'b1`
- completion when `PREADYx == 1'b1` during the access phase

During APB wait states, address and control outputs must remain stable:

- `PADDRx`
- `PPROTx`
- `PWRITEx`
- `PWDATAx` for writes
- `PSTRBx` for writes

Only one APB port may be selected for a transfer. The inactive APB port must
keep `PSEL` and `PENABLE` deasserted.

`PPROT` maps directly from `AWPROT` or `ARPROT`.

## Addressing

The bridge uses `addr[31]` as a fixed APB port select bit. This creates two
2 GiB target windows:

| Address range | APB port |
| --- | --- |
| `0x0000_0000` to `0x7FFF_FFFF` | APB0 |
| `0x8000_0000` to `0xFFFF_FFFF` | APB1 |

An `INCR` burst whose last beat crosses `addr[31]` is rejected with `DECERR`.
`FIXED` bursts cannot cross because all beats use the same address.

## Parameter Contract

The current target contract is intentionally fixed-width:

- `ADDR_WIDTH == 32`
- `DATA_WIDTH == 64`
- `DATA_WIDTH / 8 == 8`

`ID_WIDTH` may vary and must be preserved through responses (only 4 is verified;
see the frozen parameter set in §T0.2).

`APB_ADDR_BIT` already exists as an RTL parameter but only 31 is verified or
supported. Future parameterization may make the APB select bit, an address decode
table, and the data width configurable. Until that work is implemented and tested, integrations
should treat non-32-bit address or non-64-bit data configurations as
unsupported.

## Current Implementation Notes

The repository currently contains:

- `axi4_to_apb4_2x_simple`: single-beat bridge with APB0/APB1 routing and APB
  wait-state support.
- `axi4_to_apb4_2x_burst`: initial restricted-burst bridge with parameter
  checks for size, burst type, and `addr[31]` crossing.

The burst RTL is now contract-complete for the fixed-width (`ADDR_WIDTH == 32`,
`DATA_WIDTH == 64`) scope:

- `WLAST` handling terminates the write-data phase on `WLAST` and flags premature
  or missing `WLAST` as `SLVERR` without deadlocking a compliant master (verified
  by directed `tb_axi4_to_apb4_2x_burst_extended.v`, cocotb
  `test_premature_wlast_no_deadlock` / `test_missing_wlast_no_deadlock`, and the
  randomized stress bench).
- Wait states on reads and writes, `PSLVERR` accumulation, `DECERR` on
  unsupported parameters and `addr[31]` crossing, and response stability while
  `xVALID && !xREADY` are exercised across the directed, cocotb, and stress
  suites.

Verification split: SymbiYosys formal (BMC depth 50 + cover, safety + liveness)
proves the compliant-`WLAST` space exhaustively; the malformed-`WLAST`
error/edge behavior is covered by directed and constrained-random simulation.
Remaining future work (parameterized data width, APB3 compatibility, synthesis
flow) is tracked in `doc/PLAN.md`.
