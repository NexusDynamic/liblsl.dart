#!/usr/bin/env bash
# Print the CHANGELOG.md section for one version (the lines under its heading,
# up to the next heading of the same or higher level).
#
#   .github/scripts/changelog_section.sh packages/liblsl/CHANGELOG.md 1.0.0
set -euo pipefail

FILE="${1:?usage: $0 <CHANGELOG.md> <version>}"
VERSION="${2:?usage: $0 <CHANGELOG.md> <version>}"

[ -f "$FILE" ] || exit 0

awk -v version="$VERSION" '
  function heading_level(line) { match(line, /^#+/); return RLENGTH }
  function heading_version(line,   v) {
    v = line
    sub(/^#+[[:space:]]*\[?v?/, "", v)
    sub(/[]+[:space:]].*$/, "", v)
    return v
  }
  /^#+[[:space:]]/ {
    if (in_section && heading_level($0) <= level) exit
    if (!in_section && heading_version($0) == version) {
      in_section = 1
      level = heading_level($0)
      next
    }
  }
  in_section { print }
' "$FILE"
