#!/usr/bin/env python3
"""Mirror the IEEE 1685-2014 (IP-XACT) XML schema for offline validation.

Downloads index.xsd and every schema it pulls in through xs:include / xs:import
(followed recursively), rewriting each schemaLocation to a local file name so
`xmllint --schema <dir>/index.xsd` works with no network access.

Usage:  scripts/fetch_ipxact_xsd.py <out-dir> [root-url]
Then:   IPXACT_XSD=<out-dir>/index.xsd make pkg

Used by CI (the synth job and the Release workflow), which have network
access; the schema is not vendored into the repo. A completed mirror is marked
with <out-dir>/.complete (file list + SHA-256) and reused as-is, so CI can cache
the directory and stop depending on the schema host after one good fetch.

Every download must actually be an XML Schema: the host sometimes answers with
an HTML page, so each file is checked and retried with backoff before failing.
"""
import hashlib
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

DEFAULT_ROOT = "http://www.accellera.org/XMLSchema/IPXACT/1685-2014/index.xsd"
LOC_RE = re.compile(r'(<xs:(?:include|import|redefine)\b[^>]*?\bschemaLocation=")([^"]+)(")')


def local_name(url: str) -> str:
    """Flatten a URL to a unique, filesystem-safe file name."""
    p = urllib.parse.urlparse(url)
    return (p.netloc + p.path).replace("/", "__")


SCHEMA_RE = re.compile(r"<(?:xs|xsd):schema\b")


def fetch(url: str, attempts: int = 5) -> str:
    """Download one schema file; retry until it really is an XML Schema."""
    last = ""
    for i in range(attempts):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "ipxact-xsd-mirror"})
            with urllib.request.urlopen(req, timeout=60) as r:
                text = r.read().decode("utf-8", errors="replace")
            if SCHEMA_RE.search(text):
                return text
            last = "response is not an XML Schema (starts: %r)" % text.lstrip()[:60]
        except Exception as e:  # network error, HTTP error, timeout
            last = repr(e)
        wait = 5 * (2 ** i)
        print(f"[XSD] {url}: {last}; retry {i + 1}/{attempts - 1} in {wait}s", file=sys.stderr)
        if i < attempts - 1:
            time.sleep(wait)
    raise SystemExit(f"[XSD] FAIL: could not fetch a valid schema from {url}: {last}")


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    out = Path(sys.argv[1])
    root = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_ROOT
    out.mkdir(parents=True, exist_ok=True)

    marker = out / ".complete"
    if marker.is_file() and (out / "index.xsd").is_file():
        listed = [l.split("  ", 1) for l in marker.read_text().splitlines() if l.strip()]
        ok = all((out / n).is_file() and
                 hashlib.sha256((out / n).read_bytes()).hexdigest() == h for h, n in listed)
        if ok:
            print(f"[XSD] reusing cached mirror in {out}/ ({len(listed)} files, hashes match)")
            return 0
        print("[XSD] cached mirror is incomplete or modified; fetching again")

    todo, done = [root], {}
    while todo:
        url = todo.pop()
        if url in done:
            continue
        text = fetch(url)
        name = "index.xsd" if url == root else local_name(url)
        done[url] = name

        def rewrite(m: "re.Match[str]") -> str:
            dep = urllib.parse.urljoin(url, m.group(2))
            if dep not in done and dep not in todo:
                todo.append(dep)
            dep_name = "index.xsd" if dep == root else local_name(dep)
            return m.group(1) + dep_name + m.group(3)

        (out / name).write_text(LOC_RE.sub(rewrite, text), encoding="utf-8")

    marker.write_text("".join(
        f"{hashlib.sha256((out / n).read_bytes()).hexdigest()}  {n}\n" for n in sorted(done.values())))
    print(f"[XSD] mirrored {len(done)} schema file(s) from {root} into {out}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
