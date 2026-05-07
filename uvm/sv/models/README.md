# APB models (`uvm/sv/models/`)

Behavioral dual-port APB slaves backing the DUT’s two APB masters. Picked per testbench top / `files_*.f` / Makefile.

| Model | Typical TB | Notes |
|-------|------------|-------|
| `apb_dual_mem_simple.sv` | `tb_uvm_simple` | Baseline memory. |
| `apb_dual_mem_burst.sv` | `tb_uvm_burst` | Tuned for burst traffic. |
| `apb_dual_mem_ws.sv` | `tb_uvm_simple_ws` | Configurable read wait-states (`READ_WS` / `BRIDGE_READ_WS`). |
| `apb_dual_mem_param.sv` | parameterized | Width/addr corner cases. |
| `apb_ext_mem_dual.sv` | `tb_uvm_burst_ext` | Larger address space for extended scenarios. |

The scoreboard’s shadow RAM is **independent** of these models; it learns expected memory content from observed successful APB writes.

Parent: [`../README.md`](../README.md).
