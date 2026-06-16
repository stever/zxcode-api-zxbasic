# Build Python deps into an isolated venv so the runtime image carries no
# compiler toolchain (gcc stays in this stage only).
FROM python:3.9-slim-bookworm AS builder
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc \
    && rm -rf /var/lib/apt/lists/*
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"
COPY requirements.txt .
# Pin pip to the pre-24.1 era: the ancient FastAPI/uvicorn stack has legacy
# metadata that pip >= 24.1 rejects. (The durable fix is modernising the deps.)
RUN pip install --no-cache-dir "pip<24.1" \
    && pip install --no-cache-dir -r requirements.txt

# Runtime: minimal official slim base, no build tools.
# Replaces the archived tiangolo/uvicorn-gunicorn-fastapi image.
# NOTE: Python 3.9 is EOL (upstream fixes ended Oct 2025); kept to match the
# tested FastAPI 0.61 / Pydantic v1 stack. Moving to 3.12 + current FastAPI /
# Pydantic v2 is a separate, test-gated change.
FROM python:3.9-slim-bookworm

COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1

# Non-root, no login shell.
RUN groupadd -g 1000 zxbasic \
    && useradd -r -u 1000 -g zxbasic -m -d /home/zxbasic -s /usr/sbin/nologin zxbasic

WORKDIR /app
COPY --chown=zxbasic:zxbasic . /app/
# zxbc writes the compiled .tap into the working dir, so /app itself must be
# writable by the non-root user (WORKDIR creates the dir owned by root).
RUN chown zxbasic:zxbasic /app
USER zxbasic

EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:80/health', timeout=3).status==200 else 1)"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "80"]
