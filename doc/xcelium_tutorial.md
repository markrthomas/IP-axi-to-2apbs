# Xcelium UVM Tutorial: Verifying an AXI-to-APB Bridge

This tutorial uses the AXI-to-2APB bridge in this repository as a concrete
lab vehicle for learning Cadence Xcelium and UVM simulation.  Every command
shown here runs against real RTL and a real UVM environment; nothing is
contrived.

**What you will learn**

- How Xcelium compiles and simulates SystemVerilog in a single pass.
- How `-uvmhome` wires in the UVM library without manual source management.
- The structure of a UVM environment: interfaces, monitors, scoreboard, test.
- How to read xrun output, correlate it to UVM phases, and interpret pass/fail.
- How to capture waveforms and debug mismatches.
- How to add your own test class and stimulus task.

**Prerequisites**

- A working Xcelium installation (`xrun` on your `PATH`).
- A UVM installation or Xcelium's bundled UVM (see Section 2).
- Basic SystemVerilog and AXI/APB familiarity.

---

## 1. What Is Xcelium?

Xcelium is Cadence's simulation platform for SystemVerilog/VHDL/UVM.  Its
front-end binary is `xrun`, which replaces the older `irun` and `ncverilog`
wrappers.  `xrun` handles compilation, elaboration, and simulation in a single
invocation — unlike Synopsys VCS, which separates `vcs` (compile) from `./simv`
(run).

```
VCS workflow:    vcs  [flags]  [files]  -o simv
                 ./simv  [plusargs]

Xcelium workflow: xrun  [flags]  [files]  [plusargs]
```

The single-step approach simplifies Makefiles and shortens the debug loop:
edit a file, re-run `xrun`, see results — no separate link step.

### 1.1 How to Get Xcelium

Xcelium is a commercial tool distributed by Cadence Design Systems.  Common
access paths:

| Path | Notes |
|------|-------|
| Company license server | Most common in industry; your EDA admin sets `CDS_LIC_FILE`. |
| University / academic license | Cadence Academic Network; contact your institution. |
| EDA cloud (AWS, Azure, GCP) | Pre-installed on Cadence cloud instances; no local install needed. |
| Cadence Cloud Personal License | Available for individual engineers via Cadence; check the Cadence website. |

After installation, verify it works:

```bash
xrun -version
```

You should see a version string like `XCELIUM24.03 ...`.

### 1.2 License Environment Variables

Xcelium uses FlexLM.  The license server is pointed to by one of:

```bash
export CDS_LIC_FILE=5280@license-server.example.com
# or the generic FlexLM variable:
export LM_LICENSE_FILE=5280@license-server.example.com
```

If `xrun -version` succeeds but a simulation fails with `Error: license
checkout failed`, the feature name in your license file may differ from what
the version of Xcelium expects.  Contact your license administrator.

---

## 2. UVM Setup

UVM (Universal Verification Methodology) is a SystemVerilog class library for
building reusable verification environments.  Xcelium supports two ways to
bring it in.

### 2.1 Bundled UVM: `-uvmhome CDNS`

Xcelium ships with its own validated UVM installation.  Pass `-uvmhome CDNS`
and Xcelium automatically:

- Adds the correct `+incdir+` for `uvm_macros.svh`.
- Compiles `uvm_pkg` and links the DPI C layer.
- Sets `UVM_HOME` internally.

You do **not** need to export `UVM_HOME` when using `-uvmhome CDNS`.

```bash
xrun -64bit -sv -timescale 1ns/1ps -access +rwc \
     -uvmhome CDNS \
     my_tb.sv -top my_tb
```

The Makefile in `uvm/xcelium/` passes `-uvmhome $(UVM_HOME)`, so set
`UVM_HOME` to the string `CDNS` to use the bundled version:

```bash
export UVM_HOME=CDNS
make sim_simple
```

### 2.2 External UVM: explicit path

If your organization maintains a specific UVM version (for stability or audit
reasons), download UVM 1.2 from Accellera (`accellera.org`) and point
`-uvmhome` at the unpacked tree:

```bash
export UVM_HOME=/opt/uvm-1.2
# Verify the expected file exists:
ls $UVM_HOME/src/uvm.sv
make sim_simple
```

The Makefile checks that `UVM_HOME` is set and contains `src/uvm.sv`.
If it is wrong you will see:

