#!/usr/bin/env python3
"""
Fail if verilog reference TBs diverge from the UVM-side mirror artifacts.

Runs without Synopsys VCS: verifies that key stimulus literals and hook names from
each test/tb_axi4*.v (and parameterized) appear in bridge_stimulus_pkg.sv,
bridge_uvm_tests_pkg.sv, and the matching tb_uvm_*.sv tops.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Suite:
    name: str
    ref: str
    mirror_files: tuple[str, ...]
    needles_ref: tuple[str, ...]
    needles_mirror_only: tuple[str, ...]
    ref_exclusive: tuple[str, ...] = ()


# Curated literals / symbols that MUST stay aligned when editing either side.
SUITES: tuple[Suite, ...] = (
    Suite(
        "simple",
        "test/tb_axi4_to_apb4_2x_simple.v",
        (
            "uvm/sv/interfaces/apb_mon_if.sv",
            "uvm/sv/pkg/bridge_uvm_env_pkg.sv",
            "uvm/sv/pkg/bridge_stimulus_pkg.sv",
            "uvm/tb/tb_uvm_simple.sv",
            "uvm/sv/pkg/bridge_uvm_tests_pkg.sv",
        ),
        needles_ref=(
            "DEAD_BEEF_CAFE_BABE",
            "1234_5678_9ABC_DEF0",
            "32'h0000_0010",
            "32'h8000_0020",
        ),
        needles_mirror_only=(
            "class bridge_scoreboard",
            "run_mirror_simple",
            "test_bridge_simple",
        ),
    ),
    Suite(
        "burst",
        "test/tb_axi4_to_apb4_2x_burst.v",
        (
            "uvm/sv/interfaces/apb_mon_if.sv",
            "uvm/sv/pkg/bridge_uvm_env_pkg.sv",
            "uvm/sv/pkg/bridge_stimulus_pkg.sv",
            "uvm/tb/tb_uvm_burst.sv",
            "uvm/sv/pkg/bridge_uvm_tests_pkg.sv",
        ),
        needles_ref=(
            "DEAD_BEEF_CAFE_BABE",
            "1234_5678_9ABC_DEF0",
            "32'h7FFF_FFF8",
            "axi_crossing_write_decerr",
        ),
        needles_mirror_only=(
            "class bridge_scoreboard",
            "axi_crossing_write_decerr",
            "run_mirror_burst",
            "test_bridge_burst",
        ),
    ),
    Suite(
        "burst_ext",
        "test/tb_axi4_to_apb4_2x_burst_extended.v",
        (
            "uvm/sv/interfaces/apb_mon_if.sv",
            "uvm/sv/pkg/bridge_uvm_env_pkg.sv",
            "uvm/sv/pkg/bridge_stimulus_pkg.sv",
            "uvm/tb/tb_uvm_burst_ext.sv",
            "uvm/sv/pkg/bridge_uvm_tests_pkg.sv",
        ),
        needles_ref=(
            "32'h0000_1000",
            "32'h0000_2000",
            "32'h0000_4000",
            "32'h8000_1000",
            "32'h0000_5000",
            "32'h7FFF_FFF8",
            "32'h6b4d2e19",
        ),
        needles_mirror_only=(
            "class bridge_scoreboard",
            "run_mirror_burst_ext",
            "test_bridge_burst_ext",
            "apb_burst_ext_side_if",
        ),
    ),
    Suite(
        "simple_ws",
        "test/tb_axi4_to_apb4_2x_simple_ws.v",
        (
            "uvm/sv/interfaces/apb_mon_if.sv",
            "uvm/sv/pkg/bridge_uvm_env_pkg.sv",
            "uvm/tb/tb_uvm_simple_ws.sv",
            "uvm/sv/pkg/bridge_uvm_tests_pkg.sv",
            "uvm/vcs/Makefile",
        ),
        needles_ref=(
            "DEAD_BEEF_CAFE_BABE",
            "1234_5678_9ABC_DEF0",
            "SIMPLE WS TEST PASSED (READ_WAIT_CYCLES=%0d)",
        ),
        needles_mirror_only=(
            "class bridge_scoreboard",
            "BRIDGE_READ_WS",
            "read_wait_cycles",
            "test_bridge_simple_ws",
        ),
        ref_exclusive=("ifndef READ_WAIT_CYCLES", "define READ_WAIT_CYCLES"),
    ),
    Suite(
        "parameterized",
        "test/tb_parameterized_config.v",
        (
            "uvm/sv/interfaces/apb_mon_if.sv",
            "uvm/sv/pkg/bridge_uvm_env_pkg.sv",
            "uvm/sv/pkg/bridge_stimulus_pkg.sv",
            "uvm/tb/tb_uvm_parameterized.sv",
            "uvm/sv/pkg/bridge_uvm_tests_pkg.sv",
        ),
        needles_ref=(
            "32'hAAAA_BBBB",
            "32'hCCCC_DDDD",
            "32'h0010_0000",
            "SUCCESS: DECERR for wrong size",
        ),
        needles_mirror_only=(
            "class bridge_scoreboard",
            "run_mirror_param",
            "apb_sel_tracker",
            "test_bridge_parameterized_cfg",
        ),
    ),
)


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8", errors="replace")


def check_suite(root: Path, s: Suite) -> list[str]:
    errs: list[str] = []
    ref_p = root / s.ref
    if not ref_p.is_file():
        return [f"{s.name}: missing reference file {s.ref}"]
    ref_txt = read(ref_p)

    sink_txt = ""
    paths_ok = True
    for rel in s.mirror_files:
        sp = root / rel
        if not sp.is_file():
            errs.append(f"{s.name}: missing mirror artifact {rel}")
            paths_ok = False
            continue
        sink_txt += read(sp) + "\n"
    if not paths_ok:
        return errs

    for nd in s.needles_ref:
        if nd not in ref_txt:
            errs.append(f"{s.name}: reference drop? '{nd}' absent from {s.ref}")
        if nd not in sink_txt:
            errs.append(f"{s.name}: mirror missing ref literal/link '{nd}'")

    for nd in s.needles_mirror_only:
        if nd not in sink_txt:
            errs.append(f"{s.name}: mirror missing symbol '{nd}'")

    for nd in s.ref_exclusive:
        if nd not in ref_txt:
            errs.append(f"{s.name}: reference lost anchor '{nd}' ({s.ref})")

    # Extra coupling: verilog extended TB forks $random with fixed seed literal.
    if s.name == "burst_ext":
        if "repeat (100)" not in ref_txt:
            errs.append(f"{s.name}: reference tb lost repeat(100)?")
        if "repeat (100)" not in sink_txt:
            errs.append(f"{s.name}: stimulus lost repeat(100)")

    # Simple / burst verilog uses same fixed seed inside crossing write decoder path.
    if s.name == "burst":
        if "32'h3f9012ab" not in ref_txt or "32'h3f9012ab" not in sink_txt:
            errs.append(f"{s.name}: crossing WDATA seed literal 32'h3f9012ab missing")

    return errs


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Repository root (default: parent of scripts/).",
    )
    args = ap.parse_args()
    root: Path = args.root

    all_errs: list[str] = []
    for suite in SUITES:
        all_errs.extend(check_suite(root, suite))

    if all_errs:
        print("uvm_mirror_check: FAILED\n", file=sys.stderr)
        for e in all_errs:
            print(f"  {e}", file=sys.stderr)
        return 1

    print("uvm_mirror_check: OK ({0} suites)".format(len(SUITES)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
