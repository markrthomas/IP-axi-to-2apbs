# UVM + VCS benches (mirror of `test/`)

This tree mirrors every Icarus Verilog RTL testbench in `test/` with SystemVerilog
interfaces, shared stimulus in `bridge_stimulus_pkg`, and thin UVM `uvm_test`
classes in `bridge_uvm_tests_pkg`. Synopsys VCS is the primary target.

## Layout

| Icarus test | UVM top | Test class |
|-------------|---------|------------|
| `tb_axi4_to_apb4_2x_simple` | `tb_uvm_simple` | `test_bridge_simple` |
| `tb_axi4_to_apb4_2x_burst` | `tb_uvm_burst` | `test_bridge_burst` |
| `tb_axi4_to_apb4_2x_burst_extended` (`tb_repro_issues`) | `tb_uvm_burst_ext` | `test_bridge_burst_ext` |
| `tb_axi4_to_apb4_2x_simple_ws` | `tb_uvm_simple_ws` | `test_bridge_simple_ws` |
| `tb_parameterized_config` | `tb_uvm_parameterized` | `test_bridge_parameterized_cfg` |

`tb_uvm_simple_ws` takes `READ_WS` (default 2) to match `READ_WAIT_CYCLES` in the Makefile flow.

Without Synopsys VCS, keep this tree aligned with the reference benches in `test/` by running
from the repo root: **`make check-uvm-mirror`** (curated literals via `scripts/uvm_mirror_check.py`)
and **`make lint-uvm-sv`** (strict Verilator: `scripts/verilator_lint_uvm_strict.sh`, `-Wall`, one top per compile).
Use **`make lint-uvm-sv-relaxed`** for a faster single-pass elaboration with broad warning waivers.

## Verification environment (`bridge_uvm_env_pkg`)

Each test builds a **`bridge_env`**: passive **AXI monitor** (`bridge_axi_monitor`), two **APB monitors**
(`bridge_apb_monitor` driven by **`apb_mon_if`** on each bus), and a **scoreboard** that predicts:

- APB beat addresses (**INCR** / **FIXED** expansion from **`awsize` / `arsize`**), routed port from **`bridge_env_cfg::apb_sel_bit`**
  (RTL **`APB_ADDR_BIT`**)
- **`bridge_env_cfg::decode_kind`**: **`BRIDGE_DECODE_SIMPLE`** vs **`BRIDGE_DECODE_BURST`** so illegal bursts (wrong
  **`axsize`**, SIMPLE non-single bursts, burst WRAP, INCR crossings of the APB select bit path) predict **DECERR**
  (**`BRESP` / `RRESP` = 2'h3**) instead of implying APB completes
- A **dual-port shadow RAM** (word index **`PADDR[apb_mem_addr_msb:apb_mem_addr_lsb]`**, default **`[9:2]`** matching
  `apb_dual_mem_*`; **`tb_uvm_burst_ext`** uses **`[12:3]`** like **`apb_ext_mem_dual`**) to check **reads** (**`PRDATA`** vs shadow,
  and **AXI `RDATA`** vs shadow on complete transactions)
- Observation **queues** reconcile whether APB completions or completed AXI transactions arrive first through the monitor TLM ports

Configure via **`bridge_env_cfg`** (fields above). Set **`has_scoreboard`** to turn off the scoreboard while leaving monitors active.

**Sequence items** used by monitors / scoreboard: **`bridge_axi_wr_tr`**, **`bridge_axi_rd_tr`**, **`bridge_apb_tr`**.

Compile order (if you edit `files_*.f`): UVM -> SV interfaces -> **`apb_mon_if.sv`** -> APB memory models -> RTL
`../../src/*.v` -> `bridge_stimulus_pkg.sv` -> **`bridge_uvm_env_pkg.sv`** -> **`bridge_uvm_tests_pkg.sv`** -> TB top.

## Build

Set `UVM_HOME` so `$UVM_HOME/src/uvm.sv` exists. From `uvm/vcs/`:

```bash
export UVM_HOME=/path/to/uvm
make sim_simple
```

For the wait-state APB model depth (matches `WAIT_CYCLES` / `READ_WAIT_CYCLES` in the Makefile Icarus flow):

```bash
make sim_simple_ws READ_WS=2
```

`READ_WS` is passed as ``+define+BRIDGE_READ_WS=$(READ_WS)`` to `tb_uvm_simple_ws.sv`.

Targets: `sim_simple`, `sim_burst`, `sim_burst_ext`, `sim_simple_ws`, `sim_parameterized`.
