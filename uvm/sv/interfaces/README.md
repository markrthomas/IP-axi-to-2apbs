# Interfaces (`uvm/sv/interfaces/`)

| File | Interface | Role |
|------|-----------|------|
| `axi4_master_if.sv` | Parameterized AXI4 **slave-side** signals (DUT is AXI slave from the TB master). |
| `apb_mon_if.sv` | Passive APB bundle for monitors (each APB port). |
| `apb_burst_ext_side_if.sv` | Sideband / extended burst test support. |
| `apb_sel_tracker_if.sv` | Tracks PSEL for parameterized decode tests. |

Virtual interface types are typedef’d in the testbench tops and passed through `uvm_config_db` to monitors and stimulus.

Parent: [`../README.md`](../README.md).
