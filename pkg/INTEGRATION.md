# Integration guide — AXI4 → 2× APB4 bridge

Tapeout-readiness program **T7** (integration / packaging) deliverable, stood up on the
flow pathfinder. This guide + the IP-XACT in `ip-xact/` are what an SoC integrator needs
to instance the IP. All interface facts here are the frozen contract in
[`../doc/design_contract.md`](../doc/design_contract.md); the IP-XACT port list is kept in
sync with the RTL by `make pkg`.

## IP variants

| Top (module / IP-XACT name) | Use when |
|---|---|
| `axi4_to_apb4_2x_simple` | Single-beat AXI transactions (`AxLEN == 0`); APB0/APB1 routing + APB wait-states. |
| `axi4_to_apb4_2x_burst`  | Restricted AXI bursts (superset); parameter checks for size / burst type / `addr[31]` crossing. |

Both present the **identical port list and interfaces** (53 ports); they differ only in
burst handling. One AXI transaction is serialized at a time into APB4 transfers.

## Interfaces

| Interface | Role | Notes |
|---|---|---|
| `S_AXI`  | AXI4 **subordinate** (slave) | Full AXI4; `ID_WIDTH` preserved through responses. |
| `APB0`   | APB4 **initiator** (master) | Target window `addr[31]==0`. |
| `APB1`   | APB4 **initiator** (master) | Target window `addr[31]==1`. |
| `ACLK`   | clock | Single clock domain (whole IP). |
| `ARESETn`| reset | Active-low, **asynchronous** assert / synchronous-safe release. |

## Clock / reset / power

- **Clock:** one domain, `ACLK`. No internal CDC (pinned at T1 / T1-CDC). Constrain with
  `../syn/constraints/axi_apb.sdc` (T2).
- **Reset:** `ARESETn` async active-low; treated as a false path in the SDC. Drive it
  from the SoC reset controller; de-assert synchronously to `ACLK` at the integrator.
- **Power:** the T3 power intent (`../syn/lp/axi_apb.upf`) models `PD_AON` (always-on
  control) + a switchable `PD_APB` (datapath) with isolation + retention. If the SoC does
  not power-gate this IP, tie it into a single always-on domain.

## Address map (APB port decode)

`addr[31]` is a fixed APB-port select, giving two 2 GiB windows:

| AXI address range | Routed to |
|---|---|
| `0x0000_0000` – `0x7FFF_FFFF` | `APB0` |
| `0x8000_0000` – `0xFFFF_FFFF` | `APB1` |

An `INCR` burst whose beats cross `addr[31]` is rejected with `DECERR` (`FIXED` bursts
cannot cross). The bridge has **no internal control/status registers** — it is a pure
protocol bridge, so there is no CSR RAL to generate; the "register map" is this address
decode. (The repo's `axi3lite_regblock` is a separate *example slave*, not part of the
bridge.)

## Parameters / configuration matrix

| Parameter | Default | Contract | Meaning |
|---|---|---|---|
| `ID_WIDTH`     | 4  | may vary; preserved through responses | AXI ID width |
| `ADDR_WIDTH`   | 32 | **fixed at 32** (current contract) | AXI/APB address width |
| `DATA_WIDTH`   | 64 | **fixed at 64** (`DATA_WIDTH/8 == 8`) | AXI/APB data width |
| `APB_ADDR_BIT` | 31 | fixed | address bit that selects APB0 vs APB1 |

Until configurable address-decode / data-width work lands, integrations should treat
non-32-bit address or non-64-bit data configurations as **unsupported** (per the contract).

## Consuming the package

- **IP-XACT** (`ip-xact/axi4_to_apb4_2x_{simple,burst}.xml`): IEEE 1685-2014 components —
  bus interfaces (AXI4 slave, 2× APB4 master, clock, reset), the full model port list, the
  `addr[31]` memory map, and the parameter set. Import into your IP-XACT-aware integration
  tool (e.g. Kactus2, or a vendor packager); bus interfaces reference the standard AMBA
  bus/abstraction definitions by VLNV, resolved from your AMBA library.
- **RTL** source is referenced from each component's `fileSet` (`../../src/<top>.v`).
- **Validate** the package with `make pkg` (`pkg/check_ipxact.sh`): XML well-formedness +
  required-element structure + a hard check that the IP-XACT model ports exactly match the
  RTL (fails on drift). Optional full XSD validation: `IPXACT_XSD=/path/to/index.xsd make pkg`.

## Sign-off cross-reference

See [`../syn/SIGNOFF.md`](../syn/SIGNOFF.md) for the T0–T7 status. Items needing a PDK or a
licensed tool (real STA, SDF-timing GLS, real PPA, scan insertion + ATPG, power-aware sim)
are tagged there and are out of scope for this OSS package.
