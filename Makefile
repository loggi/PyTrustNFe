IMAGE ?= pytrustnfe-build

AWS_PROFILE ?= platform-prod-sso

CODEARTIFACT_DOMAIN ?= loggi
CODEARTIFACT_DOMAIN_OWNER ?= 550903664601
CODEARTIFACT_REGION ?= us-east-1

.PHONY: build test shell dist wheel publish-release publish-ca publish-ca-build aws-sso

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

# Alias kept for callers that only cared about wheels.
wheel: dist

aws-sso:
	aws sso login --profile $(AWS_PROFILE)

# Set CalVer in pyproject, then CodeArtifact publish (build+wheels). Usage: make publish-release VERSION=20260515.02
publish-release:
	@test -n "$(VERSION)" || (echo "usage: make publish-release VERSION=YYYYMMDD.XX" >&2; exit 1)
	poetry version "$(VERSION)"
	$(MAKE) publish-ca-build

# Publish ./dist/* to AWS CodeArtifact (build first: `make dist` or pass --build targets below).
publish-ca:
	AWS_PROFILE="$(AWS_PROFILE)" \
	CODEARTIFACT_DOMAIN="$(CODEARTIFACT_DOMAIN)" \
	CODEARTIFACT_DOMAIN_OWNER="$(CODEARTIFACT_DOMAIN_OWNER)" \
	CODEARTIFACT_REGION="$(CODEARTIFACT_REGION)" \
	  bash "$(CURDIR)/ops/publish-codeartifact.sh"

publish-ca-build:
	AWS_PROFILE="$(AWS_PROFILE)" \
	CODEARTIFACT_DOMAIN="$(CODEARTIFACT_DOMAIN)" \
	CODEARTIFACT_DOMAIN_OWNER="$(CODEARTIFACT_DOMAIN_OWNER)" \
	CODEARTIFACT_REGION="$(CODEARTIFACT_REGION)" \
	  bash "$(CURDIR)/ops/publish-codeartifact.sh" --build