```
Error: Set UVM_HOME (directory containing src/uvm.sv)
```

---

## 3. Repository Layout

```
IP-axi-to-2apbs/
+-- src/                     RTL: axi4_to_apb4_2x_simple.v, _burst.v
+-- test/                    Icarus Verilog reference testbenches
+-- uvm/
|   +-- sv/                  UVM source (packages, monitors, scoreboard)
|   |   +-- interfaces/      SV interfaces (axi4_master_if, apb_mon_if, ...)
|   |   +-- pkg/             bridge_stimulus_pkg, bridge_uvm_env_pkg, bridge_uvm_tests_pkg
|   |   +-- env/             bridge_env, bridge_env_cfg
|   |   +-- monitors/        bridge_axi_monitor, bridge_apb_monitor
|   |   +-- scoreboard/      bridge_scoreboard
|   |   +-- transactions/    bridge_axi_wr_tr, bridge_axi_rd_tr, bridge_apb_tr
|   |   +-- models/          APB slave behavioral memories
|   +-- tb/                  Top-level SV modules (tb_uvm_simple.sv, ...)
|   +-- xcelium/             Makefile + .f file lists  <-- you are here
|   +-- vcs/                 Makefile + .f file lists (Synopsys VCS)
+-- doc/                     Design contract, plan, this tutorial
```

The DUT is one of two RTL files in `src/`.  Every UVM test exercises the
same RTL through an AXI4 interface, through the bridge, and out to one of
two APB4 ports backed by a behavioral memory model.

---

## 4. Your First Simulation

### Step 1 — Set UVM_HOME

```bash
export UVM_HOME=CDNS           # use Xcelium bundled UVM
# or:
export UVM_HOME=/opt/uvm-1.2  # use an external install
```

### Step 2 — Enter the Xcelium directory and build

```bash
cd uvm/xcelium
make sim_simple
```

### Step 3 — Read the output

A successful run prints something like:

```
xrun  ...flags...  -top tb_uvm_simple  -log sim_simple.log
...
UVM_INFO @ 0: reporter [RNTST] Running test test_bridge_simple...
UVM_INFO uvm/sv/pkg/bridge_uvm_tests_pkg.sv(70) @ 210: ...
UVM_INFO uvm/sv/pkg/bridge_stimulus_pkg.sv(287) @ ...: SIMPLE TEST PASSED
UVM_INFO uvm/sv/scoreboard/bridge_scoreboard.sv(292) @ ...:
  SB summary: axi_wr=2 axi_rd=2 apb0=1 apb1=1 mism=0 | ...
--- UVM Report Summary ---
** Report counts by severity
UVM_INFO :   ...
UVM_WARNING :   0
UVM_ERROR :   0
UVM_FATAL :   0
```

A `mism=0` scoreboard summary and zero `UVM_ERROR`/`UVM_FATAL` entries mean
the test passed.

The detailed log is in `sim_simple.log` (same directory).  Xcelium also
creates `xcelium.d/` (compilation database) and possibly `INCA_libs/`.

---

## 5. The `xrun` Command, Explained

Open `uvm/xcelium/Makefile` and look at the `sim_simple` target:

```makefile
sim_simple:
    $(XRUN) $(XRUN_FLAGS) $(UVM_ARGS) $(IFDIR) \
      $(RTL)/axi4_to_apb4_2x_simple.v \
      ../sv/interfaces/axi4_master_if.sv \
      ../sv/interfaces/apb_sel_tracker_if.sv \
      ../sv/interfaces/apb_burst_ext_side_if.sv \
      ../sv/models/apb_dual_mem_simple.sv \
      ../sv/pkg/bridge_stimulus_pkg.sv \
      ../sv/interfaces/apb_mon_if.sv \
      ../sv/pkg/bridge_uvm_env_pkg.sv \
      ../sv/pkg/bridge_uvm_tests_pkg.sv \
      ../tb/tb_uvm_simple.sv \
      -top tb_uvm_simple \
      -log sim_simple.log
```

Expanding the variables:

