// UVM macro include shim for the open-source (Verilator) UVM flow.
//
// The bridge/regblock packages `include "uvm_macros.svh", which under a
// commercial simulator resolves to $UVM_HOME/src/uvm_macros.svh.  This flow
// instead compiles the Accellera library as the single monolithic header
// uvm_pkg_all_v2020_3_1_dpi.svh (listed first on the tool command line), which
// already defines every `uvm_* macro.  This stub simply satisfies the `include
// so the same sources compile unchanged; it deliberately defines nothing.  It
// is only ever on the open-source flow's +incdir (see uvm/vlt/Makefile) — the
// VCS/Xcelium flows use the real header from UVM_HOME and never see this file.
//
// (First comment word avoids "verilator", which the tool parses as a pragma.)
