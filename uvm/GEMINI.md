# UVM Development & Extension Guide

This document provides technical details for developers looking to extend or debug the UVM environment.

## Adding a New Test

To add a new test case:

1.  **Define a new test class** in `uvm/sv/pkg/bridge_uvm_tests_pkg.sv` (or a new file included in that package).
    - Inherit from **`bridge_base_test #(DW)`** (where `DW` is 32 or 64).
    - Override **`configure_env()`** to tune `env_cfg` (e.g., set `apb_sel_bit`, `decode_kind`).
    - Implement the stimulus in `run_phase`.
2.  **Create a new top-level TB** in `uvm/tb/` if needed (e.g., `tb_uvm_new_feature.sv`).
    - Instantiate the DUT and interfaces.
    - Call `run_test()`.
3.  **Add a `.f` file** in `uvm/vcs/` (e.g., `files_new_feature.f`) listing all required files.
4.  **Update the Makefile** in `uvm/vcs/Makefile` to include a new simulation target.

## Extending the Stimulus

Stimulus is currently managed in `bridge_stimulus_pkg.sv` using helper classes like `bridge_axi_stim_64`. While not a pure UVM sequence-based approach, it allows for easy mirroring of the RTL testbenches.

To transition to UVM sequences:
1.  Add a `bridge_axi_sequencer` and `bridge_axi_driver` to the `axi_monitor` (converting it into a full UVC).
2.  Define `uvm_sequence` items for AXI transactions.

## Scoreboard Deep Dive

The `bridge_scoreboard` is the heart of the verification. It uses TLM imp ports to receive transactions from the AXI and APB monitors.

### DECERR Prediction
The bridge variants handle illegal transactions differently. The scoreboard uses `bridge_aw_txn_decerr` and `bridge_ar_txn_decerr` to match the RTL's internal error decoding logic.
- **SIMPLE variant:** Any burst (`len > 0`) or incorrect `axsize` results in `DECERR`.
- **BURST variant:** Bursts that cross the `apb_sel_bit` boundary, or have unsupported burst types (e.g., WRAP), result in `DECERR`.

### Shadow RAM
The shadow RAM is implemented as an associative array: `logic [63:0] slv_shadow[int unsigned]`.
- The key is generated using `ram_key_of(port_ix, paddr)`.
- Writes are committed when a successful APB write completion is observed.
- Reads are checked against the shadow RAM at the APB level (when observed by the monitor) and at the AXI level (when the full transaction completes).

## Debugging Mismatches

When the scoreboard reports a mismatch:
1.  **Check the logs for `UVM_ERROR`** messages from the scoreboard. They usually indicate whether it was an address, data, or metadata (port/pwrite) mismatch.
2.  **Enable `UVM_HIGH` verbosity** to see every predicted and observed beat.
3.  **Check the observation queues** reported in the `report_phase`. Outstanding items in `pred_wr` or `buf_wr_obs` indicate missing completions or ordering issues.
4.  **Trace the `apb_sel_bit`:** Ensure the TB and DUT agree on which address bit selects the APB port.

## Linting & Quality

Always run `make lint-uvm-sv` before committing. The UVM environment is linted with Verilator in strict mode to ensure high-quality SystemVerilog code.
