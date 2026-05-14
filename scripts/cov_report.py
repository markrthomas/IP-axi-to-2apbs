#!/usr/bin/env python3
"""
Generate a coverage report from Verilator-produced lcov .info files.

Prints a terminal summary table and writes a self-contained HTML report.

Usage:
    python3 scripts/cov_report.py [--out coverage_report.html] <file.info> ...

The HTML file embeds all source code and requires no external assets.
"""

from __future__ import annotations

import argparse
import html
import sys
from dataclasses import dataclass, field
from pathlib import Path


# ---------------------------------------------------------------------------
# Parse lcov .info
# ---------------------------------------------------------------------------

@dataclass
class FileRecord:
    path: str
    da: dict[int, int] = field(default_factory=dict)   # line -> hit count
    brda: dict[int, list[int]] = field(default_factory=dict)  # line -> branch counts
    brf: int = 0
    brh: int = 0

    @property
    def lines_found(self) -> int:
        return len(self.da)

    @property
    def lines_hit(self) -> int:
        return sum(1 for c in self.da.values() if c > 0)

    @property
    def line_pct(self) -> float:
        return 100.0 * self.lines_hit / self.lines_found if self.lines_found else 0.0

    @property
    def branch_pct(self) -> float:
        return 100.0 * self.brh / self.brf if self.brf else 0.0


def parse_info(path: Path) -> list[FileRecord]:
    records: list[FileRecord] = []
    cur: FileRecord | None = None
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if line.startswith("SF:"):
            cur = FileRecord(path=line[3:])
        elif line.startswith("DA:") and cur is not None:
            parts = line[3:].split(",")
            if len(parts) >= 2:
                try:
                    ln, cnt = int(parts[0]), int(parts[1])
                    cur.da[ln] = cur.da.get(ln, 0) + cnt
                except ValueError:
                    pass
        elif line.startswith("BRDA:") and cur is not None:
            parts = line[5:].split(",")
            if len(parts) >= 4:
                try:
                    ln = int(parts[0])
                    cnt = int(parts[3]) if parts[3] != "-" else 0
                    cur.brda.setdefault(ln, []).append(cnt)
                except ValueError:
                    pass
        elif line.startswith("BRF:") and cur is not None:
            try:
                cur.brf = int(line[4:])
            except ValueError:
                pass
        elif line.startswith("BRH:") and cur is not None:
            try:
                cur.brh = int(line[4:])
            except ValueError:
                pass
        elif line in ("end_of_record", "end_record") and cur is not None:
            records.append(cur)
            cur = None
    if cur is not None:
        records.append(cur)
    return records


# ---------------------------------------------------------------------------
# Terminal report
# ---------------------------------------------------------------------------

_BAR = "█"
_BAR_W = 20

def _bar(pct: float) -> str:
    filled = round(pct / 100 * _BAR_W)
    return _BAR * filled + "░" * (_BAR_W - filled)

def _grade(pct: float) -> str:
    if pct >= 90:
        return "✓"
    if pct >= 70:
        return "~"
    return "✗"

def print_terminal(records: list[FileRecord], title: str) -> None:
    print(f"\n{'─'*72}")
    print(f"  Coverage report: {title}")
    print(f"{'─'*72}")
    hdr = f"  {'File':<38} {'Lines':>6}  {'Bar':<22} {'Branch':>7}"
    print(hdr)
    print(f"  {'─'*38}  {'─'*6}  {'─'*22}  {'─'*7}")

    totals_lf = totals_lh = totals_brf = totals_brh = 0
    for rec in records:
        name = Path(rec.path).name
        lp = rec.line_pct
        bp = rec.branch_pct
        totals_lf  += rec.lines_found
        totals_lh  += rec.lines_hit
        totals_brf += rec.brf
        totals_brh += rec.brh
        bar = _bar(lp)
        print(f"  {name:<38} {lp:5.1f}%  {bar}  {bp:6.1f}%  {_grade(bp)}")

    print(f"  {'─'*38}  {'─'*6}  {'─'*22}  {'─'*7}")
    tot_lp = 100.0 * totals_lh / totals_lf if totals_lf else 0.0
    tot_bp = 100.0 * totals_brh / totals_brf if totals_brf else 0.0
    print(f"  {'TOTAL':<38} {tot_lp:5.1f}%  {_bar(tot_lp)}  {tot_bp:6.1f}%  {_grade(tot_bp)}")
    print(f"  Lines: {totals_lh}/{totals_lf}    Branches: {totals_brh}/{totals_brf}")
    print(f"{'─'*72}\n")


