#!/usr/bin/env python3
"""Build the versioned IP release bundle (tapeout-readiness T7).

    scripts/make_release.py --version 1.0.0 [--out dist] [--allow-dirty]
    scripts/make_release.py --verify dist/<name>-<version>.tar.gz

Build: collects the deliverable files (RTL, IP-XACT, integration guide, design
contract, constraint/power/plan collateral, sign-off table) plus any generated
gate reports already present (syn/**/reports/, from `make syn dft gls ppa`),
writes MANIFEST.json (SHA-256 per file, source commit, contract tag, gate
status parsed from syn/SIGNOFF.md, tool versions) and packs a deterministic
tar.gz: sorted entries, fixed mtime (= source commit time), uid/gid 0.
A <bundle>.sha256 file is written next to it.

Verify: unpacks the bundle and checks every file against MANIFEST.json.

The bundle is a snapshot of tracked files at HEAD; a dirty working tree is
refused unless --allow-dirty (then the manifest records "dirty": true).
"""
import argparse
import gzip
import hashlib
import io
import json
import re
import subprocess
import sys
import tarfile
from pathlib import Path

NAME = "axi4-to-2apbs"
ROOT = Path(__file__).resolve().parent.parent

# Deliverable files, each with its role in the release. All are required.
DELIVERABLES = [
    ("src/axi4_to_apb4_2x_simple.v",          "rtl"),
    ("src/axi4_to_apb4_2x_burst.v",           "rtl"),
    ("src/axi3lite_regblock.v",               "rtl-example"),
    ("pkg/ip-xact/axi4_to_apb4_2x_simple.xml", "ip-xact"),
    ("pkg/ip-xact/axi4_to_apb4_2x_burst.xml",  "ip-xact"),
    ("pkg/INTEGRATION.md",                    "doc"),
    ("pkg/README.md",                         "doc"),
    ("pkg/RELEASE.md",                        "doc"),
    ("doc/design_contract.md",                "contract"),
    ("syn/SIGNOFF.md",                        "signoff"),
    ("syn/constraints/axi_apb.sdc",           "constraints"),
    ("syn/sta/opensta.tcl",                   "constraints"),
    ("syn/lp/axi_apb.upf",                    "power-intent"),
    ("syn/lp/LP_PLAN.md",                     "plan"),
    ("syn/dft/DFT_PLAN.md",                   "plan"),
    ("syn/gls/T6_PLAN.md",                    "plan"),
    ("README.md",                             "doc"),
    ("LICENSE",                               "license"),
]
REPORT_GLOB = "syn/**/reports/*"
CONTRACT_TAG = "contract-v1.0"


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, check=True,
                          capture_output=True, text=True).stdout.strip()


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def tool_version(cmd: list) -> str:
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
        return (out.stdout or out.stderr).strip().splitlines()[0]
    except Exception:
        return "not available"


def gate_status() -> dict:
    """Gate -> status cell, from the table in syn/SIGNOFF.md."""
    gates = {}
    for line in (ROOT / "syn/SIGNOFF.md").read_text(encoding="utf-8").splitlines():
        m = re.match(r"\|\s*\*\*(T\d)\*\*[^|]*\|\s*([^|]+?)\s*\|", line)
        if m:
            gates[m.group(1)] = re.sub(r"\*\*", "", m.group(2))
    return gates


def contract_info() -> dict:
    info = {"tag": CONTRACT_TAG, "commit": None}
    try:
        info["commit"] = git("rev-list", "-n", "1", CONTRACT_TAG)
    except subprocess.CalledProcessError:
        pass  # shallow CI checkouts may not have tags; the doc still pins it
    m = re.search(r"\*\*Contract version\*\*\s*\|\s*`([^`]+)`",
                  (ROOT / "doc/design_contract.md").read_text(encoding="utf-8"))
    info["version"] = m.group(1) if m else None
    return info


