#!/usr/bin/env bash
# Prepare a package release: set the pubspec version (and, for liblsl, the
# citation metadata; for an app, the download links in the READMEs).
#
#   tool/release.sh <package> <version> [--cascade]
#
# The work is done by tool/release.dart, which can also show what is pending
# and push the tags; see "Releases (maintainers)" in CONTRIBUTING.md.
set -euo pipefail
cd "$(dirname "$0")/.."
exec dart run tool/release.dart bump "$@"
