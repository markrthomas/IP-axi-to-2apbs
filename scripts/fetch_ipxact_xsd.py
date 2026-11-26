#!/usr/bin/env python3
"""Mirror the IEEE 1685-2014 (IP-XACT) XML schema for offline validation.

Downloads index.xsd and every schema it pulls in through xs:include / xs:import
(followed recursively), rewriting each schemaLocation to a local file name so
`xmllint --schema <dir>/index.xsd` works with no network access.

Usage:  scripts/fetch_ipxact_xsd.py <out-dir> [root-url]
Then:   IPXACT_XSD=<out-dir>/index.xsd make pkg

Used by CI (the synth job), which has network access; the schema is not
vendored into the repo.
"""
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

DEFAULT_ROOT = "http://www.accellera.org/XMLSchema/IPXACT/1685-2014/index.xsd"
LOC_RE = re.compile(r'(<xs:(?:include|import|redefine)\b[^>]*?\bschemaLocation=")([^"]+)(")')


def local_name(url: str) -> str:
    """Flatten a URL to a unique, filesystem-safe file name."""
    p = urllib.parse.urlparse(url)
    return (p.netloc + p.path).replace("/", "__")


def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "ipxact-xsd-mirror"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8")


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    out = Path(sys.argv[1])
    root = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_ROOT
    out.mkdir(parents=True, exist_ok=True)

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

    print(f"[XSD] mirrored {len(done)} schema file(s) from {root} into {out}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
