import asyncio

import pytest
from fastapi.testclient import TestClient

from dashboard_server.app import create_app
from dashboard_server.config import NodeEntry
from dashboard_server.liveness import liveness_tick

from .conftest import PLAIN_TOKEN

GCP = {"X-Source-Id": "gcp-ai-workstation", "X-Source-Token": PLAIN_TOKEN}


@pytest.fixture()
def configured(config):
    config.nodes = {
        "gcp-ai-workstation": NodeEntry(
            node_id="gcp-ai-workstation",
            label="GCP AI Workstation",
            tailscale_name="gcp-ai-workstation",
            method="icmp",
        ),
        "router": NodeEntry(
            node_id="router",
            label="Router (ping only)",
            tailscale_name="router",
            method="icmp",
        ),
    }
    return config


@pytest.fixture()
def client(configured):
    app = create_app(configured)
    with TestClient(app) as c:
        yield c


def test_nodes_lists_inventory_even_without_status(client):
    r = client.get("/api/v1/nodes")
    assert r.status_code == 200
    body = r.json()
    nodes = {it["node"]: it for it in body["items"]}
    assert set(nodes) == {"gcp-ai-workstation", "router"}
    for n in nodes.values():
        assert n["alive"] is False
        assert n["last_seen"] is None
        assert n["metrics"] is None


def test_nodes_reflects_liveness_and_metrics(client, configured):
    async def ok_probe(node, timeout):
        return True, 0.42

    asyncio.run(liveness_tick(
        client.app.state.db, configured.nodes, ok_probe, timeout=1.0
    ))

    r = client.post("/api/v1/ingest", headers=GCP, json={
        "kind": "status",
        "body": "metrics",
        "meta": {
            "uptime_s": 12345,
            "load_1": 0.5,
            "mem_used_pct": 30.0,
            "disk_root_pct": 40.0,
            "metrics_ts": "2026-04-29T10:00:00Z",
            "custom_field": "x",
        },
    })
    assert r.status_code == 201

    r = client.get("/api/v1/nodes")
    items = {it["node"]: it for it in r.json()["items"]}
    gcp = items["gcp-ai-workstation"]
    assert gcp["alive"] is True
    assert gcp["ping_ms"] == 0.42
    assert gcp["metrics"]["uptime_s"] == 12345
    assert gcp["metrics"]["load_1"] == 0.5
    assert gcp["metrics"]["disk_root_pct"] == 40.0
    assert gcp["metrics"]["extra"] == {"custom_field": "x"}

    router = items["router"]
    assert router["alive"] is True
    assert router["metrics"] is None  # no kind=status pushed for router
