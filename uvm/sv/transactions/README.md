# Transactions (`uvm/sv/transactions/`)

| File | Contents |
|------|----------|
| `bridge_transactions.sv` | UVM sequence items for AXI writes, AXI reads, and APB beats; also `bridge_decode_kind_e` (`SIMPLE` vs `BURST`) used by the scoreboard and cfg. |

## Class summary

| Class | Typical use |
|-------|-------------|
| `bridge_axi_wr_tr` | Monitor → scoreboard for write bursts (addr, len, size, burst, strobes, data array, `bresp`). |
| `bridge_axi_rd_tr` | Monitor → scoreboard for read bursts (`rdata` array, `rresp`). |
| `bridge_apb_tr` | Per-beat APB observation (port index, addr, write/read, data, strb, `pslverr`). |

Parent: [`../README.md`](../README.md).