| Variable / argument | Value | Purpose |
|---------------------|-------|---------|
| `XRUN` | `xrun` | The Xcelium front-end. |
| `-64bit` | — | Run in 64-bit mode (required for most commercial flows). |
| `-sv` | — | Enable SystemVerilog (not just Verilog-2001). |
| `-timescale 1ns/1ps` | — | Default timescale for modules that omit `` `timescale ``. |
| `-access +rwc` | — | Grant read/write/connectivity access to all signals; needed for waveform probing and UVM virtual interfaces to resolve at elaboration. |
| `-uvmhome $(UVM_HOME)` | path or `CDNS` | Point Xcelium at the UVM installation.  This replaces the explicit `+incdir+.../uvm/src  .../uvm.sv` required by VCS. |
| `+incdir+../sv/interfaces` | — | `axi4_master_if.sv` lives here; bare `` `include "axi4_master_if.sv" `` in package bodies resolve against these directories. |
| `+incdir+../sv/pkg` ... | — | Five more `+incdir+` entries for `env/`, `monitors/`, `scoreboard/`, `transactions/`, `pkg/`.  **All six are required** because `bridge_uvm_env_pkg.sv` uses bare-filename `` `include `` directives for sub-components. |
| RTL `.v` file | `../../src/axi4_to_apb4_2x_simple.v` | The DUT under test. |
| SV interface/model/pkg files | listed explicitly | Order matters: interfaces first, then models, packages (stimulus → env → tests), then the top module. |
| `-top tb_uvm_simple` | — | Designates the top-level module to elaborate. |
| `-log sim_simple.log` | — | Captures all xrun output to a log file (console still shows it too). |

### 5.1 Why `-access +rwc`?

Without read/write/connectivity access, Xcelium optimizes signals away during
elaboration and the virtual interface handles in UVM config DB cannot probe
DUT signals.  You will see:

```
Error: Signal not accessible ...
```

`+rwc` (read, write, connectivity) keeps every named signal accessible.  It
has a small simulation-speed cost, which is usually acceptable in verification.

### 5.2 Why `-uvmhome` instead of explicit `uvm.sv`?

VCS requires you to compile `uvm.sv` as a source file and add
`+incdir+$(UVM_HOME)/src`.  Xcelium with `-uvmhome` does this automatically
and also links the UVM DPI C library without any extra `-sv_lib` flag.  The
result is a shorter, cleaner compile line.

---

## 6. All Five Test Targets

The Makefile in `uvm/xcelium/` provides five targets, each testing a different
bridge configuration.

### 6.1 `sim_simple` — Single-beat AXI to APB

```bash
make sim_simple
```

DUT: `axi4_to_apb4_2x_simple`.  Test class: `test_bridge_simple`.

The test writes a 64-bit word to APB port 0 (`addr[31]==0`) and one to APB
port 1 (`addr[31]==1`), then reads both back and checks for exact data match.

### 6.2 `sim_burst` — Multi-beat INCR/FIXED bursts

```bash
make sim_burst
```

DUT: `axi4_to_apb4_2x_burst`.  Test class: `test_bridge_burst`.

Exercises single-beat writes and reads through the burst bridge (which also
validates the DECERR path for a crossing burst).  The scoreboard verifies
AXI response codes as well as APB data.

### 6.3 `sim_burst_ext` — Burst with PSLVERR injection

```bash
make sim_burst_ext
```

DUT: `axi4_to_apb4_2x_burst`.  Test class: `test_bridge_burst_ext`.

Uses `apb_burst_ext_side_if` to drive `PSLVERR` on the APB slave side and
`PREADY` randomly.  Verifies `BRESP == SLVERR` when APB slaves signal errors,
and checks that `DECERR` appears for address-crossing bursts.

### 6.4 `sim_simple_ws` — APB read wait-states

```bash
make sim_simple_ws            # default READ_WS=2
make sim_simple_ws READ_WS=4  # four APB read stall cycles
```

DUT: `axi4_to_apb4_2x_simple`.  Test class: `test_bridge_simple_ws`.

The APB slave model (`apb_dual_mem_ws.sv`) inserts `READ_WS` wait cycles on
every read transfer.  The test verifies the bridge handles back-pressure from
`PREADY` correctly.  `READ_WS` defaults to 2; override as shown.

### 6.5 `sim_parameterized` — 32-bit bridge, custom select bit

```bash
make sim_parameterized
```

DUT: `axi4_to_apb4_2x_burst` with `APB_ADDR_BIT=20` and `DATA_WIDTH=32`.
Test class: `test_bridge_parameterized_cfg`.

Writes to addresses with bit 20 clear (APB0) and set (APB1), verifies
`PSEL0`/`PSEL1` assertion via `apb_sel_tracker_if`, and checks DECERR for
64-bit AXI size on a 32-bit bridge.

### 6.6 Running all five at once

```bash
make sim_simple sim_burst sim_burst_ext sim_simple_ws sim_parameterized
```

Or from the **repository root** (after the top-level Makefile wiring added in
the latest commit):

```bash
export UVM_HOME=CDNS
make uvm-xcelium         # runs all five
make uvm-xcelium-simple  # one target
```

---

## 7. Reading the UVM Output

### 7.1 UVM phases

Each simulation goes through UVM's standard phase ladder:

```
build_phase      -> construct env, monitors, scoreboard
connect_phase    -> wire analysis ports to scoreboard TLM imps
start_of_simulation_phase
run_phase        -> stimulus runs here; objections gate end-of-test
extract_phase
check_phase
report_phase     -> scoreboard prints summary; errors appear here
final_phase
```

Phase progression looks like this in the log:

```
UVM_INFO @ 0: reporter [RNTST] Running test test_bridge_simple...
UVM_INFO @ 0 [build_phase] ...
...
UVM_INFO @ 1040 [run_phase] SIMPLE TEST PASSED
...
UVM_INFO @ 1040 [report_phase] SB summary: axi_wr=2 axi_rd=2 apb0=1 apb1=1 mism=0 ...
```

The timestamps are in simulation time (nanoseconds at `1ns/1ps`).

### 7.2 Scoreboard summary fields

| Field | Meaning |
|-------|---------|
| `axi_wr=N` | Number of AXI write transactions the AXI monitor observed. |
| `axi_rd=N` | Number of AXI read transactions. |
| `apb0=N` | APB completions on port 0 (both directions). |
| `apb1=N` | APB completions on port 1. |
| `mism=N` | Mismatches found.  Must be 0 for a clean pass. |
| `pred_wr rem p0=N p1=N` | Unreconciled predicted write beats (should be 0). |
| `buf_wr p0=N p1=N` | Unreconciled observed write beats (should be 0). |

Non-zero `rem` or `buf` counts in `report_phase` mean a transaction was never
matched — a lost beat or ordering problem.

### 7.3 Severity levels

| UVM severity | Meaning |
|--------------|---------|
| `UVM_INFO` | Informational; use `+UVM_VERBOSITY` to control. |
| `UVM_WARNING` | Unexpected but recoverable situation. |
| `UVM_ERROR` | Verification failure; simulation continues. |
| `UVM_FATAL` | Unrecoverable; simulation stops immediately. |

A clean run has `UVM_ERROR : 0` and `UVM_FATAL : 0`.

---

## 8. Waveforms

Xcelium does not dump waveforms by default.  Add probing flags to the
`xrun` command in `uvm/xcelium/Makefile` or use a separate `xrun -input`
script.

### 8.1 VCD (open format, GTKWave-compatible)

Add `-vcd waves.vcd` and `-probe {tb_uvm_simple}` to the xrun command for
`sim_simple`:

```makefile
sim_simple:
    $(XRUN) $(XRUN_FLAGS) $(UVM_ARGS) $(IFDIR) \
      ...files... \
      -top tb_uvm_simple -log sim_simple.log \
      -vcd waves_simple.vcd -probe {tb_uvm_simple}
