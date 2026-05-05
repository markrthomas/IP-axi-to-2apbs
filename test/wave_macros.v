// Optional GTKWave-compatible dumps via vvp runtime.
// Trigger: +wave on vvp CLI. Override path: +wavefile=<relative_path>
//
// Extension must match runtime: use vvp -fst for .fst files (recommended for GTKWave),
// or omit -fst so $dumpvars writes Verilog-standard VCD (use .vcd filenames).

`define IVL_OPTIONAL_DUMP(MODULE_TOP, DEFAULT_WAVEFILE) \
initial begin \
  reg [1023:0] wf_; \
  if ($test$plusargs("wave")) begin \
    if (!$value$plusargs("wavefile=%s", wf_)) wf_ = DEFAULT_WAVEFILE; \
    $dumpfile(wf_); \
    $dumpvars(0, MODULE_TOP); \
  end \
end
