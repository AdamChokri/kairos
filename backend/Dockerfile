# Kairos API (plan WP4.5, SV-09 fixed). Two stages on the pinned slim Python image of ci/tools/tools.lock:
#   build    installs the locked production dependencies into /opt/venv (no development tools, no cache);
#   runtime  copies that virtual environment and the application and runs as UID 10001. The image holds
#            no secret: the signing key and the database password are files mounted at run time (SV-01).
# It is meant to run with a read-only root filesystem and no capability (deploy/compose.yaml).
FROM python:3.13.18-slim-trixie@sha256:76baad6037690d6e8c4397fbcaef17bca6f19eecef822b708fe8fa3417d30bb5 AS build

ENV UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy
WORKDIR /src
RUN pip install --no-cache-dir uv==0.13.6
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

FROM python:3.13.18-slim-trixie@sha256:76baad6037690d6e8c4397fbcaef17bca6f19eecef822b708fe8fa3417d30bb5

ARG GIT_SHA=dev
RUN groupadd --system --gid 10001 kairos \
    && useradd --system --uid 10001 --gid 10001 --no-create-home --home-dir /nonexistent \
        --shell /usr/sbin/nologin kairos
COPY --from=build /opt/venv /opt/venv
WORKDIR /app
COPY app ./app
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    GIT_SHA=${GIT_SHA}
USER 10001:10001
EXPOSE 8000
HEALTHCHECK --interval=10s --timeout=4s --start-period=20s --retries=5 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=3)"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