```

Then view with GTKWave:

```bash
gtkwave waves_simple.vcd
```

`-probe {tb_uvm_simple}` dumps all signals under the `tb_uvm_simple` scope.
Use a more specific path like `{tb_uvm_simple.dut}` to limit dump size.

### 8.2 SHDB / SimVision (Cadence native)

Cadence's waveform format is SHM (`.shm` directory) or FSDB (with a VIP).
For SHM:

```bash
xrun  ...  -shm waves_simple.shm -probe {tb_uvm_simple}
simvision waves_simple.shm &
```

SimVision provides schematic trace, transaction annotation, and is tightly
integrated with Xcelium's debug database.

### 8.3 Adding probes via TCL input script

For finer control, put probe commands in a TCL file:

```tcl
# file: probe_simple.tcl
probe -create tb_uvm_simple -depth all -shm -name probe_simple
run
```

Then:

```bash
xrun  ...  -input probe_simple.tcl  -top tb_uvm_simple
```

This is useful when you want to probe only specific hierarchical scopes or
use conditional triggers.

---

## 9. Debugging Techniques

### 9.1 Increase UVM verbosity

The default verbosity is `UVM_MEDIUM`.  Pass `+UVM_VERBOSITY=UVM_HIGH` to
see every transaction prediction and comparison:

```bash
make sim_simple XRUN_FLAGS="-64bit -sv -timescale 1ns/1ps -access +rwc +UVM_VERBOSITY=UVM_HIGH"
```

Or edit the Makefile temporarily:

```makefile
XRUN_FLAGS ?= -64bit -sv -timescale 1ns/1ps -access +rwc +UVM_VERBOSITY=UVM_HIGH
```

With `UVM_HIGH` you will see each AXI and APB transaction as the monitors
observe it, and each scoreboard comparison as it is made.

### 9.2 Override the test name

Each testbench top hardcodes `run_test("test_bridge_simple")`.  To swap in a
different test without modifying HDL, pass `+UVM_TESTNAME=`:

```bash
xrun  ...  +UVM_TESTNAME=test_bridge_burst  -top tb_uvm_burst
```

This only works if the new test class is compiled into the same run.

### 9.3 Timeout a hung simulation

The `test_bridge_burst_ext` test includes a UVM fatal timer
(`#20000 -> uvm_fatal`).  For other tests, add a global timeout:

