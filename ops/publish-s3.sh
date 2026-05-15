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

export AWS_PROFILE INDEX_TMP="$tmpdir"
export PYPI_S3_LIST_PREFIX="$DEST"

# Do not use `aws s3 sync`: this prefix often has nested keys (nfe-sp/, pytrustnfe3/) beside flat wheels.
# Recursive sync hits ENOTDIR when the local layout cannot represent both files and prefixes.
echo "Refreshing PEP 503 index (flat *.whl / *.tar.gz only under ${DEST}) …"
python3 <<'PYINDEX'
import hashlib
import json
import os
import re
import subprocess

dest = os.environ["PYPI_S3_LIST_PREFIX"].rstrip("/") + "/"
tmpdir = os.environ["INDEX_TMP"]
profile = os.environ["AWS_PROFILE"]

m = re.match(r"s3://([^/]+)/(.+)", dest)
if not m:
    raise SystemExit(f"Bad S3 URL: {dest!r}")
bucket, prefix = m.group(1), m.group(2)
if not prefix.endswith("/"):
    prefix += "/"


def aws_json(argv):
    out = subprocess.check_output(["aws", *argv, "--profile", profile, "--output", "json"], text=True)
    return json.loads(out)


keys = []
token = None
while True:
    cmd = ["s3api", "list-objects-v2", "--bucket", bucket, "--prefix", prefix]
    if token:
        cmd += ["--continuation-token", token]
    data = aws_json(cmd)
    for obj in data.get("Contents", []):
        key = obj["Key"]
        if not key.startswith(prefix):
            continue
        rel = key[len(prefix) :]
        if "/" in rel:
            continue
        if rel.endswith(".whl") or rel.endswith(".tar.gz"):
            keys.append(key)
    token = data.get("NextContinuationToken")
    if not token:
        break

keys = sorted(set(keys))

for key in keys:
    base = os.path.basename(key)
    path = os.path.join(tmpdir, base)
    subprocess.check_call(
        ["aws", "s3", "cp", f"s3://{bucket}/{key}", path, "--profile", profile],
        stdout=subprocess.DEVNULL,
    )

lines = [
    "<!DOCTYPE html>",
    '<html><head><meta charset="UTF-8"><title>Package Index</title></head><body>',
]
for key in keys:
    base = os.path.basename(key)
    path = os.path.join(tmpdir, base)
    dig = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            dig.update(chunk)
    digest = dig.hexdigest()
    lines.append(f'<a href="{base}#sha256={digest}">{base}</a><br>')
lines.append("</body></html>")

with open(os.path.join(tmpdir, "index.html"), "w", encoding="utf-8") as fp:
    fp.write("\n".join(lines))

print(f"Indexed {len(keys)} flat artifacts (skipped nested prefixes).")
PYINDEX

echo "Writing ${DEST}index.html"
aws s3 cp "${tmpdir}/index.html" "${DEST}index.html" \
  --profile "$AWS_PROFILE" \
  --content-type 'text/html'

echo "Done."
