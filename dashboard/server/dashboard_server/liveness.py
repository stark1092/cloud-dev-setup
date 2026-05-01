import asyncio
import logging
import sqlite3
import time
from collections.abc import Awaitable, Callable
from datetime import datetime, timezone

from .config import NodeEntry
from .db import transaction

logger = logging.getLogger("dashboard.liveness")

ProbeFn = Callable[[NodeEntry, float], Awaitable[tuple[bool, float | None]]]


def _utcnow_iso() -> str:
    now = datetime.now(timezone.utc)
    return now.strftime("%Y-%m-%dT%H:%M:%S.") + f"{now.microsecond // 1000:03d}Z"


async def probe_icmp(host: str, timeout: float) -> tuple[bool, float | None]:
    deadline_arg = max(1, int(timeout))
    proc = await asyncio.create_subprocess_exec(
        "ping", "-c", "1", "-W", str(deadline_arg), host,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
    )
    try:
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout + 1.0)
    except asyncio.TimeoutError:
        proc.kill()
        return False, None
    if proc.returncode != 0:
        return False, None
    rtt = _parse_ping_rtt(stdout.decode(errors="replace"))
    return True, rtt


def _parse_ping_rtt(out: str) -> float | None:
    for line in out.splitlines():
        if "time=" in line:
            tail = line.split("time=", 1)[1]
            num = tail.split()[0]
            try:
                return float(num)
            except ValueError:
                return None
    return None


async def probe_tcp(host: str, port: int, timeout: float) -> tuple[bool, float | None]:
    started = time.monotonic()
    try:
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(host, port), timeout=timeout
        )
    except (OSError, asyncio.TimeoutError):
        return False, None
    rtt_ms = (time.monotonic() - started) * 1000.0
    writer.close()
    try:
        await writer.wait_closed()
    except Exception:
        pass
    return True, round(rtt_ms, 2)


async def default_probe(node: NodeEntry, timeout: float) -> tuple[bool, float | None]:
    if node.method == "tcp":
        if node.tcp_port <= 0:
            return False, None
        return await probe_tcp(node.tailscale_name, node.tcp_port, timeout)
    return await probe_icmp(node.tailscale_name, timeout)


async def liveness_tick(
    conn: sqlite3.Connection,
    nodes: dict[str, NodeEntry],
    probe_fn: ProbeFn,
    timeout: float,
    fail_threshold: int = 2,
) -> dict[str, tuple[bool, float | None]]:
    """Probe every node once, write results into node_status. Returns the per-node result."""
    results: dict[str, tuple[bool, float | None]] = {}
    if not nodes:
        return results
    coros = [probe_fn(node, timeout) for node in nodes.values()]
    probes = await asyncio.gather(*coros, return_exceptions=True)
    now = _utcnow_iso()
    with transaction(conn):
        for node, outcome in zip(nodes.values(), probes):
            if isinstance(outcome, BaseException):
                logger.warning("probe %s raised: %s", node.node_id, outcome)
                ok, rtt = False, None
            else:
                ok, rtt = outcome
            results[node.node_id] = (ok, rtt)
            if ok:
                conn.execute(
                    """
                    INSERT INTO node_status (node, alive, last_seen, last_check_ts, ping_ms, consecutive_fail)
                    VALUES (?, 1, ?, ?, ?, 0)
                    ON CONFLICT(node) DO UPDATE SET
                      alive=1,
                      last_seen=excluded.last_seen,
                      last_check_ts=excluded.last_check_ts,
                      ping_ms=excluded.ping_ms,
                      consecutive_fail=0
                    """,
                    (node.node_id, now, now, rtt),
                )
            else:
                conn.execute(
                    """
                    INSERT INTO node_status (node, alive, last_seen, last_check_ts, ping_ms, consecutive_fail)
                    VALUES (?, 0, NULL, ?, NULL, 1)
                    ON CONFLICT(node) DO UPDATE SET
                      last_check_ts = excluded.last_check_ts,
                      consecutive_fail = node_status.consecutive_fail + 1,
                      alive = CASE
                        WHEN node_status.consecutive_fail + 1 >= ? THEN 0
                        ELSE node_status.alive
                      END
                    """,
                    (node.node_id, now, fail_threshold),
                )
    return results


async def liveness_loop(app, interval: float) -> None:
    while True:
        try:
            await liveness_tick(
                app.state.db,
                app.state.config.nodes,
                app.state.probe_fn,
                app.state.config.liveness_probe_timeout_s,
            )
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("liveness_tick failed")
        try:
            await asyncio.sleep(interval)
        except asyncio.CancelledError:
            raise