```bash
xrun  ...  +UVM_TIMEOUT=50000,YES
```

`YES` means the simulation exits with a fatal error rather than running
forever.

### 9.4 Inspecting signals with `-access +rwc`

Because the Makefile already passes `-access +rwc`, all signals are readable
at elaboration time.  You can add a `$monitor` or `$display` directly in a
testbench top or UVM component without needing a separate TCL session.

From an `xrun -input` TCL file, you can also read signals interactively:

```tcl
run 200
puts [value {tb_uvm_simple.dut.S_AXI_AWVALID}]
```

### 9.5 Reading the log file

The log file (`sim_simple.log`) contains the full xrun output including
elaboration messages, UVM phase output, and the report summary.  Search for:

```bash
grep -E "UVM_ERROR|UVM_FATAL|PASSED|FAILED|mism=" sim_simple.log
```

### 9.6 Common xrun errors

| Error message | Likely cause | Fix |
|---------------|--------------|-----|
| `Set UVM_HOME` | `UVM_HOME` not exported | `export UVM_HOME=CDNS` or explicit path |
| `` `include: file not found `` | Missing `+incdir+` | Add the missing directory; see `uvm/xcelium/Makefile` `IFDIR` |
| `Error: license checkout failed` | FlexLM license unavailable | Check `CDS_LIC_FILE`; contact EDA admin |
| `Signal not accessible` | `-access` not set | Add `-access +rwc` to `XRUN_FLAGS` |
| `+define+BRIDGE_READ_WS=` (empty) | `READ_WS` not exported before `make` | `export READ_WS=2` or `make sim_simple_ws READ_WS=2` |
| `Error: [TPRM] Test 'X' not found` | Test class not compiled or typo | Check `+UVM_TESTNAME` spelling and package compilation order |

---

## 10. How the UVM Environment Is Structured

Understanding the architecture helps you extend it.  The environment has
three layers, each in a separate SV package.

### 10.1 Package layer

```
bridge_stimulus_pkg
    bridge_axi_stim_64   -- direct-stimulus class: drives AXI interface
    bridge_axi_stim_32

bridge_uvm_env_pkg
    bridge_env_cfg       -- configuration object
    bridge_transactions  -- uvm_sequence_item: wr_tr, rd_tr, apb_tr
    bridge_axi_monitor   -- observes AXI handshakes -> analysis ports
    bridge_apb_monitor   -- observes APB completions -> analysis port
    bridge_scoreboard    -- prediction + check
    bridge_env           -- wires monitors to scoreboard

bridge_uvm_tests_pkg
    bridge_base_test     -- abstract base (DW parameter, build/connect)
    test_bridge_simple
    test_bridge_burst
    test_bridge_burst_ext
    test_bridge_simple_ws
    test_bridge_parameterized_cfg
