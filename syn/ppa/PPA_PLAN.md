# PPA plan (IP-axi-to-2apbs)

PPA is part of the T6 sign-off. The full plan — what runs OSS here (the
technology-independent proxy baseline, `make ppa`) and what is deferred as
`needs-pdk` (real area in µm², power in mW, and timing in ns via a standard-cell
library + OpenROAD/OpenSTA or PrimeTime/PrimePower) — lives in
[`../gls/T6_PLAN.md`](../gls/T6_PLAN.md).

`make ppa` emits, per top, to `syn/ppa/reports/<top>.ppa.rpt`:
- **area proxy** — generic cell count + flip-flop count (post-synth, flattened);
- **timing proxy** — longest topological logic path (`ltp`), i.e. combinational depth.

These are tracked baselines that move monotonically with the real post-PDK numbers.
