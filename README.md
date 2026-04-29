# IP-axi-to-2apbs

IP AXI to 2× APB4 bridge RTL and self-checking testbenches.

## Directory layout

- `src/` - canonical RTL entrypoints for the bridges
- `test/` - canonical testbench entrypoints
- `doc/` - documentation

## Design contract

The target behavior for a fully functional bridge is defined in
[`doc/design_contract.md`](doc/design_contract.md). Use that document as the
reference for RTL completion, verification scope, and integration assumptions.

## Prerequisites

- [Icarus Verilog](https://github.com/steveicarus/iverilog): `iverilog` and `vvp` on your `PATH`.

## Build and test

From the repo root:

| Target | Description |
|--------|-------------|
| `make test-simple` | Simple bridge (`axi4_to_apb4_2x_simple`) with default simple TB. |
| `make test-burst` | Burst bridge (`axi4_to_apb4_2x_burst`) TB. |
| `make test-all` | Runs `test-simple` and `test-burst`. |
| `make test-simple-ws` | Simple bridge with configurable APB read wait-states (see below). |
| `make test-simple-ws-sweep` | Runs `test-simple-ws` with `WAIT_CYCLES` 1, 2, and 3. |
| `make lint` | Compiles all TBs with `-Wall` (no simulation run). |
| `make clean` | Removes generated simulator binaries (`sim_simple`, `sim_burst`, `sim_simple_ws_*`). |

### APB read wait-state depth (`WAIT_CYCLES`)

The wait-state testbench `tb_axi4_to_apb4_2x_simple_ws.v` uses the compile-time macro `READ_WAIT_CYCLES`. The Makefile passes it from the variable `WAIT_CYCLES` (default `2`).

Examples:

```bash
make test-simple-ws                    # uses WAIT_CYCLES=2
make test-simple-ws WAIT_CYCLES=1    # one-cycle read stall pattern
make test-simple-ws-sweep            # runs 1, 2, and 3
```

Generated executables are listed in `.gitignore` and should not be committed.
