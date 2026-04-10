# ─────────────────────────────────────────────
# Stage 1: Build
# ─────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build

# Install only what's needed to build
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential=12.* \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --upgrade pip --no-cache-dir \
    && pip install --prefix=/install --no-cache-dir -r requirements.txt

# ─────────────────────────────────────────────
# Stage 2: Runtime — minimal attack surface
# ─────────────────────────────────────────────
FROM python:3.12-slim AS runtime

LABEL org.opencontainers.image.title="secure-app" \
      org.opencontainers.image.description="Security-gated CI/CD demo application" \
      org.opencontainers.image.vendor="your-org" \
      org.opencontainers.image.source="https://github.com/cercuit/fullstack-ci-cd" \

# Build-time metadata (injected by pipeline)
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION
LABEL org.opencontainers.image.created=$BUILD_DATE \
      org.opencontainers.image.revision=$VCS_REF \
      org.opencontainers.image.version=$VERSION

# Create non-root user
RUN groupadd --gid 1000 appgroup \
    && useradd --uid 1000 --gid appgroup --shell /bin/sh --create-home appuser

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Copy application source
COPY --chown=appuser:appgroup src/ .

# Remove package manager caches and tools not needed at runtime
RUN apt-get update && apt-get remove -y --purge \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && find /usr/local/lib -name "*.pyc" -delete \
    && find /usr/local/lib -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

# Drop to non-root
USER 1000:1000

EXPOSE 8080

# Health check (ECS uses ALB health check, this is a secondary safeguard)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

# Read-only filesystem at runtime — write only to /tmp
VOLUME ["/tmp"]

CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080", "--no-access-log"]
