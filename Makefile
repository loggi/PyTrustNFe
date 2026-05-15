IMAGE ?= pytrustnfe-build

AWS_PROFILE ?= platform-root-sso
# Trailing slash optional; normalize in ops/publish-s3.sh
PYPI_PYTRUSTNFES3_PREFIX ?= s3://pypi.loggi.com/vqouYW66G1Q5LmpcgXGa/pytrustnfe3/

.PHONY: docker-build docker-test docker-shell docker-dist docker-wheel publish-s3 aws-sso

docker-build:
	docker build -t $(IMAGE) .

docker-test:
	docker run --rm $(IMAGE) poetry run pytest -q

docker-shell:
	docker run --rm -it $(IMAGE) bash -il

# Build wheel + sdist inside the image and copy both into ./dist
docker-dist:
	@mkdir -p dist
	docker run --rm -v "$(CURDIR)/dist:/out" $(IMAGE) sh -eu -c "\
	  poetry build && cp dist/pytrustnfe3-*.whl /out/ && cp dist/pytrustnfe3-*.tar.gz /out/"

# Alias kept for callers that only cared about wheels; uploads should use both artifacts.
docker-wheel: docker-dist

# AWS SSO session (interactive). Run once before publish-s3 when the profile session expired.
aws-sso:
	aws sso login --profile $(AWS_PROFILE)

# Requires: docker-dist (or poetry build locally), aws CLI, and a valid SSO session for AWS_PROFILE.
publish-s3:
	@AWS_PROFILE="$(AWS_PROFILE)" S3_PKG_PREFIX="$(PYPI_PYTRUSTNFES3_PREFIX)" \
	  bash "$(CURDIR)/ops/publish-s3.sh"
