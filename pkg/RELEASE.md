# Releasing the IP (tapeout-readiness T7)

How a versioned release of the AXI4 → 2× APB4 bridge is cut. This block is the program's
flow pathfinder, so this procedure and `scripts/make_release.py` are the template the
sibling IPs copy.

## Versioning

- **IP release:** semantic version `vMAJOR.MINOR.PATCH` (git tag `v1.0.0`, …).
  - MAJOR: an interface or behaviour change, which always comes with a new design-contract
    version and tag.
  - MINOR: compatible additions (new collateral, new configurations).
  - PATCH: fixes that keep the contract.
- **Design contract:** its own tag (`contract-v1.0`). Every IP release records the contract
  it implements in `MANIFEST.json`. `v1.0.0` implements contract `1.0`.

## What a release contains

`make release VERSION=x.y.z` builds `dist/axi4-to-2apbs-x.y.z.tar.gz` (plus a `.sha256`).
The bundle holds:

| Kind | Files |
|---|---|
| `rtl` | `src/axi4_to_apb4_2x_{simple,burst}.v` |
| `rtl-example` | `src/axi3lite_regblock.v` (example slave, outside sign-off) |
| `ip-xact` | `pkg/ip-xact/*.xml` (IEEE 1685-2014, XSD-validated) |
| `contract` | `doc/design_contract.md` |
| `signoff` | `syn/SIGNOFF.md` |
| `constraints`, `power-intent`, `plan` | SDC, OpenSTA script, UPF, LP/DFT/T6 plans |
| `doc`, `license` | integration guide, package README, this file, top-level README, LICENSE |
| `gate-report` | every `syn/**/reports/*` present at build time (synth, scan, GLS, PPA) |
| — | `MANIFEST.json` |

`MANIFEST.json` records:
- the SHA-256 and size of every file;
- the source commit, and whether the tree was dirty;
- the contract tag and version;
- the T0–T7 gate status, parsed from `syn/SIGNOFF.md`;
- the tool versions used.

The tarball is deterministic: sorted entries, and every timestamp set to the commit time.
Rebuilding the same commit with the same reports gives the same bytes.

## Procedure

1. `main` is green in CI: CI, UVM on Verilator, Docker plumbing.
2. Regenerate the gate reports and run the gates:
   `make syn dft lp gls ppa pkg pkg-xsd test-compliance`.
3. Build and check the bundle: `make release VERSION=1.0.0`, then `make release-verify VERSION=1.0.0`.
   CI runs the same build and verify on every push (`release-bundle` artifact).
4. Tag and publish (owner):
   ```
   git tag -a v1.0.0 -m "IP release 1.0.0 (contract 1.0)"
   git push https://github.com/markrthomas/IP-axi-to-2apbs.git v1.0.0
   gh release create v1.0.0 dist/axi4-to-2apbs-1.0.0.tar.gz dist/axi4-to-2apbs-1.0.0.tar.gz.sha256 \
     --title "v1.0.0" --notes-file pkg/RELEASE_NOTES.md
   ```
5. Sign the gates in `syn/SIGNOFF.md` (artifact path, pass date, reviewer), citing the
   release bundle as the archived artifact.

## Scope

This is the OSS, no-PDK release. A bundle contains the generated gate reports so that each
sign-off row has an archived artifact. Items that need a PDK or a licensed tool are tagged
in `syn/SIGNOFF.md`; they are not part of this release.
