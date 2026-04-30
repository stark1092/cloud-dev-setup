import time
from datetime import datetime, timezone

from fastapi import APIRouter, Request

from . import __version__
from .models import HealthResponse

router = APIRouter()


@router.get("/api/v1/health", response_model=HealthResponse)
async def health(request: Request) -> HealthResponse:
    started_at: float = request.app.state.started_at
    db = request.app.state.db
    db_ok = True
    try:
        db.execute("SELECT 1").fetchone()
    except Exception:
        db_ok = False
    now = datetime.now(timezone.utc)
    return HealthResponse(
        status="ok" if db_ok else "degraded",
        version=__version__,
        db_ok=db_ok,
        uptime_s=int(time.monotonic() - started_at),
        now=now.strftime("%Y-%m-%dT%H:%M:%S.") + f"{now.microsecond // 1000:03d}Z",
    )
