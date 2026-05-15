IMAGE ?= pytrustnfe-build

.PHONY: docker-build docker-test docker-shell docker-wheel

docker-build:
	docker build -t $(IMAGE) .

docker-test:
	docker run --rm $(IMAGE) poetry run pytest -q

docker-shell:
	docker run --rm -it $(IMAGE) bash -il

docker-wheel:
	@mkdir -p dist
	docker run --rm -v "$(CURDIR)/dist:/out" $(IMAGE) sh -eu -c "\
	  poetry build && cp dist/*.whl /out/"
