import asyncio
import logging
import sqlite3
from datetime import datetime, timezone

from .db import transaction

logger = logging.getLogger("dashboard.retention")


def _get_meta(conn: sqlite3.Connection, key: str) -> str | None:
    r = conn.execute("SELECT value FROM dashboard_meta WHERE key = ?", (key,)).fetchone()
    return r["value"] if r else None


def _set_meta(conn: sqlite3.Connection, key: str, value: str) -> None:
    conn.execute(
        """
        INSERT INTO dashboard_meta (key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """,
        (key, value),
    )


def retention_tick(conn: sqlite3.Connection, retain_days: int) -> int:
    """Delete messages older than retain_days, but always keep the latest row per source."""
    cutoff_expr = f"-{int(retain_days)} days"
    with transaction(conn):
        cur = conn.execute(
            """
            DELETE FROM messages
            WHERE server_ts < datetime('now', ?)
              AND id NOT IN (SELECT MAX(id) FROM messages GROUP BY source)
            """,
            (cutoff_expr,),
        )
        deleted = cur.rowcount or 0
    conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    return deleted


def maybe_vacuum(conn: sqlite3.Connection) -> bool:
    """Run VACUUM at most once per calendar month (UTC). Returns True if it ran."""
    today = datetime.now(timezone.utc).date()
    month_key = today.strftime("%Y-%m")
    last = _get_meta(conn, "last_vacuum_month")
    if last == month_key:
        return False
    conn.execute("VACUUM")
    with transaction(conn):
        _set_meta(conn, "last_vacuum_month", month_key)
    return True


async def retention_loop(app, interval: float) -> None:
    while True:
        try:
            deleted = retention_tick(app.state.db, app.state.config.retain_days)
            ran = maybe_vacuum(app.state.db)
            logger.info("retention: deleted=%d vacuum=%s", deleted, ran)
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("retention_tick failed")
        try:
            await asyncio.sleep(interval)
        except asyncio.CancelledError:
            raise
