#!/usr/bin/env python3
"""gen_report.py — aggregate the AXI4→2×APB4 bridge's verification, performance,
and run-environment metrics into one report (PLAN item 8).

Consumes (all optional; missing inputs degrade gracefully):
  - coverage_{simple,burst,regblock}.info : Verilator LCOV → line + branch coverage
  - uvm/vlt/obj/<top>/run.log             : UVM report counts + Verilator $finish
                                            (walltime / speed / peak MB) per top
  - cocotb/<group>/results.xml            : cocotb JUnit → per-test pass/fail + sim ns
  - <out>/logs/formal.log                 : SymbiYosys → per-proof PASS/FAIL
  - perf_metrics.txt                      : "PERF <key> <value>" benchmark lines

The **compare & contrast** axis: each run's per-top build/run stats (walltime,
peak RSS, sim speed) are tagged with the run environment (local / container /
railway / ci — auto-detected or --env) and merged into <out>/environments.json,
plus any <out>/env-*.json fragments dropped by container/CI runs, so the same
work is diffable side by side across environments.

Emits <out>/{metrics.json, report.md, report.html}. Figures are SIMULATION
numbers (Verilator), not silicon timing.
"""
import argparse
import datetime
import glob
import html
import json
import os
import re
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

UVM_TOPS = ["tb_uvm_simple", "tb_uvm_burst", "tb_uvm_burst_ext",
            "tb_uvm_parameterized", "tb_uvm_regblock"]
COV_INFO = ["coverage_simple.info", "coverage_burst.info", "coverage_regblock.info"]


# ---------------------------------------------------------------- helpers
def _pct(hit, total):
    return round(100.0 * hit / total, 2) if total else 0.0


