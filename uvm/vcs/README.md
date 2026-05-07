# VCS build (`uvm/vcs/`)

| Artifact | Purpose |
|----------|---------|
| `Makefile` | **Authoritative** compile line: sets `UVM_HOME`, `+incdir+` for `pkg`, `env`, `monitors`, `scoreboard`, `transactions`, `interfaces`, RTL path, and per-test sources. |
| `files_*.f` | Example file lists; handy reference but **incomplete** vs Makefile unless you duplicate all include dirs. |

## Targets (from repo `uvm/README.md`)

| `make` target | `-top` module |
|---------------|---------------|
| `sim_simple` | `tb_uvm_simple` |
| `sim_burst` | `tb_uvm_burst` |
| `sim_burst_ext` | `tb_uvm_burst_ext` |
| `sim_simple_ws` | `tb_uvm_simple_ws` (optional `READ_WS=`) |
| `sim_parameterized` | `tb_uvm_parameterized` |

## Include directories (`IFDIR`)

The Makefile adds absolute `+incdir+` paths so `` `include "bridge_axi_monitor.sv" `` inside `bridge_uvm_env_pkg.sv` resolves without relative paths.

```text
../sv/interfaces
../sv/pkg
../sv/env
../sv/monitors
../sv/scoreboard
../sv/transactions
```

Prerequisite: `export UVM_HOME=/path/to/uvm` (must contain `src/uvm.sv`).

Parent: [`../README.md`](../README.md).
