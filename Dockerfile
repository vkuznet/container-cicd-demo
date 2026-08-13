# syntax=docker/dockerfile:1
#
# py-cicd-demo container image
# Base   : debian:bookworm-slim
# Packs  : curl, python3, pip, and a small set of python libs (numpy, requests)
#
# Built multi-arch (linux/amd64, linux/arm64) by .github/workflows/containers.yml
# and pushed to both Docker Hub and GitHub Container Registry (GHCR).

FROM debian:bookworm-slim AS base

# Avoid interactive prompts and pyc noise during build
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# --- OS packages -------------------------------------------------------
# curl        : demonstrates a non-Python tool baked into the image
#               (also used for the container HEALTHCHECK below)
# python3/pip : runtime for hello.py
# ca-certificates : required for curl/pip to talk to HTTPS endpoints
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        python3 \
        python3-pip \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*

# --- Application ---------------------------------------------------------
WORKDIR /app

# Create an unprivileged user to run the app as (avoid running as root)
RUN useradd --create-home --shell /usr/sbin/nologin appuser

COPY requirements.txt ./

# Install python libraries (numpy + requests) system-wide via a venv,
# since Debian 12 ships pip with PEP 668 "externally managed" protection.
RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --upgrade pip \
    && /opt/venv/bin/pip install -r requirements.txt

ENV PATH="/opt/venv/bin:${PATH}"

COPY hello.py ./

RUN chown -R appuser:appuser /app
USER appuser

# Basic container-level healthcheck exercising curl
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD curl -fsS https://example.com >/dev/null || exit 1

ENTRYPOINT ["python3", "hello.py"]
CMD ["World"]

# --- OCI labels (also set/overridden at build time via --label) ---------
LABEL org.opencontainers.image.title="py-cicd-demo" \
      org.opencontainers.image.description="Minimal demo app: Debian + curl + python3 + numpy" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/vkuznet/py-cicd-demo"
