# Kairos API - the as-is image (plan WP2.1, SV-09). Every line below is deliberate:
#   - python:latest is a mutable tag (Hadolint DL3007; a new Python can arrive with any rebuild);
#   - no USER, so the API runs as root;
#   - a secret in ENV stays readable in the image's layers and in `docker inspect`;
#   - the development tools are installed too, and nothing is hardened or limited.
# WP4.5 replaces it with a multi-stage build on a pinned slim base, a fixed non-root user, no secret.
FROM python:latest

ENV ADMIN_API_KEY=kairos-admin-key-2026
ENV UV_PYTHON_DOWNLOADS=never
ENV PATH="/app/.venv/bin:$PATH"

WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN pip install uv && uv sync --frozen

COPY . .
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