def git_sha(root: Path):
    try:
        return subprocess.check_output(
            ["git", "-C", str(root), "rev-parse", "--short", "HEAD"],
            text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return "unknown"


def detect_env():
    """Name the run environment for the compare/contrast axis."""
    if os.environ.get("UVM_RUN_ENV"):
        return os.environ["UVM_RUN_ENV"]
    if any(os.environ.get(k) for k in
           ("RAILWAY_SERVICE_ID", "RAILWAY_PROJECT_ID", "RAILWAY_ENVIRONMENT")):
        return "railway"
    if os.environ.get("GITHUB_ACTIONS") == "true":
        return "ci"
    if Path("/.dockerenv").exists() or Path("/run/.containerenv").exists():
        return "container"
    return "local"


# ---------------------------------------------------------------- coverage (LCOV)
def parse_coverage(root: Path):
    """Union of the DUT (src/) files across all coverage_*.info; line + branch."""
    files = {}   # basename -> [lhit, lines, bhit, branches]
    any_info = False
    for name in COV_INFO:
        info = root / name
        if not info.exists():
            continue
        any_info = True
        cur = None
        for line in info.read_text(errors="replace").splitlines():
            if line.startswith("SF:"):
                path = line[3:]
                cur = os.path.basename(path) if "/src/" in path or path.startswith("src/") else None
            elif line.startswith("DA:") and cur is not None:
                try:
                    _ln, hits = line[3:].split(",")[:2]
                    rec = files.setdefault(cur, [0, 0, 0, 0])
                    rec[1] += 1
                    if int(hits) > 0:
                        rec[0] += 1
                except ValueError:
                    pass
            elif line.startswith("BRDA:") and cur is not None:
                # BRDA:<line>,<block>,<branch>,<taken|->
                parts = line[5:].split(",")
                if len(parts) >= 4:
                    rec = files.setdefault(cur, [0, 0, 0, 0])
                    rec[3] += 1
                    if parts[3] not in ("-", "0"):
                        rec[2] += 1
            elif line.startswith("end_of_record"):
                cur = None
    if not any_info:
        return None
    rows = []
    tlh = tl = tbh = tb = 0
    for f, (lh, ln, bh, br) in sorted(files.items()):
        rows.append({"file": f, "lhit": lh, "lines": ln, "line_pct": _pct(lh, ln),
                     "bhit": bh, "branches": br, "branch_pct": _pct(bh, br)})
        tlh += lh; tl += ln; tbh += bh; tb += br
    rows.sort(key=lambda r: r["line_pct"])   # worst-covered first
    return {"files": rows,
            "line_hit": tlh, "lines": tl, "line_pct": _pct(tlh, tl),
            "branch_hit": tbh, "branches": tb, "branch_pct": _pct(tbh, tb)}


# ---------------------------------------------------------------- UVM tops
_FIN = re.compile(r"\$finish at (\d+)ns; walltime ([\d.]+) s; speed ([\d.]+) us/s")
_MEM = re.compile(r"allocated (\d+) MB")
_CNT = re.compile(r"^UVM_(INFO|WARNING|ERROR|FATAL)\s*:\s*(\d+)")


def parse_uvm_top(log: Path):
    if not log.exists():
        return None
    counts = {"INFO": 0, "WARNING": 0, "ERROR": 0, "FATAL": 0}
    walltime = speed = mem_mb = None
    saw_report = False
    for line in log.read_text(errors="replace").splitlines():
        m = _CNT.match(line)
        if m:
            counts[m.group(1)] = int(m.group(2)); saw_report = True
        m = _FIN.search(line)
        if m:
            walltime = float(m.group(2)); speed = float(m.group(3))
        m = _MEM.search(line)
        if m:
            mem_mb = int(m.group(1))
    status = "PASS" if (saw_report and counts["ERROR"] == 0 and counts["FATAL"] == 0) else "FAIL"
    return {"status": status, "uvm_info": counts["INFO"], "uvm_warning": counts["WARNING"],
            "uvm_error": counts["ERROR"], "uvm_fatal": counts["FATAL"],
            "walltime_s": walltime, "speed_us_s": speed, "mem_mb": mem_mb}


def parse_uvm_tops(root: Path):
    out = {}
    for top in UVM_TOPS:
        rec = parse_uvm_top(root / "uvm" / "vlt" / "obj" / top / "run.log")
        if rec is not None:
            out[top] = rec
    return out


# ---------------------------------------------------------------- cocotb (JUnit)
def parse_cocotb(root: Path):
    groups = {}
    for xml_path in sorted(glob.glob(str(root / "cocotb" / "*" / "results.xml"))):
        group = Path(xml_path).parent.name
        try:
            r = ET.parse(xml_path).getroot()
        except (ET.ParseError, OSError):
            continue
        tests = []
        for tc in r.iter("testcase"):
            failed = any(c.tag in ("failure", "error") for c in tc)
            tests.append({"name": tc.get("name", "?"),
                          "status": "FAIL" if failed else "PASS",
                          "time_s": tc.get("time", ""), "sim_ns": tc.get("sim_time_ns", "")})
        if tests:
            groups[group] = tests
    return groups


# ---------------------------------------------------------------- formal
def parse_formal(log: Path):
    if not log.exists():
        return {}
    proofs = {}
    for line in log.read_text(errors="replace").splitlines():
        m = re.search(r"\[([a-z0-9_]+?)(?:_bmc|_cover)?\]\s+DONE \((PASS|FAIL)", line)
        if m:
            name, status = m.group(1), m.group(2)
            if proofs.get(name) != "FAIL":
                proofs[name] = status
    return proofs


# ---------------------------------------------------------------- perf
def parse_perf(f: Path):
    if not f.exists():
        return {}
    raw = {}
    for line in f.read_text(errors="replace").splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[0] == "PERF":
            try:
                raw[parts[1]] = float(parts[2])
            except ValueError:
                pass
    return raw


# ---------------------------------------------------------------- environments merge
def merge_environments(out: Path, env_name: str, this_tops: dict):
    """Accumulate per-environment UVM run metrics into <out>/environments.json.

    Sources: this run's tops (tagged env_name) + any <out>/env-*.json fragments
    ({"env":..,"generated":..,"tops":{..}}) dropped by container/CI runs.
    """
    store = {}
    ef = out / "environments.json"
    if ef.exists():
        try:
            store = json.loads(ef.read_text())
        except (ValueError, OSError):
            store = {}
    now = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
    if this_tops:
        store[env_name] = {"generated": now, "tops": this_tops}
    for frag in sorted(glob.glob(str(out / "env-*.json"))):
        try:
            d = json.loads(Path(frag).read_text())
            if d.get("env") and d.get("tops"):
                store[d["env"]] = {"generated": d.get("generated", now), "tops": d["tops"]}
        except (ValueError, OSError):
            continue
    if store:
        ef.write_text(json.dumps(store, indent=2) + "\n")
    return store


# ---------------------------------------------------------------- emitters (md/html)
def build_metrics(**kw):
    kw["generated"] = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
    kw["note"] = "Verilator simulation figures; not silicon timing"
    return kw


def _md_uvm(tops):
    L = ["## UVM tops (open-source Verilator)", "",
         "| Top | Status | UVM_ERR | UVM_FATAL | walltime s | peak MB |",
         "|-----|--------|--------:|----------:|-----------:|--------:|"]
    for t in UVM_TOPS:
        if t in tops:
            r = tops[t]
            L.append(f"| {t} | {r['status']} | {r['uvm_error']} | {r['uvm_fatal']} | "
                     f"{r['walltime_s'] if r['walltime_s'] is not None else '?'} | "
                     f"{r['mem_mb'] if r['mem_mb'] is not None else '?'} |")
    return L + [""]


def build_md(m):
    L = [f"# AXI4→2×APB4 bridge — metrics report", "",
         f"_Generated {m['generated']} · commit `{m['git_sha']}` · {m['note']}._", ""]
    cov = m.get("coverage")
    if cov:
        L += ["## Coverage (Verilator, DUT `src/`)", "",
              f"**Line {cov['line_hit']}/{cov['lines']} = {cov['line_pct']}%**, "
              f"**Branch {cov['branch_hit']}/{cov['branches']} = {cov['branch_pct']}%**", "",
              "| File | Line % | Branch % |", "|------|-------:|---------:|"]
        L += [f"| {r['file']} | {r['line_pct']}% | {r['branch_pct']}% |" for r in cov["files"]] + [""]
    if m.get("uvm_tops"):
        L += _md_uvm(m["uvm_tops"])
    envs = m.get("environments") or {}
    if envs:
        names = sorted(envs)
        L += ["## Run environments — compare & contrast", "",
              "Per-top walltime (s) / peak MB by environment.", "",
              "| Top | " + " | ".join(names) + " |",
              "|-----|" + "|".join(["---:"] * len(names)) + "|"]
        for t in UVM_TOPS:
            cells = []
            for n in names:
                r = envs[n]["tops"].get(t)
                cells.append(f"{r['walltime_s']}s / {r['mem_mb']}MB" if r else "—")
            if any(c != "—" for c in cells):
                L.append(f"| {t} | " + " | ".join(cells) + " |")
        L += [""]
    if m.get("formal"):
        L += ["## Formal proofs", "", "| Proof | Status |", "|-------|--------|"]
        L += [f"| {k} | {v} |" for k, v in sorted(m["formal"].items())] + [""]
    coc = m.get("cocotb") or {}
    if coc:
        L += ["## cocotb / pyUVM", "", "| Group | Pass | Total |", "|-------|-----:|------:|"]
        for g, tests in sorted(coc.items()):
            p = sum(1 for t in tests if t["status"] == "PASS")
            L.append(f"| {g} | {p} | {len(tests)} |")
        L += [""]
    if m.get("performance"):
        L += ["## Performance (burst bridge benchmark)", "", "| Metric | Value |", "|--------|------:|"]
        L += [f"| {k} | {v} |" for k, v in m["performance"].items()] + [""]
    return "\n".join(L)


def _bar(pct):
    color = "#2e7d32" if pct >= 90 else ("#f9a825" if pct >= 75 else "#c62828")
    return (f'<div class="bar"><div class="fill" style="width:{pct}%;background:{color}"></div>'
            f'<span>{pct}%</span></div>')


def _badge(ok):
    return f'<span class="badge {"ok" if ok else "bad"}">{"PASS" if ok else "FAIL"}</span>'


def _card(k, v, unit=""):
    return (f'<div class="card"><div class="k">{html.escape(k)}</div>'
            f'<div class="v">{v}<small> {html.escape(unit)}</small></div></div>')


def build_html(m):
    cov = m.get("coverage")
    tops = m.get("uvm_tops") or {}
    envs = m.get("environments") or {}
    coc = m.get("cocotb") or {}
    formal = m.get("formal") or {}
    perf = m.get("performance") or {}

    # summary cards
    cards = []
    tops_pass = sum(1 for r in tops.values() if r["status"] == "PASS")
    if tops:
        cards.append(_card("UVM tops passing", f"{tops_pass}/{len(tops)}"))
    if cov:
        cards.append(_card("Line coverage", cov["line_pct"], "%"))
        cards.append(_card("Branch coverage", cov["branch_pct"], "%"))
    if formal:
        fp = sum(1 for v in formal.values() if v == "PASS")
        cards.append(_card("Formal proofs", f"{fp}/{len(formal)}"))
    if coc:
        tp = sum(1 for ts in coc.values() for t in ts if t["status"] == "PASS")
        tt = sum(len(ts) for ts in coc.values())
        cards.append(_card("cocotb tests", f"{tp}/{tt}"))
    if envs:
        cards.append(_card("Environments compared", len(envs)))

    P = [f'<p class="meta">Generated {html.escape(m["generated"])} · commit '
         f'<code>{html.escape(m["git_sha"])}</code><br>{html.escape(m["note"])}</p>']
    if cards:
        P.append(f'<div class="cards">{"".join(cards)}</div>')

    if cov:
        trs = "".join(
            f'<tr><td>{html.escape(r["file"])}</td>'
            f'<td class="r">{r["lhit"]}/{r["lines"]}</td><td>{_bar(r["line_pct"])}</td>'
            f'<td>{_bar(r["branch_pct"])}</td></tr>' for r in cov["files"])
        P.append(f'<h2>Coverage <small>line {cov["line_pct"]}% · branch {cov["branch_pct"]}% '
                 f'(Verilator, DUT src/)</small></h2>'
                 f'<table><tr><th>File</th><th>Lines</th><th>Line</th><th>Branch</th></tr>{trs}</table>')

    if tops:
        trs = "".join(
            f'<tr><td>{html.escape(t)}</td><td>{_badge(tops[t]["status"]=="PASS")}</td>'
            f'<td class="r">{tops[t]["uvm_error"]}</td><td class="r">{tops[t]["uvm_fatal"]}</td>'
            f'<td class="r">{tops[t]["walltime_s"] if tops[t]["walltime_s"] is not None else "?"}</td>'
            f'<td class="r">{tops[t]["mem_mb"] if tops[t]["mem_mb"] is not None else "?"}</td></tr>'
            for t in UVM_TOPS if t in tops)
        P.append(f'<h2>UVM tops <small>{tops_pass}/{len(tops)} passing (open-source Verilator)</small></h2>'
                 f'<table><tr><th>Top</th><th>Status</th><th>UVM_ERR</th><th>UVM_FATAL</th>'
                 f'<th>walltime s</th><th>peak MB</th></tr>{trs}</table>')

    if envs:
        names = sorted(envs)
        head = "".join(f'<th>{html.escape(n)}</th>' for n in names)
        body = ""
        for t in UVM_TOPS:
            cells = []
            present = False
            for n in names:
                r = envs[n]["tops"].get(t)
                if r:
                    present = True
                    cells.append(f'<td class="r">{r["walltime_s"]}s<br><small>{r["mem_mb"]} MB</small></td>')
                else:
                    cells.append('<td class="r">—</td>')
            if present:
                body += f'<tr><td>{html.escape(t)}</td>{"".join(cells)}</tr>'
        gen = "<br>".join(f'{html.escape(n)}: {html.escape(envs[n]["generated"])}' for n in names)
        P.append(f'<h2>Run environments — compare &amp; contrast '
                 f'<small>{len(names)} env(s); walltime / peak RSS per top</small></h2>'
                 f'<table><tr><th>Top</th>{head}</tr>{body}</table>'
                 f'<p class="meta">{gen}</p>')

    if formal:
        trs = "".join(f'<tr><td>{html.escape(k)}</td><td>{_badge(v=="PASS")}</td></tr>'
                      for k, v in sorted(formal.items()))
        P.append(f'<h2>Formal proofs <small>{len(formal)}</small></h2>'
                 f'<table><tr><th>Proof</th><th>Status</th></tr>{trs}</table>')

    if coc:
        trs = ""
        for g, tests in sorted(coc.items()):
            p = sum(1 for t in tests if t["status"] == "PASS")
            trs += (f'<tr><td>{html.escape(g)}</td><td>{_badge(p==len(tests))}</td>'
                    f'<td class="r">{p}/{len(tests)}</td></tr>')
        P.append(f'<h2>cocotb / pyUVM <small>{sum(len(t) for t in coc.values())} tests</small></h2>'
                 f'<table><tr><th>Group</th><th>Status</th><th>Pass</th></tr>{trs}</table>')

    if perf:
        pc = "".join(_card(k, (int(v) if float(v).is_integer() else round(v, 3))) for k, v in perf.items())
        P.append(f'<h2>Performance <small>burst-bridge benchmark</small></h2><div class="cards">{pc}</div>')

    body = "\n".join(P)
    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>AXI→2×APB4 bridge metrics</title><style>
:root{{--bg:#fff;--fg:#1a1a1a;--mut:#666;--line:#e2e2e2;--card:#f6f7f9}}
@media(prefers-color-scheme:dark){{:root{{--bg:#14171c;--fg:#e6e6e6;--mut:#9aa0a6;--line:#2a2f37;--card:#1c2027}}}}
*{{box-sizing:border-box}}body{{margin:0;padding:2rem;max-width:1100px;margin:auto;
font:15px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;background:var(--bg);color:var(--fg)}}
h1{{font-size:1.5rem;margin:0 0 .2rem}}h2{{margin:2rem 0 .6rem;font-size:1.15rem;border-bottom:1px solid var(--line);padding-bottom:.3rem}}
h2 small,h1 small{{color:var(--mut);font-weight:400;font-size:.8em}}.meta{{color:var(--mut);font-size:.85rem}}
.cards{{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:.7rem}}
.card{{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:.8rem}}
.card .k{{color:var(--mut);font-size:.8rem}}.card .v{{font-size:1.5rem;font-weight:600;margin-top:.2rem}}
.card .v small{{font-size:.55em;color:var(--mut);font-weight:400}}
table{{border-collapse:collapse;width:100%;font-size:.9rem}}th,td{{text-align:left;padding:.35rem .6rem;border-bottom:1px solid var(--line)}}
th{{color:var(--mut);font-weight:600}}td.r{{text-align:right;font-variant-numeric:tabular-nums}}
.bar{{position:relative;background:var(--line);border-radius:5px;height:16px;min-width:110px}}
.bar .fill{{height:100%;border-radius:5px}}.bar span{{position:absolute;right:6px;top:0;font-size:.72rem;line-height:16px}}
.badge{{font-size:.7rem;font-weight:700;padding:.1rem .35rem;border-radius:4px;color:#fff}}
.badge.ok{{background:#2e7d32}}.badge.bad{{background:#c62828}}
code{{background:var(--card);padding:.05rem .3rem;border-radius:4px}}
</style></head><body>
<h1>AXI4 → 2×APB4 bridge <small>metrics report</small></h1>
{body}
</body></html>"""


# ---------------------------------------------------------------- threshold check
def check_thresholds(out: Path, thresh_file: Path):
    mfile = out / "metrics.json"
    if not mfile.exists():
        print(f"[THRESH] no {mfile}; run `make report` first"); return 2
    m = json.loads(mfile.read_text())
    t = json.loads(thresh_file.read_text())
    cov = m.get("coverage") or {}
    tops = m.get("uvm_tops") or {}
    formal = m.get("formal") or {}
    coc = m.get("cocotb") or {}

    checks = []  # (name, ok, detail)
    if "min_line_coverage_pct" in t:
        v = cov.get("line_pct", 0.0)
        checks.append(("line_coverage", v >= t["min_line_coverage_pct"], f"{v} >= {t['min_line_coverage_pct']}"))
    if "min_branch_coverage_pct" in t:
        v = cov.get("branch_pct", 0.0)
        checks.append(("branch_coverage", v >= t["min_branch_coverage_pct"], f"{v} >= {t['min_branch_coverage_pct']}"))
    if t.get("require_uvm_tops_clean"):
        bad = [k for k, r in tops.items() if r["status"] != "PASS"]
        checks.append(("uvm_tops_clean", not bad, "all PASS" if not bad else f"failing: {bad}"))
    if t.get("require_formal_pass") and formal:
        bad = [k for k, v in formal.items() if v != "PASS"]
        checks.append(("formal_all_pass", not bad, "all PASS" if not bad else f"failing: {bad}"))
    if "min_cocotb_pass_rate" in t and coc:
        tp = sum(1 for ts in coc.values() for x in ts if x["status"] == "PASS")
        tt = sum(len(ts) for ts in coc.values())
        rate = _pct(tp, tt)
        checks.append(("cocotb_pass_rate", rate >= t["min_cocotb_pass_rate"], f"{rate} >= {t['min_cocotb_pass_rate']}"))

    fails = 0
    for name, ok, detail in checks:
        fails += not ok
        print(f"[THRESH] {'PASS' if ok else 'FAIL'}  {name}: {detail}")
    print(f"[THRESH] {'all ' + str(len(checks)) + ' thresholds met' if not fails else str(fails) + ' violated'}")
    return 1 if fails else 0


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--out", default="report")
    ap.add_argument("--env", help="run-environment label (default: auto-detect)")
    ap.add_argument("--check", metavar="THRESHOLDS_JSON",
                    help="evaluate <out>/metrics.json against a thresholds file; nonzero on violation")
    ap.add_argument("--fragment", action="store_true",
                    help="write only <out>/env-<env>.json (this run's per-top metrics) and exit; "
                         "for a container/CI run to contribute to a central compare report")
    a = ap.parse_args()
    root, out = Path(a.root).resolve(), Path(a.out).resolve()
    if a.check:
        raise SystemExit(check_thresholds(out, Path(a.check)))
    out.mkdir(parents=True, exist_ok=True)

    if a.fragment:
        env_name = a.env or detect_env()
        frag = {"env": env_name,
                "generated": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
                "tops": parse_uvm_tops(root)}
        p = out / f"env-{env_name}.json"
        p.write_text(json.dumps(frag, indent=2) + "\n")
        print(f"[REPORT] wrote {p} ({len(frag['tops'])} tops for env '{env_name}')")
        return

    cov = parse_coverage(root)
    tops = parse_uvm_tops(root)
    coc = parse_cocotb(root)
    formal = parse_formal(out / "logs" / "formal.log")
    perf = parse_perf(root / "perf_metrics.txt")
    env_name = a.env or detect_env()
    environments = merge_environments(out, env_name, tops)

    m = build_metrics(git_sha=git_sha(root), run_env=env_name, coverage=cov,
                      uvm_tops=tops, environments=environments, formal=formal,
                      cocotb={g: t for g, t in coc.items()}, performance=perf)
    (out / "metrics.json").write_text(json.dumps(m, indent=2) + "\n")
    (out / "report.md").write_text(build_md(m) + "\n")
    (out / "report.html").write_text(build_html(m))

    cpct = f"{cov['line_pct']}%" if cov else "n/a"
    print(f"[REPORT] wrote {out}/metrics.json, report.md, report.html  "
          f"(env={env_name} coverage={cpct} uvm_tops={len(tops)} "
          f"envs={len(environments)} formal={len(formal)} "
          f"cocotb_groups={len(coc)} perf={'y' if perf else 'n'})")


if __name__ == "__main__":
    main()
