# Xcelium build (`uvm/xcelium/`)

| Artifact | Purpose |
|----------|---------|
| `Makefile` | **Authoritative** compile+run line: sets `UVM_HOME`, `-uvmhome`, `+incdir+` for `pkg`, `env`, `monitors`, `scoreboard`, `transactions`, `interfaces`, RTL path, and per-test sources. |
| `files_*.f` | Convenience file lists for direct `xrun -f` invocation; pass `-uvmhome`, `-64bit -sv -timescale` etc. on the command line (tool flags are not in the `.f` files). |

## Quick start

```bash
export UVM_HOME=/path/to/uvm        # must contain src/uvm.sv
# or: export UVM_HOME=CDNS          # use Xcelium's bundled UVM
cd uvm/xcelium
make sim_simple
```

`xrun` compiles and runs in one step; output goes to `sim_simple.log`.

New to Xcelium?  See [`../../doc/xcelium_tutorial.md`](../../doc/xcelium_tutorial.md)
for a step-by-step guide covering installation, `-uvmhome` options, all five
targets, waveform capture, and how to add your own test.

## Targets

| `make` target | `-top` module | DUT RTL | Test class |
|---------------|---------------|---------|------------|
| `sim_simple` | `tb_uvm_simple` | `axi4_to_apb4_2x_simple` | `test_bridge_simple` |
| `sim_burst` | `tb_uvm_burst` | `axi4_to_apb4_2x_burst` | `test_bridge_burst` |
| `sim_burst_ext` | `tb_uvm_burst_ext` | `axi4_to_apb4_2x_burst` | `test_bridge_burst_ext` |
| `sim_simple_ws` | `tb_uvm_simple_ws` | `axi4_to_apb4_2x_simple` | `test_bridge_simple_ws` |
| `sim_parameterized` | `tb_uvm_parameterized` | `axi4_to_apb4_2x_burst` | `test_bridge_parameterized_cfg` |

### `sim_simple_ws` — wait-state depth

Pass `READ_WS=N` to override the default APB read wait-state count (default: 2):

```bash
make sim_simple_ws READ_WS=3
```

This sets `+define+BRIDGE_READ_WS=3`, which `apb_dual_mem_ws.sv` uses to insert N wait cycles.

## Include directories (`IFDIR`)

The Makefile adds absolute `+incdir+` paths so `` `include "bridge_axi_monitor.sv" `` inside `bridge_uvm_env_pkg.sv` resolves without relative paths:

```text
../sv/interfaces
../sv/pkg
../sv/env
../sv/monitors
../sv/scoreboard
../sv/transactions
```

## Key differences from VCS

| Aspect | VCS (`uvm/vcs/`) | Xcelium (`uvm/xcelium/`) |
|--------|------------------|--------------------------|
| Tool | `vcs` (compile) → `./simv` (run) | `xrun` (unified compile+run) |
| 64-bit | `-full64` | `-64bit` |
| SV mode | `-sverilog` | `-sv` |
| Debug access | `+acc +vpi` | `-access +rwc` |
| UVM hook-in | `+incdir+$(UVM_HOME)/src $(UVM_HOME)/src/uvm.sv` | `-uvmhome $(UVM_HOME)` |
| Log | separate `./simv -l sim.log` invocation | `-log sim.log` inline in `xrun` call |
| Clean artifacts | `csrc/ simv.daidir/ DVEfiles/` | `xcelium.d/ INCA_libs/ *.shm` |

`-uvmhome` is the Xcelium-native way to point at a UVM installation; it registers UVM packages, sets the include path, and links the DPI layer automatically — no need to pass `uvm.sv` as a source file.

## `.f` file lists

The five `files_*.f` lists parallel those in `uvm/vcs/` but omit UVM source lines (handled by `-uvmhome`) and tool flags.  They are useful for ad-hoc invocations:

```bash
xrun -64bit -sv -timescale 1ns/1ps -access +rwc \
     -uvmhome $UVM_HOME \
     +incdir+../sv/pkg \
     +incdir+../sv/env \
     +incdir+../sv/monitors \
     +incdir+../sv/scoreboard \
     +incdir+../sv/transactions \
     -f files_simple.f \
     -top tb_uvm_simple \
     -log sim_simple.log
```

The Makefile already supplies all of the above; prefer `make` over a raw `xrun -f` invocation.

## Build artifacts and `make clean`

| Path | Created by |
|------|-----------|
| `xcelium.d/` | `xrun` compilation database |
| `INCA_libs/` | Older Xcelium tool library cache |
| `*.shm` | Waveform databases (if `-shm` probe is added) |
| `*.log` | Per-target simulation logs |

`make clean` removes all of the above.

Prerequisite: `export UVM_HOME=/path/to/uvm` (must contain `src/uvm.sv`).

Parent: [`../README.md`](../README.md).
