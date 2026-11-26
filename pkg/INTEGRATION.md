# Integration guide — AXI4 → 2× APB4 bridge

Tapeout-readiness program **T7** (integration / packaging) deliverable. This guide plus the
IP-XACT in `ip-xact/` is what an SoC integrator needs to instance the IP. Every behaviour
stated here comes from the frozen **design contract `1.0`**
([`../doc/design_contract.md`](../doc/design_contract.md), tag `contract-v1.0`); the decision
IDs (D*n*) and integration requirements (R*n*) below refer to its §T0. The IP-XACT port list
is kept in sync with the RTL by `make pkg`, and the XML is validated against the IEEE
1685-2014 schema by `make pkg-xsd`.

## IP variants

| Top (module / IP-XACT name) | Use when |
|---|---|
| `axi4_to_apb4_2x_simple` | Single-beat traffic (`AxLEN == 0`). Anything else gets a protocol-correct `DECERR` (all write beats accepted; `ARLEN + 1` read beats returned). |
| `axi4_to_apb4_2x_burst`  | `INCR` / `FIXED` bursts of 1–256 beats (superset of simple). |

Both present the **identical port list and interfaces** (53 ports). One AXI transaction is
in flight at a time; each beat becomes one APB4 transfer on the port its address selects.

## Interfaces

| Interface | Role | Notes |
|---|---|---|
| `S_AXI`  | AXI4 **subordinate** | `ID`, `ADDR`, `LEN`, `SIZE`, `BURST`, `PROT`, `DATA`, `STRB`, `LAST`, `RESP` + handshakes. **Not present:** `AxLOCK`, `AxCACHE`, `AxQOS`, `AxREGION`, `xUSER`; leave them unconnected at the interconnect (D2). No exclusive access, so never `EXOKAY`. |
| `APB0`   | APB4 **requester** | Window `addr[31] == 0`. |
| `APB1`   | APB4 **requester** | Window `addr[31] == 1`. |
| `ACLK`   | clock | Single clock domain for the whole IP. |
| `ARESETn`| reset | Active-low, **asynchronous** assert; release synchronously to `ACLK`. |

## Supported AXI profile (contract D1–D9)

| Field | simple | burst | Anything else |
|---|---|---|---|
| `AxSIZE` | `3'b011` (8 bytes = bus width) | `3'b011` | `DECERR` (narrow transfers unsupported) |
| `AxLEN` | `0` | `0`–`255` | simple: `DECERR` |
| `AxBURST` | ignored (single beat) | `FIXED`, `INCR` | burst: `WRAP` / reserved → `DECERR` |
| `INCR` step | — | `+8` bytes per beat | — |
| Window | `addr[31]` | `addr[31]`; an `INCR` burst whose last beat flips bit 31 → `DECERR` (not split) | — |

`FIXED` bursts longer than 16 beats are accepted, although AXI limits `FIXED` to 16 (D7).

## Arbitration and ordering (D3, D18)

- **One transaction at a time.** A new AW/AR is accepted only when the bridge is idle and no
  response is pending.
- **Write wins.** If an AW (or, on simple, a W) and an AR are both valid, the write goes first.
  `AWREADY` never waits on `ARVALID`, so presenting both together is safe.
- **Reads can be starved:** a manager that always has a write pending delays reads
  indefinitely. See R7.
- Responses carry the request's ID (`BID`/`RID` = `AxID`). With one transaction in flight,
  responses come back in request order.

## Responses and errors (D12–D14, D20)

| Case | Response |
|---|---|
| APB `PSLVERR` on a write beat | Burst completes; one `BRESP = SLVERR` if any beat erred |
| APB `PSLVERR` on a read beat | That beat's `RRESP = SLVERR` |
| Unsupported `AxSIZE` / `AxLEN` / `AxBURST`, or window crossing | `DECERR`, and **no APB transfer** for that transaction |
| Decode-error **write** | Every W beat is accepted (until `WLAST` or `AWLEN + 1` beats), then one `BRESP = DECERR` |
| Decode-error **read** | `ARLEN + 1` beats of `RRESP = DECERR`, `RDATA = 0`, `RLAST` on the last beat |
| burst: early or missing `WLAST` | `SLVERR` (`DECERR` outranks it); the data phase ends on `WLAST` or beat `AWLEN + 1` |

`DECERR` is normally an interconnect response; this IP uses it for unsupported requests by
design (D13).

## What an APB completer sees (D10, D11, D15, D19)

- Standard APB4 SETUP then ACCESS; the transfer completes on `PREADY`. `PADDR`, `PPROT`,
  `PWRITE`, `PWDATA` and `PSTRB` are stable through wait states.
