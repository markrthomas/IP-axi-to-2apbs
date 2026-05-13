# IP-axi-to-2apbs

IP AXI to 2× APB4 bridge RTL and self-checking testbenches.

## Directory layout

- `src/` - canonical RTL entrypoints for the bridges
- `test/` - canonical testbench entrypoints
- `uvm/` - UVM-based verification environment (VCS and Xcelium targets)
- `doc/` - documentation

## Design contract

The target behavior for a fully functional bridge is defined in
[`doc/design_contract.md`](doc/design_contract.md). Use that document as the
reference for RTL completion, verification scope, and integration assumptions.

## Xcelium Tutorial

If you have Cadence Xcelium (or are setting it up for the first time), start with
[`doc/xcelium_tutorial.md`](doc/xcelium_tutorial.md).  It covers installation,
`-uvmhome` setup, running all five UVM tests, waveform capture, debugging
techniques, and adding your own test class — all using this bridge as the lab DUT.

## Prerequisites

- [Icarus Verilog](https://github.com/steveicarus/iverilog): `iverilog` and `vvp` on your `PATH`.
- Optional, for waveform viewing: [GTKWave](https://gtkwave.github.io/gtkwave/) on `PATH` (override with `GTKWAVE=/path/to/gtkwave`).

## Quick start

Running **`make`** with no arguments prints **help** with all common targets.

| Goal | Command |
|------|---------|
| Fast regression (simple + burst) | `make test` or `make test-all` |
| Every simulator TB (except wait-state sweep) | `make test-full` |
| Lint + fast regression | `make check` |
| Lint + full TB set | `make check-full` |
| Build one simulator executable | `make sim WAVETB=simple` (see `make help`) |
| Dump FST/VCD without opening viewer | `make wave` or `make wave-simple` … |
| Run sim and open GTKWave | `make gtk` or `make gtk-simple` … |

Individual tests still map to **`make test-simple`**, **`make test-burst`**, **`make test-burst-ext`**, **`make test-param`**, **`make test-simple-ws`**.

## Build and test (detail)

From the repo root:

| Target | Description |
|--------|-------------|
| `make test` | Same as **`test-all`**. |
| `make test-all` | Simple + burst TBs. |
| `make test-full` | All TBs except **`test-simple-ws-sweep`**. |
| `make check` | **`lint`** then **`test-all`**. |
| `make check-full` | **`lint`** then **`test-full`**. |
| `make test-simple` | Simple bridge (`axi4_to_apb4_2x_simple`) with default simple TB. |
| `make test-burst` | Burst bridge (`axi4_to_apb4_2x_burst`) TB. |
| `make test-burst-ext` | Extended / repro scenarios (`tb_axi4_to_apb4_2x_burst_extended.v`, top `tb_repro_issues`). |
| `make test-param` | Parameterized APB decode / width corner (`tb_parameterized_config.v`). |
| `make test-simple-ws` | Simple bridge with configurable APB read wait-states (see below). |
| `make test-simple-ws-sweep` | Runs `test-simple-ws` with `WAIT_CYCLES` 1, 2, and 3. |
| `make sim` | Builds the simulator for **`WAVETB`** (`simple`, `burst`, `burst-ext`, `simple-ws`, `param`). |
| `make lint` | Compiles all TBs with `-Wall` (no simulation run). |
| `make clean` | Removes generated simulator binaries and default waveform outputs. |

### Waveforms (VCD / FST)

With [Icarus `vvp`](https://steveicarus.github.io/iverilog/usage/waveform_viewer.html), dumps are enabled with **`+wave`**. For **FST** (compact, good for GTKWave), use a **`.fst` filename** and pass **`-fst`** as an extended argument **after** the compiled simulator name (some toolchains mis-parse **`-fst`** if it appears before the binary):

```bash
make wave                          # WAVETB=simple → waves_simple.fst
make wave WAVETB=burst
make wave WAVETB=simple-ws WAIT_CYCLES=1
make wave-simple WAVEFMT=vcd       # waves_simple.vcd, no -fst
```

Override the output file with **`WAVEFILE=path`**.

### GTKWave (simulate + viewer)

```bash
make gtk                           # default bench: simple
make gtk WAVETB=burst
make gtk-simple | gtk-burst | gtk-burst-ext | gtk-simple-ws | gtk-param
```

The **`gtk-*`** targets run the matching simulation with **`+wave`**, then start **`$(GTKWAVE)`** in the background. Set **`GTKWAVE_FLAGS`** for extra viewer flags if needed.

### APB read wait-state depth (`WAIT_CYCLES`)

The wait-state testbench `tb_axi4_to_apb4_2x_simple_ws.v` uses the compile-time macro `READ_WAIT_CYCLES`. The Makefile passes it from the variable `WAIT_CYCLES` (default `2`).

Examples:

```bash
make test-simple-ws                    # uses WAIT_CYCLES=2
make test-simple-ws WAIT_CYCLES=1    # one-cycle read stall pattern
make test-simple-ws-sweep            # runs 1, 2, and 3
```

Generated executables and simulation traces are listed in `.gitignore` and should not be committed.
