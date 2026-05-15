IMAGE ?= pytrustnfe-build

AWS_PROFILE ?= platform-root-sso
# Trailing slash optional; normalize in ops/publish-s3.sh
PYPI_PYTRUSTNFES3_PREFIX ?= s3://pypi.loggi.com/vqouYW66G1Q5LmpcgXGa/pytrustnfe3/

.PHONY: build test shell dist wheel publish-s3 aws-sso

build:
	docker build -t $(IMAGE) .

test:
	docker run --rm $(IMAGE) poetry run pytest -q

shell:
	docker run --rm -it $(IMAGE) bash -il

# Build wheel + sdist inside the image and copy both into ./dist
dist:
	@mkdir -p dist
	docker run --rm -v "$(CURDIR)/dist:/out" $(IMAGE) sh -eu -c "\
	  poetry build && cp dist/pytrustnfe3-*.whl /out/ && cp dist/pytrustnfe3-*.tar.gz /out/"

# Alias kept for callers that only cared about wheels; uploads should use both artifacts.
wheel: dist

# AWS SSO session (interactive). Run once before publish-s3 when the profile session expired.
aws-sso:
	aws sso login --profile $(AWS_PROFILE)

# Requires: `make dist` (or `poetry build` locally), aws CLI, and SSO for AWS_PROFILE.
publish-s3:
	@AWS_PROFILE="$(AWS_PROFILE)" S3_PKG_PREFIX="$(PYPI_PYTRUSTNFES3_PREFIX)" \
	  bash "$(CURDIR)/ops/publish-s3.sh"
