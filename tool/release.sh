#!/usr/bin/env bash
# Prepare a package release: set the pubspec version (and, for liblsl, the
# citation metadata), then print the tag to push.
#
#   tool/release.sh <package> <version>
#   tool/release.sh liblsl 1.0.0
#
# Pushing the printed `<package>-v<version>` tag starts .github/workflows/release.yml,
# which runs the tests and then publishes. Tags without a package prefix are rejected.
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 <package> <version>" >&2
  exit 64
fi

PACKAGE="$1"
VERSION="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.+-]+)?$ ]]; then
  echo "error: '$VERSION' is not a semantic version" >&2
  exit 65
fi

if [ -f "$ROOT/packages/$PACKAGE/pubspec.yaml" ]; then
  PKG_DIR="$ROOT/packages/$PACKAGE"
elif [ -f "$ROOT/apps/$PACKAGE/pubspec.yaml" ]; then
  PKG_DIR="$ROOT/apps/$PACKAGE"
else
  echo "error: no package or app named '$PACKAGE'" >&2
  exit 66
fi

# The tag carries the version without build metadata; pubspec may keep it.
TAG_VERSION="${VERSION%%+*}"

sed -i.bak -E "s/^version: .*/version: $VERSION/" "$PKG_DIR/pubspec.yaml"
rm -f "$PKG_DIR/pubspec.yaml.bak"
echo "Set $PACKAGE pubspec version to $VERSION"

if [ "$PACKAGE" = "liblsl" ]; then
  TODAY="$(date -u +%Y-%m-%d)"
  VERSION="$TAG_VERSION" TODAY="$TODAY" ROOT="$ROOT" python3 - <<'PYEOF'
import json, os, re

root, version, today = os.environ["ROOT"], os.environ["VERSION"], os.environ["TODAY"]

path = os.path.join(root, "CITATION.cff")
with open(path) as f:
    text = f.read()
text = re.sub(r'(?m)^version: .*$', f'version: "{version}"', text)
text = re.sub(r'(?m)^date-released: .*$', f'date-released: "{today}"', text)
with open(path, "w") as f:
    f.write(text)

for name, keys in [
    ("codemeta.json", {
        "version": version,
        "dateModified": today,
        "downloadUrl": f"https://pub.dev/api/archives/liblsl-{version}.tar.gz",
    }),
    (".zenodo.json", {"version": version}),
]:
    path = os.path.join(root, name)
    with open(path) as f:
        data = json.load(f)
    data.update(keys)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")

print(f"Set CITATION.cff, codemeta.json and .zenodo.json to {version} ({today})")
PYEOF
fi

if ! grep -qE "^#+ *\[?$VERSION\]?" "$PKG_DIR/CHANGELOG.md" 2>/dev/null; then
  echo "warning: no '# $VERSION' heading in $PKG_DIR/CHANGELOG.md; the release notes will be empty" >&2
fi

cat <<MSG

Next:
  git commit -am "chore: release $PACKAGE $VERSION"
  git push
  git tag $PACKAGE-v$TAG_VERSION
  git push origin $PACKAGE-v$TAG_VERSION
MSG