def build(version: str, out: Path, allow_dirty: bool) -> Path:
    if not re.fullmatch(r"\d+\.\d+\.\d+([-+][0-9A-Za-z.-]+)?", version):
        sys.exit(f"[REL] FAIL: version '{version}' is not semver (e.g. 1.0.0)")
    dirty = bool(git("status", "--porcelain", "--untracked-files=no"))
    if dirty and not allow_dirty:
        sys.exit("[REL] FAIL: working tree has uncommitted changes (use --allow-dirty for a test build)")

    missing = [p for p, _ in DELIVERABLES if not (ROOT / p).is_file()]
    if missing:
        sys.exit("[REL] FAIL: missing deliverables: " + ", ".join(missing))
    untracked = [p for p, _ in DELIVERABLES
                 if subprocess.run(["git", "ls-files", "--error-unmatch", p], cwd=ROOT,
                                   capture_output=True).returncode != 0]
    if untracked:
        sys.exit("[REL] FAIL: deliverables not tracked by git: " + ", ".join(untracked))

    files = [(p, kind) for p, kind in DELIVERABLES]
    reports = sorted(str(p.relative_to(ROOT)) for p in ROOT.glob(REPORT_GLOB) if p.is_file())
    files += [(p, "gate-report") for p in reports]

    commit = git("rev-parse", "HEAD")
    mtime = int(git("show", "-s", "--format=%ct", "HEAD"))
    prefix = f"{NAME}-{version}"

    entries = []
    for path, kind in sorted(files):
        data = (ROOT / path).read_bytes()
        entries.append({"path": path, "kind": kind, "bytes": len(data), "sha256": sha256(data)})

    manifest = {
        "name": NAME,
        "version": version,
        "source": {"repo": "markrthomas/IP-axi-to-2apbs", "commit": commit, "dirty": dirty,
                   "commit_time_unix": mtime},
        "contract": contract_info(),
        "gates": gate_status(),
        "gate_reports_included": bool(reports),
        "tools": {"yosys": tool_version(["yosys", "-V"]),
                  "iverilog": tool_version(["iverilog", "-V"]),
                  "xmllint": tool_version(["xmllint", "--version"])},
        "files": entries,
    }
    man_bytes = (json.dumps(manifest, indent=2) + "\n").encode()

    out.mkdir(parents=True, exist_ok=True)
    bundle = out / f"{prefix}.tar.gz"
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.PAX_FORMAT) as tar:
        def add(arc: str, data: bytes) -> None:
            ti = tarfile.TarInfo(f"{prefix}/{arc}")
            ti.size, ti.mtime, ti.mode = len(data), mtime, 0o644
            ti.uid = ti.gid = 0
            ti.uname = ti.gname = ""
            tar.addfile(ti, io.BytesIO(data))
        add("MANIFEST.json", man_bytes)
        for e in entries:
            add(e["path"], (ROOT / e["path"]).read_bytes())
    # gzip with a fixed header mtime so the bundle is byte-reproducible
    with open(bundle, "wb") as fh, gzip.GzipFile(filename="", mode="wb", fileobj=fh, mtime=mtime) as gz:
        gz.write(buf.getvalue())
    digest = sha256(bundle.read_bytes())
    (out / f"{prefix}.tar.gz.sha256").write_text(f"{digest}  {bundle.name}\n")
    print(f"[REL] built {bundle} ({len(entries)} files, {len(reports)} gate reports, "
          f"commit {commit[:7]}{' DIRTY' if dirty else ''})")
    print(f"[REL] sha256 {digest}")
    return bundle


def verify(bundle: Path) -> int:
    rc = 0
    with tarfile.open(bundle, "r:gz") as tar:
        names = [m.name for m in tar.getmembers() if m.isfile()]   # ignore dir entries
        prefix = names[0].split("/")[0]
        man = json.load(tar.extractfile(f"{prefix}/MANIFEST.json"))
        listed = {f"{prefix}/{e['path']}" for e in man["files"]} | {f"{prefix}/MANIFEST.json"}
        extra = sorted(set(names) - listed)
        if extra:
            print("[REL] FAIL: files in bundle but not in manifest: " + ", ".join(extra)); rc = 1
        for e in man["files"]:
            member = f"{prefix}/{e['path']}"
            if member not in names:
                print(f"[REL] FAIL: {e['path']} listed but missing"); rc = 1; continue
            data = tar.extractfile(member).read()
            if sha256(data) != e["sha256"] or len(data) != e["bytes"]:
                print(f"[REL] FAIL: {e['path']} hash/size mismatch"); rc = 1
        kinds = {e["kind"] for e in man["files"]}
        for need in ("rtl", "ip-xact", "contract", "signoff"):
            if need not in kinds:
                print(f"[REL] FAIL: no '{need}' file in bundle"); rc = 1
    if rc == 0:
        print(f"[REL] verify PASS: {bundle.name}: {len(man['files'])} files match MANIFEST.json "
              f"(version {man['version']}, commit {man['source']['commit'][:7]}, "
              f"contract {man['contract'].get('version')})")
    return rc


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--version")
    ap.add_argument("--out", default=str(ROOT / "dist"))
    ap.add_argument("--allow-dirty", action="store_true")
    ap.add_argument("--verify", metavar="BUNDLE")
    a = ap.parse_args()
    if a.verify:
        return verify(Path(a.verify))
    if not a.version:
        ap.error("--version is required to build")
    build(a.version, Path(a.out), a.allow_dirty)
    return 0


if __name__ == "__main__":
    sys.exit(main())
