# Python 3.8 / Debian bookworm — lxml+xmlsec são recompiladas contra libs do sistema (mais estável que wheel misto na PyPI).
FROM python:3.8-slim-bookworm

ENV POETRY_VERSION=1.8.5 \
    POETRY_NO_INTERACTION=1 \
    POETRY_VIRTUALENVS_IN_PROJECT=false \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Runtime + headers so lxml+xmlsec rebuild against the same system libxml2/libxmlsec1 (manylinux wheels can still mismatch).
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl \
    libxml2 libxslt1.1 libxmlsec1 libxmlsec1-openssl openssl \
    libxml2-dev libxslt1-dev libxmlsec1-dev \
    zlib1g-dev pkg-config build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY pyproject.toml poetry.lock poetry.toml README.md /workspace/
COPY pytrustnfe /workspace/pytrustnfe
COPY tests /workspace/tests

RUN pip install "poetry==${POETRY_VERSION}" \
    && poetry install --with dev \
    && poetry run python - <<'PY'
import subprocess
import sys

from pkg_resources import get_distribution

lv = get_distribution("lxml").version
xv = get_distribution("xmlsec").version
subprocess.check_call(
    [
        sys.executable,
        "-m",
        "pip",
        "install",
        "--no-cache-dir",
        "--force-reinstall",
        "--no-binary=lxml",
        "--no-binary=xmlsec",
        f"lxml=={lv}",
        f"xmlsec=={xv}",
    ]
)
PY

RUN poetry run python -c "import lxml, xmlsec; print('xml stack ok', lxml.__version__)" \
    && poetry run pytest -q --tb=no

CMD ["poetry", "run", "pytest", "-q"]
