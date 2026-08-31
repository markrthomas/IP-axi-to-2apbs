import { defineRailway, preserve, project, service } from "railway/iac";

// Railway Infrastructure as Code — replaces the deprecated railway.toml.
// https://docs.railway.com/infrastructure-as-code
//
// This project is a hardware DV suite, not a web service: it has no listening
// port.  The container's ENTRYPOINT (docker/entrypoint.sh) runs `make -C uvm/vlt
// ci` (lint + every UVM top under open-source Verilator, scoreboard/UVM_ERROR-
// gated) and exits with the gate's status (0 = green).  Run it as a one-off /
// batch job, not an always-on service.
//
// Partial: this file manages ONLY the ip-axi-2apbs-uvm service so it does not
// touch the sibling service that happens to share the "Test axi-on-ucie"
// project.  (A shared repo would keep one .railway file for the whole project;
// here the service lives beside another team's, so a partial is correct.)
export const partial = "ip-axi-2apbs-uvm";

export default defineRailway(() => {
  const ipAxi2apbsUvm = service("ip-axi-2apbs-uvm", {
    // Root Dockerfile (Verilator 5.050 from source) is auto-detected as the
    // builder; the other two Dockerfiles (.dev, .ci) are never the root name.
    replicas: 1,

    // Batch job: don't restart on exit.  A normal always-on service that exits 0
    // is flagged "crashed" by Railway — NEVER is correct for a run-to-completion
    // gate.  (Do NOT set a start command: it would run via `sh -c` and bypass the
    // entrypoint wrapper that injects the bundled-Verilator overrides and the
    // Railway log-volume filter.)
    restartPolicyType: "NEVER",

    // Keep the Railway-level BUILD_JOBS override if one is set (the Dockerfile
    // already bakes ENV BUILD_JOBS=1); preserve() retains the value without
    // writing it into source.
    env: { BUILD_JOBS: preserve() },
  });

  return project("Test axi-on-ucie", {
    resources: [ipAxi2apbsUvm],
  });
});
