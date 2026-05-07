# Verilator lint shims (`uvm/lint/`)

Small wrapper modules or packages that satisfy Verilator when linting UVM-adjacent SystemVerilog that references interfaces or packages in specific ways.

| File | Role |
|------|------|
| `vlint_shim_axi4_master_if.sv` | Shim for AXI interface lint. |
| `vlint_shim_apb_mon_if.sv` | Shim for APB monitor interface. |
| `vlint_shim_apb_burst_ext_side_if.sv` | Extended burst side interface. |
| `vlint_shim_apb_sel_tracker_if.sv` | PSEL tracker interface. |
| `vlint_shim_bridge_stimulus_pkg.sv` | Stimulus package lint entry. |

Invoked from repo root via `make lint-uvm-sv` / `make lint-uvm-sv-relaxed` (see root `Makefile` and [`../README.md`](../README.md)).

Parent: [`../README.md`](../README.md).
