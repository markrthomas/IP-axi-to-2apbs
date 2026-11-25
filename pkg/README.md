# pkg/ — IP packaging (tapeout-readiness T7)

Packaging deliverables for the AXI4 → 2× APB4 bridge, so an SoC integrator can instance
the IP. This block is the program's flow pathfinder: the packaging template here is
promoted to the shared sign-off kit, then instantiated on the sibling IPs.

## Contents

| Path | What |
|---|---|
| `ip-xact/axi4_to_apb4_2x_simple.xml` | IP-XACT (IEEE 1685-2014) component — single-beat variant. |
| `ip-xact/axi4_to_apb4_2x_burst.xml`  | IP-XACT component — restricted-burst variant (superset). |
| `INTEGRATION.md` | Integration guide: interfaces, clock/reset/power, address map, parameter/config matrix, how to consume. |
| `check_ipxact.sh` | The `make pkg` gate: well-formedness + structure + IP-XACT↔RTL port-sync. |

## Run the gate

```
make pkg          # xmllint well-formed + structural + model-ports-match-RTL
IPXACT_XSD=/path/to/1685-2014/index.xsd make pkg   # + full XSD schema validation
```

`make pkg` is wired into CI (the `synth` job) and fails on any drift between the IP-XACT
model ports and the RTL — so the package cannot silently fall out of sync with the design.

## Scope

This is the OSS, no-PDK packaging layer. Real-silicon collateral that needs a PDK or a
licensed tool (timing/STA, SDF-timing GLS, real PPA, scan/ATPG, power-aware sim) is tracked
and tagged in [`../syn/SIGNOFF.md`](../syn/SIGNOFF.md), not duplicated here.
