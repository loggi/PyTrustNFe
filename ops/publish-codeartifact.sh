#!/usr/bin/env bash
# Publish pytrustnfe3 to AWS CodeArtifact (PyPI-compatible repo «loggi»).
#
# Prerequisites:
#   - AWS CLI v2 logged in (e.g. `aws sso login --profile …` or env credentials)
#   - `make dist` already ran if you publish without --build (expects ./dist artifacts)
#
# Typical local flow: build wheels into ./dist then upload:
#   make dist && make publish-ca
#
# Or build inside publish:
#   make publish-ca-build
#
# Env overrides:
#   AWS_PROFILE                    (default: platform-prod-sso)
#   CODEARTIFACT_DOMAIN            (default: loggi)
#   CODEARTIFACT_DOMAIN_OWNER      (default: 550903664601, same as xproto)
#   CODEARTIFACT_REGION            (default: us-east-1)
#   POETRY_PUBLISH_REPOSITORY      (default: loggi)
#   POETRY_HTTP_BASIC_LOGGI_USERNAME  (default: aws — CodeArtifact convention)
#   CODEARTIFACT_REPO_URL          optional: override poetry.toml publish URL for this run

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

AWS_PROFILE="${AWS_PROFILE:-platform-prod-sso}"
export AWS_PROFILE

DOMAIN="${CODEARTIFACT_DOMAIN:-loggi}"
OWNER="${CODEARTIFACT_DOMAIN_OWNER:-550903664601}"
REGION="${CODEARTIFACT_REGION:-us-east-1}"
REPO_NAME="${POETRY_PUBLISH_REPOSITORY:-loggi}"

if [[ -n "${CODEARTIFACT_REPO_URL:-}" ]]; then
  poetry config "repositories.${REPO_NAME}" "${CODEARTIFACT_REPO_URL}"
fi

TOKEN="$(
  aws codeartifact get-authorization-token \
    --domain "${DOMAIN}" \
    --domain-owner "${OWNER}" \
    --region "${REGION}" \
    --query authorizationToken \
    --output text
)"

export POETRY_HTTP_BASIC_LOGGI_USERNAME="${POETRY_HTTP_BASIC_LOGGI_USERNAME:-aws}"
export POETRY_HTTP_BASIC_LOGGI_PASSWORD="${TOKEN}"

MODE_BUILD=0
EXTRA_POETRY_PUBLISH_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build)
      MODE_BUILD=1
      shift
      ;;
    --repository|-r)
      EXTRA_POETRY_PUBLISH_ARGS+=("$1" "$2")
      shift 2
      ;;
    *)
      EXTRA_POETRY_PUBLISH_ARGS+=("$1")
      shift
      ;;
  esac
done

if (( MODE_BUILD )); then
  poetry publish --build --repository "${REPO_NAME}" "${EXTRA_POETRY_PUBLISH_ARGS[@]}"
else
  poetry publish --repository "${REPO_NAME}" "${EXTRA_POETRY_PUBLISH_ARGS[@]}"
fi
