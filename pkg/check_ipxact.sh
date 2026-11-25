#!/usr/bin/env bash
# pkg/check_ipxact.sh — T7 packaging gate (OSS pathfinder).
#
# Part of the tapeout-readiness program (../DESIGN_READINESS.md). Validates the
# IP-XACT (IEEE 1685-2014) component descriptions that package this IP. Three checks,
# all real artifacts, no licensed tool required:
#   1. WELL-FORMED   — xmllint parses each component XML.
#   2. STRUCTURAL    — the required IP-XACT elements are present
#                      (vendor/library/name/version, model/ports, busInterfaces).
#   3. RTL-IN-SYNC   — the set of model ports in the IP-XACT EXACTLY matches the RTL
#                      module's port list. This is the check that matters: it fails the
#                      gate if the package drifts from the RTL (a renamed/added/removed
#                      port). Port *widths* are parametric expressions in the XML and are
#                      reviewed against doc/design_contract.md, not re-derived here.
# Full XSD schema validation is an optional extra: set IPXACT_XSD=/path/to/index.xsd to
# enable it (the 1685-2014 schema is not redistributed here). Absent that, a skip is
# reported honestly as "not run", never as a pass.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
cd "$ROOT"

command -v xmllint >/dev/null || { echo "[PKG] xmllint not on PATH — skipping (needs libxml2-utils)"; exit 0; }

# component-xml basename (sans .xml) is the RTL top / module name.
declare -A XML=(
  [axi4_to_apb4_2x_simple]=pkg/ip-xact/axi4_to_apb4_2x_simple.xml
  [axi4_to_apb4_2x_burst]=pkg/ip-xact/axi4_to_apb4_2x_burst.xml
)

rc=0
for TOP in axi4_to_apb4_2x_simple axi4_to_apb4_2x_burst; do
  xml="${XML[$TOP]}"; rtl="src/$TOP.v"
  echo "[PKG] === $TOP ==="
  [ -f "$xml" ] || { echo "[PKG] $TOP: FAIL — missing $xml"; rc=1; continue; }

  # 1) well-formed
  if ! xmllint --noout "$xml" 2>/tmp/_pkg_xmllint.$$; then
    echo "[PKG] $TOP: FAIL — malformed XML:"; cat /tmp/_pkg_xmllint.$$; rm -f /tmp/_pkg_xmllint.$$; rc=1; continue
  fi
  rm -f /tmp/_pkg_xmllint.$$

  # 2) structural — required top-level IP-XACT elements present
  miss=""
  for tag in "ipxact:vendor" "ipxact:library" "ipxact:name" "ipxact:version" "ipxact:busInterfaces" "ipxact:model"; do
    grep -q "<$tag>" "$xml" || miss="$miss $tag"
  done
  if [ -n "$miss" ]; then echo "[PKG] $TOP: FAIL — missing IP-XACT elements:$miss"; rc=1; continue; fi

  # 3) RTL-in-sync — model ports (XML) must equal RTL module ports
  xml_ports="$(grep -oE '<ipxact:port><ipxact:name>[A-Za-z0-9_]+' "$xml" | sed -E 's|.*<ipxact:name>||' | sort -u)"
  rtl_ports="$(awk -v top="$TOP" '
      $0 ~ "^[ \t]*module[ \t]+"top"[ \t]*[#(]" {m=1}
      m && /^[ \t]*(input|output|inout)[ \t]/ {
          s=$0; gsub(/\r/,"",s); sub(/\/\/.*/,"",s); sub(/,[ \t]*$/,"",s);
          n=split(s,a,/[ \t]/); name=a[n]; sub(/\[.*$/,"",name); sub(/[,\r]+$/,"",name);
          if (name ~ /^[A-Za-z_]/) print name
      }
      m && /^[ \t]*\);/ {exit}
  ' "$rtl" | sort -u)"

  if [ "$xml_ports" = "$rtl_ports" ]; then
    nports="$(printf '%s\n' "$xml_ports" | grep -c .)"
    echo "[PKG] $TOP: PASS — well-formed + structural + RTL-in-sync ($nports ports match $rtl)"
  else
    echo "[PKG] $TOP: FAIL — IP-XACT model ports differ from RTL ($rtl):"
    echo "  only in IP-XACT:"; comm -23 <(printf '%s\n' "$xml_ports") <(printf '%s\n' "$rtl_ports") | sed 's/^/    /'
    echo "  only in RTL:";     comm -13 <(printf '%s\n' "$xml_ports") <(printf '%s\n' "$rtl_ports") | sed 's/^/    /'
    rc=1
  fi
done

# optional: full XSD schema validation when a local schema is provided
if [ -n "${IPXACT_XSD:-}" ] && [ -f "${IPXACT_XSD}" ]; then
  echo "[PKG] XSD schema validation against $IPXACT_XSD"
  for TOP in axi4_to_apb4_2x_simple axi4_to_apb4_2x_burst; do
    xmllint --noout --schema "$IPXACT_XSD" "${XML[$TOP]}" || rc=1
  done
else
  echo "[PKG] XSD schema validation: not run (set IPXACT_XSD to the 1685-2014 index.xsd to enable) — this is 'not run', not a pass."
fi

[ $rc -eq 0 ] && echo "[PKG] T7 packaging gate PASSED (IP-XACT well-formed + structural + in sync with RTL)."
exit $rc
