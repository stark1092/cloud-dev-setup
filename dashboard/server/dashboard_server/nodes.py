import json
import sqlite3
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Request

from .auth import verify_read
from .models import NodeItem, NodeMetrics, NodesResponse

router = APIRouter()

KNOWN_METRIC_KEYS = {"uptime_s", "load_1", "mem_used_pct", "disk_root_pct", "metrics_ts"}


def _utcnow_iso() -> str:
    now = datetime.now(timezone.utc)
    return now.strftime("%Y-%m-%dT%H:%M:%S.") + f"{now.microsecond // 1000:03d}Z"


def _split_metrics(meta_json: str | None, server_ts: str) -> NodeMetrics:
    if not meta_json:
        return NodeMetrics(metrics_ts=server_ts)
    try:
        meta = json.loads(meta_json)
    except Exception:
        meta = {}
    extra = {k: v for k, v in meta.items() if k not in KNOWN_METRIC_KEYS}
    return NodeMetrics(
        uptime_s=meta.get("uptime_s"),
        load_1=meta.get("load_1"),
        mem_used_pct=meta.get("mem_used_pct"),
        disk_root_pct=meta.get("disk_root_pct"),
        metrics_ts=meta.get("metrics_ts") or server_ts,
        extra=extra or None,
    )


@router.get("/api/v1/nodes", response_model=NodesResponse)
async def nodes(request: Request, _: None = Depends(verify_read)) -> NodesResponse:
    cfg = request.app.state.config
    conn: sqlite3.Connection = request.app.state.db

    status_rows = {
        r["node"]: r
        for r in conn.execute("SELECT * FROM node_status").fetchall()
    }

    metrics_rows = {
        r["source"]: r
        for r in conn.execute(
            """
            SELECT m.* FROM messages m
            JOIN (
              SELECT source, MAX(id) AS max_id FROM messages
              WHERE kind = 'status' GROUP BY source
            ) latest ON m.id = latest.max_id
            """
        ).fetchall()
    }

    items: list[NodeItem] = []
    for node_id, node in cfg.nodes.items():
        st = status_rows.get(node_id)
        m = metrics_rows.get(node_id)
        items.append(NodeItem(
            node=node_id,
            label=node.label,
            tailscale_name=node.tailscale_name,
            alive=bool(st["alive"]) if st else False,
            last_seen=st["last_seen"] if st else None,
            last_check_ts=st["last_check_ts"] if st else None,
            ping_ms=st["ping_ms"] if st else None,
            metrics=_split_metrics(m["meta_json"], m["server_ts"]) if m else None,
        ))

    return NodesResponse(items=items, generated_at=_utcnow_iso())
