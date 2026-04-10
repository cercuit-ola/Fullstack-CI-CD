"""
secure-app — FastAPI application
Secrets are injected as environment variables by ECS from AWS Secrets Manager.
No secrets are ever hardcoded or logged.
"""

import os
import logging
import time
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse
import uvicorn

# ─────────────────────────────────────────────
# Structured logging — never log secret values
# ─────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format='{"time": "%(asctime)s", "level": "%(levelname)s", "msg": "%(message)s"}',
)
logger = logging.getLogger(__name__)

START_TIME = time.time()


@asynccontextmanager
async def lifespan(application: FastAPI):
    logger.info("Application starting up")
    # Validate required secrets are present (do NOT log their values)
    required_env = ["APP_ENV"]
    missing = [k for k in required_env if not os.getenv(k)]
    if missing:
        logger.warning(f"Missing environment variables: {missing}")
    yield
    logger.info("Application shutting down")


app = FastAPI(
    title="secure-app",
    version=os.getenv("VERSION", "0.0.0"),
    docs_url=None if os.getenv("APP_ENV") == "prod" else "/docs",
    redoc_url=None,
    lifespan=lifespan,
)


# ─────────────────────────────────────────────
# Security headers middleware
# ─────────────────────────────────────────────
@app.middleware("http")
async def security_headers(request: Request, call_next) -> Response:
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["Cache-Control"] = "no-store"
    # Remove server header
    response.headers.pop("server", None)
    return response


# ─────────────────────────────────────────────
# Routes
# ─────────────────────────────────────────────
@app.get("/health", include_in_schema=False)
async def health() -> dict[str, Any]:
    """ECS + ALB health check endpoint."""
    return {
        "status": "healthy",
        "uptime_seconds": round(time.time() - START_TIME, 1),
        "environment": os.getenv("APP_ENV", "unknown"),
    }


@app.get("/")
async def root() -> dict[str, str]:
    return {"message": "OK", "env": os.getenv("APP_ENV", "unknown")}


if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=int(os.getenv("PORT", "8080")),
        log_level="info",
    )
