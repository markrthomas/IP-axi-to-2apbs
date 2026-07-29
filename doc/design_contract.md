# AXI4 to 2x APB4 Bridge Design Contract

This document defines the target behavior for the fully functional bridge.
It is the reference contract for RTL cleanup, verification, and integration
documentation.

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
stalled mid-transaction.

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
`RRESP == DECERR`, zero `RDATA`, and correct `RLAST`.

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

`ID_WIDTH` may vary and must be preserved through responses.

Future parameterization may add a configurable APB select bit, address decode
table, and data width. Until that work is implemented and tested, integrations
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