```

### 10.2 Data flow

```
                      AXI interface (virtual)
                           |
           +---------------+---------------+
           |                               |
    bridge_axi_monitor              bridge_base_test
    (observe AWVALID/AWREADY,       (drive S_AXI_* via
     WVALID/WREADY, BVALID/BREADY,   bridge_axi_stim_64)
     ARVALID/ARREADY, RVALID/RREADY)
           |
           | ap_wr, ap_rd (analysis ports)
           v
    bridge_scoreboard
           ^
           | ap (analysis port)
           |
    bridge_apb_monitor x2
    (observe PSEL/PENABLE/PREADY,
     PWRITE, PADDR, PWDATA, PRDATA)
```

The scoreboard receives AXI events first, predicts the expected APB beats
(address, data, port), then matches them against observed APB events.  The
shadow RAM tracks committed writes so read data checks are self-contained.

### 10.3 `bridge_env_cfg` knobs

| Field | Default | Effect |
|-------|---------|--------|
| `apb_sel_bit` | 31 | Which address bit selects APB0 vs APB1. |
| `decode_kind` | `BRIDGE_DECODE_BURST` | How the scoreboard predicts DECERR. |
| `apb_mem_addr_msb/lsb` | 9/2 | Shadow RAM indexing range. |
| `has_scoreboard` | 1 | Disable for stimulus-only debug. |
| `enable_axi_mon` | 1 | Disable if you only care about APB side. |
| `enable_apb_mons` | 1 | Disable for AXI-only checks. |

---

## 11. Adding Your Own Test

This section walks through adding a new directed test end-to-end.

### Goal: test a 4-beat INCR burst write and read-back on APB0

**Step 1 — Add a stimulus task to `bridge_stimulus_pkg.sv`**

Open `uvm/sv/pkg/bridge_stimulus_pkg.sv` and add inside `bridge_axi_stim_64`:

```systemverilog
task axi_incr_write_4beat(input logic [31:0] base_addr);
  int i;
  @(posedge vif.clk);
  vif.S_AXI_AWID    <= 0;
  vif.S_AXI_AWADDR  <= base_addr;
  vif.S_AXI_AWLEN   <= 8'd3;       // 4 beats: AWLEN+1
  vif.S_AXI_AWSIZE  <= 3'h3;       // 8 bytes
  vif.S_AXI_AWBURST <= 2'h1;       // INCR
  vif.S_AXI_AWPROT  <= 3'h0;
  vif.S_AXI_AWVALID <= 1'h1;
  vif.S_AXI_BREADY  <= 1'h1;
  while (!vif.S_AXI_AWREADY) @(posedge vif.clk);
  @(posedge vif.clk);
  vif.S_AXI_AWVALID <= 1'h0;

  for (i = 0; i < 4; i++) begin
    vif.S_AXI_WDATA  <= 64'(i + 1) << 8 | 64'(i);  // unique per beat
    vif.S_AXI_WSTRB  <= 8'hFF;
    vif.S_AXI_WLAST  <= (i == 3);
    vif.S_AXI_WVALID <= 1'h1;
    while (!vif.S_AXI_WREADY) @(posedge vif.clk);
    @(posedge vif.clk);
    vif.S_AXI_WVALID <= 1'h0;
  end

  while (!vif.S_AXI_BVALID) @(posedge vif.clk);
  if (vif.S_AXI_BRESP !== 2'b00)
    $display("ERROR: burst write BRESP %b", vif.S_AXI_BRESP);
  @(posedge vif.clk);
  vif.S_AXI_BREADY <= 1'h0;
endtask
```

**Step 2 — Add a test class to `bridge_uvm_tests_pkg.sv`**

Open `uvm/sv/pkg/bridge_uvm_tests_pkg.sv` and add before `endpackage`:

```systemverilog
class test_bridge_burst4 extends bridge_base_test #(64);
  `uvm_component_utils(test_bridge_burst4)
  bridge_axi_stim_64 stim;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure_env();
    env_cfg.apb_sel_bit  = 31;
    env_cfg.decode_kind  = BRIDGE_DECODE_BURST;
    // Shadow RAM default covers address bits [9:2]; 4 beats of 8B each
    // starting at 0x0000_0100 use indices 32-35, well within range.
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    stim = new();
    stim.set_if(axi_vif, null);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    stim.drv_init_zeros();
    stim.wait_reset_after_start();
    stim.axi_incr_write_4beat(32'h0000_0100);
    // Add a read-back here if desired using axi_single_read_burst_style
    $display("BURST-4 WRITE TEST PASSED");
    phase.drop_objection(this);
  endtask
endclass
```

**Step 3 — Add a Makefile target**

In `uvm/xcelium/Makefile`, add a new target after `sim_parameterized`:

```makefile
sim_burst4:
    $(XRUN) $(XRUN_FLAGS) $(UVM_ARGS) $(IFDIR) \
      $(RTL)/axi4_to_apb4_2x_burst.v \
      ../sv/interfaces/axi4_master_if.sv \
      ../sv/interfaces/apb_sel_tracker_if.sv \
      ../sv/interfaces/apb_burst_ext_side_if.sv \
      ../sv/models/apb_dual_mem_burst.sv \
      ../sv/pkg/bridge_stimulus_pkg.sv \
      ../sv/interfaces/apb_mon_if.sv \
      ../sv/pkg/bridge_uvm_env_pkg.sv \
      ../sv/pkg/bridge_uvm_tests_pkg.sv \
      ../tb/tb_uvm_burst.sv \
      -top tb_uvm_burst \
      -log sim_burst4.log
```

The test uses `tb_uvm_burst` (which calls `run_test("test_bridge_burst")` by
default), so override the test name at the command line:

```bash
make sim_burst4 XRUN_FLAGS="-64bit -sv -timescale 1ns/1ps -access +rwc +UVM_TESTNAME=test_bridge_burst4"
```

Or replace the `run_test` call in a new `tb_uvm_burst4.sv` top module.

**Step 4 — Update `.PHONY`**

Add `sim_burst4` to the `.PHONY` line in `uvm/xcelium/Makefile` and to the
`clean` target's log deletion.

**Step 5 — Run it**

```bash
cd uvm/xcelium
make sim_burst4 XRUN_FLAGS="-64bit -sv -timescale 1ns/1ps -access +rwc +UVM_TESTNAME=test_bridge_burst4"
grep -E "PASSED|UVM_ERROR|mism=" sim_burst4.log
```

---

## 12. Key Differences: Xcelium vs VCS

If you will work on both tool flows, keep this table handy:

| Aspect | Xcelium (`uvm/xcelium/`) | VCS (`uvm/vcs/`) |
|--------|--------------------------|-----------------|
| Tool | `xrun` (single step) | `vcs` (compile) + `./simv` (run) |
| 64-bit flag | `-64bit` | `-full64` |
| SV mode | `-sv` | `-sverilog` |
| Signal access | `-access +rwc` | `+acc +vpi` |
| UVM | `-uvmhome $(UVM_HOME)` (no extra source files) | `+incdir+$(UVM_HOME)/src $(UVM_HOME)/src/uvm.sv` |
| Log | `-log sim.log` (inline) | `./simv -l sim.log` (separate run step) |
| Build artifacts | `xcelium.d/` `INCA_libs/` `*.shm` | `csrc/` `simv.daidir/` `DVEfiles/` |
| Waveform | `-vcd` / `-shm` + SimVision | `-vpd` + DVE or Verdi |

---

## 13. Where to Go Next

| Goal | Starting point |
|------|---------------|
| Understand the bridge protocol | [`doc/design_contract.md`](design_contract.md) |
| Navigate UVM component code | [`uvm/README.md`](../uvm/README.md) and per-directory READMEs |
| Extend tests or debug scoreboard mismatches | [`uvm/GEMINI.md`](../uvm/GEMINI.md) |
| Add constrained-random stimulus | `bridge_stimulus_pkg.sv` — convert tasks to `uvm_sequence` items |
| Add functional coverage | Add `covergroup` inside monitors or a new coverage collector component |
| Formal property checking | `verification/formal/` (SymbiYosys) — see `make formal` from root |
| Add a second DUT variant | Extend `bridge_env_cfg`, add a new `decode_kind_e` value, add RTL + tb top |

The `doc/PLAN.md` lists near-term and medium-term features: constrained-random
AXI driver, APB slave agent with wait-state randomization, functional coverage
groups, and burst-length sweeps.  Each is a well-defined next step for
someone comfortable with the Xcelium basics covered in this tutorial.
