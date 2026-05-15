#!/usr/bin/env bash
# Upload pytrustnfe3 wheel + sdist to Loggi private PEP 503 prefix and refresh index.html.
#
# Prerequisites: run `make docker-dist` (or `poetry build`) so ./dist contains the artifacts
# matching the version in pyproject.toml. AWS SSO: `make aws-sso` or `aws sso login --profile …`.
#
# Env overrides:
#   AWS_PROFILE      (default: platform-root-sso)
#   S3_PKG_PREFIX    (default: s3://pypi.loggi.com/vqouYW66G1Q5LmpcgXGa/pytrustnfe3/)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

AWS_PROFILE="${AWS_PROFILE:-platform-root-sso}"
S3_PKG_PREFIX="${S3_PKG_PREFIX:-s3://pypi.loggi.com/vqouYW66G1Q5LmpcgXGa/pytrustnfe3/}"
DEST="${S3_PKG_PREFIX%/}/"

version_from_pyproject() {
  python3 <<'PY'
import re
from pathlib import Path

text = Path("pyproject.toml").read_text(encoding="utf-8")
m = re.search(r'(?m)^version\s*=\s*"([^"]+)"', text)
if not m:
    raise SystemExit("Could not read version from pyproject.toml")
print(m.group(1))
PY
}

VERSION="$(version_from_pyproject)"

shopt -s nullglob

wheels=(dist/pytrustnfe3-"${VERSION}"-*.whl)
tars=(dist/pytrustnfe3-"${VERSION}".tar.gz)

if ((${#wheels[@]} != 1)); then
  echo "Expected exactly one wheel dist/pytrustnfe3-${VERSION}-*.whl, got: ${wheels[*]:-(none)}"
  exit 1
fi
if ((${#tars[@]} != 1)); then
  echo "Expected exactly one sdist dist/pytrustnfe3-${VERSION}.tar.gz, got: ${tars[*]:-(none)}"
  exit 1
fi

for f in "${wheels[0]}" "${tars[0]}"; do
  echo "Uploading $(basename "$f") -> ${DEST}"
  aws s3 cp "$f" "$DEST" --profile "$AWS_PROFILE"
done

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

echo "Syncing ${DEST} (excluding index.html) …"
aws s3 sync "$DEST" "$tmpdir/" --profile "$AWS_PROFILE" --exclude 'index.html'

{
  echo '<!DOCTYPE html>'
  echo '<html><head><meta charset="UTF-8"><title>Package Index</title></head><body>'
  for f in "$tmpdir"/*.whl "$tmpdir"/*.tar.gz; do
    [[ -f "$f" ]] || continue
    base=$(basename "$f")
    hash=$(sha256sum "$f" | awk '{print $1}')
    echo "<a href=\"${base}#sha256=${hash}\">${base}</a><br>"
  done
  echo '</body></html>'
} >"${tmpdir}/index.html"

echo "Writing ${DEST}index.html"
aws s3 cp "${tmpdir}/index.html" "${DEST}index.html" \
  --profile "$AWS_PROFILE" \
  --content-type 'text/html'

echo "Done."
