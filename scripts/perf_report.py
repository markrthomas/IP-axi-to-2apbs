#!/usr/bin/env python3
"""
Render a performance report from the sim_main_perf benchmark output.

Reads the "PERF <key> <value>" lines emitted by sim_main_perf (from a file or
stdin), prints a terminal summary, and writes a self-contained HTML report.

Usage:
    ./sim_main_perf | python3 scripts/perf_report.py --out perf_report.html
    python3 scripts/perf_report.py perf_metrics.txt --out perf_report.html
"""

from __future__ import annotations

import argparse
import datetime
import sys
from pathlib import Path


def parse_perf(text: str) -> dict[str, float]:
    raw: dict[str, float] = {}
    for line in text.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[0] == "PERF":
            try:
                raw[parts[1]] = float(parts[2])
            except ValueError:
                pass
    return raw


def derive(raw: dict[str, float]) -> list[tuple[str, str, str]]:
    """Return a list of (metric, value, unit) rows, raw counters then rates."""
    cycles   = raw.get("sim_cycles", 0.0)
    beats    = raw.get("axi_beats", 0.0)
    wall     = raw.get("wall_seconds", 0.0)
    txns     = raw.get("transactions", 0.0)
    clk_mhz  = raw.get("clock_mhz", 100.0)

    sim_hz          = cycles / wall if wall else 0.0
    cycles_per_beat = cycles / beats if beats else 0.0
    cycles_per_txn  = cycles / txns if txns else 0.0
    # Sustained DUT throughput at the nominal clock: one beat carries 8 bytes.
    beats_per_sec   = (clk_mhz * 1e6) / cycles_per_beat if cycles_per_beat else 0.0
    mbytes_per_sec  = beats_per_sec * 8 / 1e6

    rows: list[tuple[str, str, str]] = [
        ("Iterations",            f"{int(raw.get('iterations', 0)):,}",  "write+read pairs"),
        ("AXI transactions",      f"{int(txns):,}",                      "AW/AR issued"),
        ("AXI beats",             f"{int(beats):,}",                     f"{int(raw.get('write_beats',0)):,} W / {int(raw.get('read_beats',0)):,} R"),
        ("Simulated cycles",      f"{int(cycles):,}",                    "ACLK edges"),
        ("Wall time",             f"{wall:.4f}",                         "s"),
        ("── Simulation speed",   "",                                    ""),
        ("Sim throughput",        f"{sim_hz/1e3:,.1f}",                  "kcycles/s"),
        ("── Design efficiency",  "",                                    ""),
        ("Cycles per beat",       f"{cycles_per_beat:.2f}",              "lower is better"),
        ("Cycles per transaction",f"{cycles_per_txn:.2f}",              "incl. AW/B/AR handshakes"),
        (f"Beat rate @ {clk_mhz:.0f} MHz", f"{beats_per_sec/1e6:.2f}",   "Mbeat/s"),
        (f"Bandwidth @ {clk_mhz:.0f} MHz", f"{mbytes_per_sec:,.1f}",     "MB/s (8 B/beat)"),
    ]
    return rows


def print_terminal(rows: list[tuple[str, str, str]], title: str) -> None:
    print(f"\n{'─'*64}")
    print(f"  Performance report: {title}")
    print(f"{'─'*64}")
    for metric, value, unit in rows:
        if value == "" and unit == "":
            # Section divider row.
            print(f"  {metric}")
            continue
        print(f"  {metric:<26} {value:>14}  {unit}")
    print(f"{'─'*64}\n")


_CSS = """\
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Courier New',monospace;font-size:13px;background:#1e1e2e;color:#cdd6f4}
h1{font-family:sans-serif;font-size:1.3rem;padding:14px 20px;background:#181825;color:#cba6f7;
   border-bottom:1px solid #313244}
.meta{padding:10px 20px;color:#a6adc8;font-size:12px}
.summary{padding:6px 20px 24px}
table{border-collapse:collapse;width:100%;max-width:640px}
th{background:#313244;color:#a6adc8;padding:6px 12px;text-align:left;font-size:12px}
td{padding:6px 12px;border-bottom:1px solid #313244}
td.val{text-align:right;color:#a6e3a1;font-weight:bold}
td.unit{color:#6c7086;font-size:12px}
tr.sec td{background:#181825;color:#89b4fa;font-family:sans-serif;font-size:12px;
          text-transform:uppercase;letter-spacing:0.5px}
tr:hover td{background:#2a2a3e}
tr.sec:hover td{background:#181825}
"""


def write_html(rows: list[tuple[str, str, str]], out: Path, title: str) -> None:
    import html as _html
    trs: list[str] = []
    for metric, value, unit in rows:
        if value == "" and unit == "":
            trs.append(f"<tr class='sec'><td colspan='3'>{_html.escape(metric.lstrip('─ '))}</td></tr>")
        else:
            trs.append(
                f"<tr><td>{_html.escape(metric)}</td>"
                f"<td class='val'>{_html.escape(value)}</td>"
                f"<td class='unit'>{_html.escape(unit)}</td></tr>"
            )
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    doc = (
        "<!DOCTYPE html><html lang='en'><head>"
        "<meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        "<title>Performance Report</title>"
        f"<style>{_CSS}</style>"
        "</head><body>"
        "<h1>Bridge Performance Report</h1>"
        f"<div class='meta'>{_html.escape(title)} &middot; generated {stamp}</div>"
        "<div class='summary'><table>"
        "<thead><tr><th>Metric</th><th>Value</th><th>Unit</th></tr></thead>"
        "<tbody>" + "\n".join(trs) + "</tbody>"
        "</table></div>"
        "</body></html>"
    )
    out.write_text(doc, encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("perf_file", nargs="?", type=Path,
                    help="File of PERF lines (default: read stdin)")
    ap.add_argument("--out", type=Path, default=Path("perf_report.html"),
                    help="Output HTML file (default: perf_report.html)")
    ap.add_argument("--title", default="axi4_to_apb4_2x_burst",
                    help="Report title / DUT name")
    args = ap.parse_args()

    text = args.perf_file.read_text(encoding="utf-8") if args.perf_file else sys.stdin.read()
    raw = parse_perf(text)
    if not raw:
        print("error: no PERF lines found", file=sys.stderr)
        return 1

    rows = derive(raw)
    print_terminal(rows, args.title)
    write_html(rows, args.out, args.title)
    print(f"HTML report: {args.out.resolve()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