# ---------------------------------------------------------------------------
# HTML report
# ---------------------------------------------------------------------------

_CSS = """\
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Courier New',monospace;font-size:13px;background:#1e1e2e;color:#cdd6f4}
h1{font-family:sans-serif;font-size:1.3rem;padding:14px 20px;background:#181825;color:#cba6f7;
   border-bottom:1px solid #313244}
h2{font-family:sans-serif;font-size:1rem;padding:10px 20px;background:#181825;
   color:#89b4fa;border-bottom:1px solid #313244;margin-top:20px}
.summary{padding:16px 20px}
table{border-collapse:collapse;width:100%;max-width:900px}
th{background:#313244;color:#a6adc8;padding:6px 10px;text-align:left;font-size:12px}
td{padding:5px 10px;border-bottom:1px solid #313244}
tr:hover td{background:#2a2a3e}
.bar-wrap{background:#45475a;border-radius:4px;height:10px;width:160px;display:inline-block}
.bar-fill{height:10px;border-radius:4px;display:block}
.hi{background:#a6e3a1}.mid{background:#f9e2af}.lo{background:#f38ba8}
.num{text-align:right;color:#a6adc8;min-width:54px;display:inline-block}
.src{margin:0 0 30px 0}
.src-header{font-family:sans-serif;font-size:0.85rem;padding:6px 14px;background:#313244;
            color:#cba6f7;cursor:pointer;user-select:none}
.src-header:hover{background:#45475a}
.src-body{overflow-x:auto}
pre{line-height:1.55;padding:2px 0}
.line{display:flex}
.lno{width:46px;min-width:46px;text-align:right;padding-right:8px;
     color:#6c7086;user-select:none;border-right:2px solid #313244}
.cnt{width:60px;min-width:60px;text-align:right;padding-right:8px;
     color:#a6adc8;user-select:none;font-size:11px}
.txt{padding-left:10px;white-space:pre;flex:1}
.cov  .lno{border-right-color:#a6e3a1}.cov  .cnt{color:#a6e3a1}.cov  {background:#1a2e1a}
.miss .lno{border-right-color:#f38ba8}.miss .cnt{color:#f38ba8}.miss {background:#2e1a1a}
.none .cnt{color:#45475a}
"""

_JS = """\
document.querySelectorAll('.src-header').forEach(h=>{
  h.addEventListener('click',()=>{
    const b=h.nextElementSibling;
    b.style.display=b.style.display==='none'?'block':'none';
  });
});
"""

def _bar_html(pct: float) -> str:
    cls = "hi" if pct >= 90 else "mid" if pct >= 70 else "lo"
    w = round(pct)
    return (f'<span class="bar-wrap"><span class="bar-fill {cls}" style="width:{w}%"></span></span>'
            f'<span class="num">{pct:.1f}%</span>')


