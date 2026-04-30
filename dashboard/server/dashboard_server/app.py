import time

from fastapi import FastAPI
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from .config import Config
from .db import connect, init_schema
from .feed import router as feed_router
from .health import router as health_router
from .ingest import router as ingest_router


def create_app(config: Config) -> FastAPI:
    app = FastAPI(title="dashboard-server", version="0.1.0", docs_url=None, redoc_url=None)

    conn = connect(config.db_path)
    init_schema(conn)

    app.state.config = config
    app.state.db = conn
    app.state.started_at = time.monotonic()
    app.state.rate_buckets = {}

    app.include_router(ingest_router)
    app.include_router(feed_router)
    app.include_router(health_router)

    @app.exception_handler(StarletteHTTPException)
    async def _http_exc(_request, exc: StarletteHTTPException):
        if isinstance(exc.detail, dict) and "error" in exc.detail:
            return JSONResponse(status_code=exc.status_code, content=exc.detail)
        return JSONResponse(
            status_code=exc.status_code,
            content={"error": "http_error", "detail": str(exc.detail)},
        )

    @app.exception_handler(RequestValidationError)
    async def _validation_exc(_request, exc: RequestValidationError):
        return JSONResponse(
            status_code=400,
            content={"error": "invalid_request", "detail": jsonable_encoder(exc.errors())},
        )

    return app
