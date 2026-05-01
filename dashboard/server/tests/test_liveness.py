import asyncio

import pytest

from dashboard_server.config import NodeEntry
from dashboard_server.db import connect, init_schema
from dashboard_server.liveness import liveness_tick


@pytest.fixture()
def conn(tmp_path):
    c = connect(str(tmp_path / "test.db"))
    init_schema(c)
    yield c
    c.close()


def _nodes() -> dict[str, NodeEntry]:
    return {
        "alpha": NodeEntry(node_id="alpha", label="Alpha", tailscale_name="alpha", method="icmp"),
        "beta":  NodeEntry(node_id="beta",  label="Beta",  tailscale_name="beta",  method="tcp", tcp_port=22),
    }


def _run(coro):
    return asyncio.get_event_loop().run_until_complete(coro) if False else asyncio.run(coro)


def test_liveness_tick_marks_alive(conn):
    async def fake_probe(node, timeout):
        return True, 1.5

    results = _run(liveness_tick(conn, _nodes(), fake_probe, timeout=2.0))
    assert results["alpha"] == (True, 1.5)
    assert results["beta"] == (True, 1.5)

    rows = {r["node"]: r for r in conn.execute("SELECT * FROM node_status").fetchall()}
    assert rows["alpha"]["alive"] == 1
    assert rows["alpha"]["ping_ms"] == 1.5
    assert rows["alpha"]["consecutive_fail"] == 0
    assert rows["alpha"]["last_seen"] is not None
    assert rows["beta"]["alive"] == 1


def test_liveness_failure_threshold_two_strikes(conn):
    async def fail_probe(node, timeout):
        return False, None

    _run(liveness_tick(conn, _nodes(), fail_probe, timeout=2.0))
    row = conn.execute("SELECT * FROM node_status WHERE node='alpha'").fetchone()
    assert row["consecutive_fail"] == 1
    # First strike does NOT immediately flip alive to false (stays at "unknown" default 0
    # but conceptually we don't claim alive until we've actually seen it). The hysteresis
    # only matters for nodes that were previously up.

    # Seed alpha as alive=1, then two consecutive failures should flip to alive=0.
    conn.execute("UPDATE node_status SET alive=1, consecutive_fail=0 WHERE node='alpha'")
    _run(liveness_tick(conn, _nodes(), fail_probe, timeout=2.0))
    row = conn.execute("SELECT * FROM node_status WHERE node='alpha'").fetchone()
    assert row["consecutive_fail"] == 1
    assert row["alive"] == 1, "single fail must not flip alive"

    _run(liveness_tick(conn, _nodes(), fail_probe, timeout=2.0))
    row = conn.execute("SELECT * FROM node_status WHERE node='alpha'").fetchone()
    assert row["consecutive_fail"] == 2
    assert row["alive"] == 0, "second fail flips to down"


def test_liveness_recovery_resets(conn):
    async def fail_probe(node, timeout):
        return False, None

    async def ok_probe(node, timeout):
        return True, 0.7

    _run(liveness_tick(conn, _nodes(), fail_probe, timeout=2.0))
    _run(liveness_tick(conn, _nodes(), fail_probe, timeout=2.0))
    _run(liveness_tick(conn, _nodes(), ok_probe, timeout=2.0))

    row = conn.execute("SELECT * FROM node_status WHERE node='alpha'").fetchone()
    assert row["alive"] == 1
    assert row["consecutive_fail"] == 0
    assert row["ping_ms"] == 0.7


def test_liveness_handles_probe_exceptions(conn):
    async def boom(node, timeout):
        raise RuntimeError("boom")

    results = _run(liveness_tick(conn, _nodes(), boom, timeout=2.0))
    assert results["alpha"] == (False, None)
    row = conn.execute("SELECT * FROM node_status WHERE node='alpha'").fetchone()
    assert row["consecutive_fail"] == 1
