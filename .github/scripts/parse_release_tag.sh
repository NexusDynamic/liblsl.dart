#!/usr/bin/env bash
# Resolve a release tag (`<package>-v<version>`) to the package it releases and
# check that the repository agrees with it. Writes key=value lines to
# $GITHUB_OUTPUT (or stdout when unset).
#
#   .github/scripts/parse_release_tag.sh liblsl-v1.0.0
set -euo pipefail

TAG="${1:?usage: $0 <tag>}"
OUT="${GITHUB_OUTPUT:-/dev/stdout}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

fail() { echo "::error::$*" >&2; exit 1; }

if ! [[ "$TAG" =~ ^([a-z][a-z0-9_]*)-v([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?)$ ]]; then
  fail "Tag '$TAG' is not of the form <package>-v<major>.<minor>.<patch>. Unscoped tags (v1.2.3) are not released."
fi
PACKAGE="${BASH_REMATCH[1]}"
VERSION="${BASH_REMATCH[2]}"
PRERELEASE=false
[ -n "${BASH_REMATCH[3]}" ] && PRERELEASE=true

if [ -f "$ROOT/packages/$PACKAGE/pubspec.yaml" ]; then
  REL_PATH="packages/$PACKAGE"
  IS_APP=false
elif [ -f "$ROOT/apps/$PACKAGE/pubspec.yaml" ]; then
  REL_PATH="apps/$PACKAGE"
  IS_APP=true
else
  fail "Tag '$TAG' names '$PACKAGE', which is not a package in packages/ or apps/."
fi
PUBSPEC="$ROOT/$REL_PATH/pubspec.yaml"

NAME="$(sed -nE 's/^name:[[:space:]]*([^[:space:]#]+).*/\1/p' "$PUBSPEC" | head -n1)"
[ "$NAME" = "$PACKAGE" ] || fail "$REL_PATH/pubspec.yaml is named '$NAME', not '$PACKAGE'."

# Build metadata (+N) is not part of the tag.
PUBSPEC_VERSION="$(sed -nE 's/^version:[[:space:]]*([^[:space:]#]+).*/\1/p' "$PUBSPEC" | head -n1)"
[ "${PUBSPEC_VERSION%%+*}" = "$VERSION" ] ||
  fail "$REL_PATH/pubspec.yaml has version '$PUBSPEC_VERSION' but the tag is '$VERSION'. Run tool/release.sh $PACKAGE $VERSION first."

if grep -qE "^publish_to:[[:space:]]*['\"]?none" "$PUBSPEC"; then
  PUBLISHABLE=false
else
  PUBLISHABLE=true
fi

if [ "$PACKAGE" = "liblsl" ]; then
  CFF_VERSION="$(sed -nE 's/^version:[[:space:]]*"?([^"[:space:]]+)"?.*/\1/p' "$ROOT/CITATION.cff")"
  META_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$ROOT/codemeta.json")"
  ZENODO_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$ROOT/.zenodo.json")"
  for pair in "CITATION.cff:$CFF_VERSION" "codemeta.json:$META_VERSION" ".zenodo.json:$ZENODO_VERSION"; do
    [ "${pair#*:}" = "$VERSION" ] ||
      fail "${pair%%:*} has version '${pair#*:}' but the tag is '$VERSION'. Run tool/release.sh liblsl $VERSION first."
  done
fi

{
  echo "package=$PACKAGE"
  echo "version=$VERSION"
  echo "path=$REL_PATH"
  echo "is_app=$IS_APP"
  echo "publishable=$PUBLISHABLE"
  echo "prerelease=$PRERELEASE"
} >> "$OUT"
