import json
import sqlite3
import time
from collections import deque
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status

from .auth import verify_source
from .config import SourceEntry
from .db import transaction
from .models import IngestRequest, IngestResponse

router = APIRouter()


def _utcnow_iso() -> str:
    now = datetime.now(timezone.utc)
    return now.strftime("%Y-%m-%dT%H:%M:%S.") + f"{now.microsecond // 1000:03d}Z"


def _check_rate_limit(buckets: dict[str, deque[float]], source: str, limit_per_minute: int) -> None:
    if limit_per_minute <= 0:
        return
    now = time.monotonic()
    cutoff = now - 60.0
    bucket = buckets.setdefault(source, deque())
    while bucket and bucket[0] < cutoff:
        bucket.popleft()
    if len(bucket) >= limit_per_minute:
        raise HTTPException(
            status_code=429,
            detail={"error": "rate_limited", "detail": f"max {limit_per_minute}/min for {source}"},
        )
    bucket.append(now)


@router.post("/api/v1/ingest")
async def ingest(
    request: Request,
    payload: IngestRequest,
    response: Response,
    source: SourceEntry = Depends(verify_source),
) -> IngestResponse:
    cfg = request.app.state.config
    body_bytes = len(payload.body.encode("utf-8"))
    if body_bytes > cfg.body_max_bytes:
        raise HTTPException(
            status_code=413,
            detail={"error": "body_too_large", "detail": f"{body_bytes} > {cfg.body_max_bytes}"},
        )
    _check_rate_limit(request.app.state.rate_buckets, source.source_id, cfg.rate_limit_per_minute)

    server_ts = _utcnow_iso()
    meta_json = json.dumps(payload.meta, ensure_ascii=False) if payload.meta is not None else None

    conn: sqlite3.Connection = request.app.state.db
    deduped = False
    with transaction(conn):
        if payload.dedup_key:
            row = conn.execute(
                "SELECT id FROM messages WHERE source = ? AND dedup_key = ?",
                (source.source_id, payload.dedup_key),
            ).fetchone()
            if row is not None:
                conn.execute(
                    """
                    UPDATE messages SET
                      kind=?, title=?, body=?, severity=?, client_ts=?,
                      server_ts=?, meta_json=?
                    WHERE id=?
                    """,
                    (
                        payload.kind, payload.title, payload.body, payload.severity,
                        payload.client_ts, server_ts, meta_json, row["id"],
                    ),
                )
                row_id = row["id"]
                deduped = True
            else:
                cur = conn.execute(
                    """
                    INSERT INTO messages
                      (source, kind, title, body, severity, client_ts, server_ts, dedup_key, meta_json)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        source.source_id, payload.kind, payload.title, payload.body,
                        payload.severity, payload.client_ts, server_ts,
                        payload.dedup_key, meta_json,
                    ),
                )
                row_id = cur.lastrowid
        else:
            cur = conn.execute(
                """
                INSERT INTO messages
                  (source, kind, title, body, severity, client_ts, server_ts, dedup_key, meta_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, NULL, ?)
                """,
                (
                    source.source_id, payload.kind, payload.title, payload.body,
                    payload.severity, payload.client_ts, server_ts, meta_json,
                ),
            )
            row_id = cur.lastrowid

    response.status_code = status.HTTP_200_OK if deduped else status.HTTP_201_CREATED
    return IngestResponse(id=row_id, server_ts=server_ts, deduped=deduped)