- Only one of `PSEL0` / `PSEL1` is ever asserted.
- `PSTRB` is the beat's `WSTRB` on writes and **all zero on reads**.
- `PPROT` = `AxPROT`, unchanged.
- `PADDR` is the full 32-bit AXI address, `addr[31]` included. Decode the low bits your
  peripheral needs.

## Integration requirements (contract §T0.5)

| ID | Requirement |
|---|---|
| **R3** | All AXI addresses must be **8-byte aligned** (`AxADDR[2:0] == 0`). Unaligned addresses are not checked and go to APB unchanged. |
| **R4** | Bursts must not cross the APB window (`addr[31]`). A crossing gets `DECERR`; it is not split. |
| **R6** | Use only the frozen parameter set (below). |
| **R7** | Reads have lower priority than writes. If read latency matters, don't keep a write always pending. |

## Address map (APB port decode)

`addr[31]` is a fixed APB-port select, giving two 2 GiB windows:

| AXI address range | Routed to |
|---|---|
| `0x0000_0000` – `0x7FFF_FFFF` | `APB0` |
| `0x8000_0000` – `0xFFFF_FFFF` | `APB1` |

The bridge has **no internal control/status registers**: it is a pure protocol bridge, so
there is no CSR RAL. Its only "register map" is this address decode.

## Parameters / configuration matrix (frozen set, D-table in §T0.2)

| Parameter | Frozen value | Notes |
|---|---|---|
| `ADDR_WIDTH`   | 32 | |
| `DATA_WIDTH`   | 64 | `DATA_WIDTH/8 == 8` strobe lanes; other widths unverified |
| `ID_WIDTH`     | 4  | Pass-through only, so other widths are expected to work, but only 4 is verified |
| `APB_ADDR_BIT` | 31 | Exposed as a parameter; other values unverified and unsupported |

## Clock / reset / power

- **Clock:** one domain, `ACLK`. No internal CDC (T1). Constrain with
  `../syn/constraints/axi_apb.sdc` (T2).
- **Reset:** `ARESETn` is async active-low and a false path in the SDC. All `VALID` outputs
  are low in reset (D17). Drive it from the SoC reset controller and de-assert it
  synchronously to `ACLK`.
- **Power:** the T3 power intent (`../syn/lp/axi_apb.upf`) models `PD_AON` (always-on
  control) plus a switchable `PD_APB` (datapath) with isolation and retention. If the SoC does
  not power-gate this IP, tie it into a single always-on domain.

## Example slave: `axi3lite_regblock` (not part of the IP)

The repo's `src/axi3lite_regblock.v` is a demo/test slave, **outside sign-off** (contract
§T0.3). If you use it as a reference, its map is:

| Offset | Register | Access | Reset |
|---|---|---|---|
| `0x00`, `0x04`, … `0x7C` | `REG0` … `REG31` (32 × 32-bit) | RW, `WSTRB` byte enables | `0` |
| ≥ `0x80` | — | `SLVERR` | — |

Its interface is a repo-defined "AXI3-Lite" profile (AXI4-Lite signalling plus AXI3 IDs and
`WID`, where `WID` must equal `AWID`, else `SLVERR`), `DATA_WIDTH = 32` only, with a
synchronous reset.

## Consuming the package

- **IP-XACT** (`ip-xact/axi4_to_apb4_2x_{simple,burst}.xml`): IEEE 1685-2014 components
  with bus interfaces (AXI4 slave, 2× APB4 master, clock, reset), the full model port list,
  the `addr[31]` memory map and the parameter set. Import into an IP-XACT-aware tool (e.g.
  Kactus2, or a vendor packager). Bus interfaces reference the standard AMBA bus and
  abstraction definitions by VLNV, resolved from your AMBA library.
- **RTL** is referenced from each component's `fileSet` (`../../src/<top>.v`).
- **Validate:** `make pkg` checks well-formedness, required structure, and that the model
  ports exactly match the RTL (fails on drift). `make pkg-xsd` adds full XSD validation
  against the IEEE 1685-2014 schema (needs network to fetch it; CI runs it).
- **Release bundle:** `make release` builds `dist/<name>-<version>.tar.gz` with a
  `MANIFEST.json` (file list with SHA-256, the source commit, the contract tag and the gate
  status). See [`RELEASE.md`](RELEASE.md).

## Sign-off cross-reference

See [`../syn/SIGNOFF.md`](../syn/SIGNOFF.md) for the T0–T7 status. Items that need a PDK or a
licensed tool (real STA, SDF-timing GLS, real PPA, scan insertion + ATPG, power-aware sim)
are tagged there and are out of scope for this OSS package.
