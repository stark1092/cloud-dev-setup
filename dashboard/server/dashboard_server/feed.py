import json
import sqlite3
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, Request

from .auth import verify_read
from .models import FeedItem, FeedResponse, HistoryResponse

router = APIRouter()

ALL_KINDS = ("briefing", "status", "alert", "link")
DEFAULT_FEED_KINDS = ("briefing", "alert", "link")


def _utcnow_iso() -> str:
    now = datetime.now(timezone.utc)
    return now.strftime("%Y-%m-%dT%H:%M:%S.") + f"{now.microsecond // 1000:03d}Z"


def _parse_kinds(raw: str | None, default: tuple[str, ...]) -> tuple[str, ...]:
    if raw is None:
        return default
    parts = tuple(p.strip() for p in raw.split(",") if p.strip())
    bad = [p for p in parts if p not in ALL_KINDS]
    if bad:
        raise HTTPException(
            status_code=400,
            detail={"error": "invalid_kind", "detail": f"unknown kinds: {bad}"},
        )
    return parts


def _row_to_item(row: sqlite3.Row, source_label: str, history_count: int | None = None) -> FeedItem:
    meta = json.loads(row["meta_json"]) if row["meta_json"] else None
    return FeedItem(
        id=row["id"],
        source=row["source"],
        source_label=source_label,
        kind=row["kind"],
        title=row["title"],
        body=row["body"],
        severity=row["severity"],
        client_ts=row["client_ts"],
        server_ts=row["server_ts"],
        history_count=history_count,
        meta=meta,
    )


@router.get("/api/v1/feed", response_model=FeedResponse)
async def feed(
    request: Request,
    kinds: str | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=200),
    _: None = Depends(verify_read),
) -> FeedResponse:
    chosen = _parse_kinds(kinds, DEFAULT_FEED_KINDS)
    placeholders = ",".join("?" for _ in chosen)
    conn: sqlite3.Connection = request.app.state.db
    cfg = request.app.state.config

    rows = conn.execute(
        f"""
        SELECT m.* FROM messages m
        JOIN (
            SELECT source, MAX(server_ts) AS max_ts
            FROM messages
            WHERE kind IN ({placeholders})
            GROUP BY source
        ) latest
          ON m.source = latest.source AND m.server_ts = latest.max_ts
        WHERE m.kind IN ({placeholders})
        ORDER BY m.server_ts DESC
        LIMIT ?
        """,
        (*chosen, *chosen, limit),
    ).fetchall()

    counts = {r["source"]: r["n"] for r in conn.execute(
        f"SELECT source, COUNT(*) AS n FROM messages WHERE kind IN ({placeholders}) GROUP BY source",
        chosen,
    ).fetchall()}

    items = []
    for r in rows:
        label = cfg.sources.get(r["source"]).display_name if r["source"] in cfg.sources else r["source"]
        items.append(_row_to_item(r, label, history_count=counts.get(r["source"], 1)))

    return FeedResponse(items=items, generated_at=_utcnow_iso())


@router.get("/api/v1/feed/{source}/history", response_model=HistoryResponse)
async def history(
    request: Request,
    source: str,
    before: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    kinds: str | None = Query(default=None),
    _: None = Depends(verify_read),
) -> HistoryResponse:
    chosen = _parse_kinds(kinds, ALL_KINDS)
    placeholders = ",".join("?" for _ in chosen)
    conn: sqlite3.Connection = request.app.state.db
    cfg = request.app.state.config

    if before is None:
        before_clause = ""
        params: list = [source, *chosen]
    else:
        before_clause = "AND server_ts < ?"
        params = [source, *chosen, before]
    params.append(limit)

    rows = conn.execute(
        f"""
        SELECT * FROM messages
        WHERE source = ? AND kind IN ({placeholders})
          {before_clause}
        ORDER BY server_ts DESC
        LIMIT ?
        """,
        params,
    ).fetchall()

    label = cfg.sources.get(source).display_name if source in cfg.sources else source
    items = [_row_to_item(r, label) for r in rows]
    next_before = items[-1].server_ts if len(items) == limit else None
    return HistoryResponse(source=source, items=items, next_before=next_before)
