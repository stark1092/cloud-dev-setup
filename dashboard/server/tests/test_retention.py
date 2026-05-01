import pytest

from dashboard_server.db import connect, init_schema
from dashboard_server.retention import maybe_vacuum, retention_tick


@pytest.fixture()
def conn(tmp_path):
    c = connect(str(tmp_path / "test.db"))
    init_schema(c)
    yield c
    c.close()


def _insert(conn, source, body, server_ts, kind="briefing"):
    conn.execute(
        """
        INSERT INTO messages (source, kind, body, server_ts)
        VALUES (?, ?, ?, ?)
        """,
        (source, kind, body, server_ts),
    )


def test_retention_keeps_latest_per_source(conn):
    _insert(conn, "src1", "old1", "2020-01-01T00:00:00Z")
    _insert(conn, "src1", "old2", "2020-06-01T00:00:00Z")
    _insert(conn, "src1", "latest-but-stale", "2024-01-01T00:00:00Z")
    _insert(conn, "src2", "very-old-only-row", "2019-01-01T00:00:00Z")
    _insert(conn, "src3", "fresh", "2099-01-01T00:00:00Z")

    deleted = retention_tick(conn, retain_days=30)
    assert deleted == 2  # src1 old1 + old2; src1 latest-but-stale and src2 only-row are kept; fresh kept

    rows = conn.execute("SELECT source, body FROM messages ORDER BY id").fetchall()
    bodies = {(r["source"], r["body"]) for r in rows}
    assert ("src1", "latest-but-stale") in bodies
    assert ("src2", "very-old-only-row") in bodies
    assert ("src3", "fresh") in bodies
    assert ("src1", "old1") not in bodies
    assert ("src1", "old2") not in bodies


def test_retention_idempotent(conn):
    _insert(conn, "src1", "a", "2020-01-01T00:00:00Z")
    _insert(conn, "src1", "b", "2020-06-01T00:00:00Z")
    retention_tick(conn, retain_days=30)
    deleted_again = retention_tick(conn, retain_days=30)
    assert deleted_again == 0


def test_vacuum_runs_once_per_month(conn):
    assert maybe_vacuum(conn) is True
    assert maybe_vacuum(conn) is False  # same month → skip
    row = conn.execute("SELECT value FROM dashboard_meta WHERE key='last_vacuum_month'").fetchone()
    assert row is not None and len(row["value"]) == 7  # YYYY-MM
