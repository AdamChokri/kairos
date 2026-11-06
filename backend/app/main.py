"""Kairos API entry point.

Seeded weakness SV-08 (security/seeded-vulns.md), the "ordinary misconfiguration" set:
  - every unexpected error returns its stack trace to the caller;
  - CORS allows any origin together with credentials;
  - no security headers, and the framework and Python versions are announced in X-Powered-By;
  - plain HTTP, no TLS (the Compose file and the hosts, not this file).
WP5.3 and WP5.4 replace these with production settings.
"""

import platform
import traceback
from contextlib import asynccontextmanager

import fastapi
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.db import Base, engine
from app.routers import auth, comments, importer, ops, tasks


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(engine)  # the schema is created at start-up (plan section 3.2)
    yield


app = FastAPI(title="Kairos", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def announce_versions(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Powered-By"] = (
        f"FastAPI {fastapi.__version__}; Python {platform.python_version()}"
    )
    return response


@app.exception_handler(Exception)
async def show_everything(request: Request, exc: Exception) -> JSONResponse:
    return JSONResponse(
        status_code=500,
        content={"error": str(exc), "traceback": traceback.format_exc()},
    )


# /api/tasks/import is registered before /api/tasks/{task_id}.
app.include_router(ops.router)
app.include_router(auth.router)
app.include_router(importer.router)
app.include_router(tasks.router)
app.include_router(comments.router)