def _source_section(rec: FileRecord, root: Path) -> str:
    src_path = root / rec.path
    lp = rec.line_pct
    bp = rec.branch_pct
    heading = (f"{rec.path}  —  lines {rec.lines_hit}/{rec.lines_found} "
               f"({lp:.1f}%)  branches {rec.brh}/{rec.brf} ({bp:.1f}%)")

    lines_html: list[str] = []
    if src_path.exists():
        src_lines = src_path.read_text(encoding="utf-8", errors="replace").splitlines()
        for i, text in enumerate(src_lines, start=1):
            if i in rec.da:
                cnt = rec.da[i]
                br_counts = rec.brda.get(i, [])
                br_miss = sum(1 for c in br_counts if c == 0)
                if cnt > 0 and br_miss == 0:
                    cls = "cov"
                elif cnt > 0 and br_miss > 0:
                    cls = "cov"   # line hit, some branches missed
                else:
                    cls = "miss"
                cnt_str = f"{cnt:,}"
            else:
                cls = "none"
                cnt_str = ""
            txt = html.escape(text.rstrip("\r"))
            lines_html.append(
                f'<div class="line {cls}">'
                f'<span class="lno">{i}</span>'
                f'<span class="cnt">{cnt_str}</span>'
                f'<span class="txt">{txt}</span>'
                f'</div>'
            )
        body = "<pre>" + "\n".join(lines_html) + "</pre>"
    else:
        body = f'<p style="padding:10px;color:#f38ba8">Source not found: {html.escape(rec.path)}</p>'

    return (f'<div class="src">'
            f'<div class="src-header">{html.escape(heading)}</div>'
            f'<div class="src-body">{body}</div>'
            f'</div>')


def write_html(all_records: list[tuple[str, list[FileRecord]]],
               out: Path, root: Path) -> None:
    rows: list[str] = []
    source_sections: list[str] = []

    for label, records in all_records:
        for rec in records:
            lp = rec.line_pct
            bp = rec.branch_pct
            rows.append(
                f"<tr>"
                f"<td>{html.escape(label)}</td>"
                f"<td>{html.escape(rec.path)}</td>"
                f"<td>{_bar_html(lp)}</td>"
                f"<td>{rec.lines_hit}/{rec.lines_found}</td>"
                f"<td>{_bar_html(bp)}</td>"
                f"<td>{rec.brh}/{rec.brf}</td>"
                f"</tr>"
            )
            source_sections.append(f"<h2>{html.escape(label)} — {html.escape(rec.path)}</h2>")
            source_sections.append(_source_section(rec, root))

    table = (
        "<table>"
        "<thead><tr>"
        "<th>Suite</th><th>File</th>"
        "<th>Line coverage</th><th>Lines hit</th>"
        "<th>Branch coverage</th><th>Branches hit</th>"
        "</tr></thead>"
        "<tbody>" + "\n".join(rows) + "</tbody>"
        "</table>"
    )

    doc = (
        "<!DOCTYPE html><html lang='en'><head>"
        "<meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        "<title>Coverage Report</title>"
        f"<style>{_CSS}</style>"
        "</head><body>"
        "<h1>Verilator Coverage Report</h1>"
        f"<div class='summary'>{table}</div>"
        + "\n".join(source_sections)
        + f"<script>{_JS}</script>"
        "</body></html>"
    )
    out.write_text(doc, encoding="utf-8")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("info_files", nargs="+", type=Path,
                    help=".info files produced by verilator_coverage --write-info")
    ap.add_argument("--out", type=Path, default=Path("coverage_report.html"),
                    help="Output HTML file (default: coverage_report.html)")
    ap.add_argument("--root", type=Path,
                    default=Path(__file__).resolve().parents[1],
                    help="Repo root for resolving source paths (default: parent of scripts/)")
    args = ap.parse_args()

    all_records: list[tuple[str, list[FileRecord]]] = []
    for info_path in args.info_files:
        if not info_path.exists():
            print(f"warning: {info_path} not found — skipping", file=sys.stderr)
            continue
        label = info_path.stem.removeprefix("coverage_")
        records = parse_info(info_path)
        if not records:
            print(f"warning: no records parsed from {info_path}", file=sys.stderr)
            continue
        all_records.append((label, records))
        print_terminal(records, label)

    if not all_records:
        print("error: no valid .info files", file=sys.stderr)
        return 1

    write_html(all_records, args.out, args.root)
    print(f"HTML report: {args.out.resolve()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
