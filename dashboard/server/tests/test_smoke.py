from .conftest import ALT_PLAIN_TOKEN, PLAIN_TOKEN

GCP = {"X-Source-Id": "gcp-ai-workstation", "X-Source-Token": PLAIN_TOKEN}
HK = {"X-Source-Id": "vps-hk-01", "X-Source-Token": ALT_PLAIN_TOKEN}


def test_health(client):
    r = client.get("/api/v1/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert body["db_ok"] is True


def test_ingest_201_then_feed(client):
    r = client.post(
        "/api/v1/ingest",
        json={"kind": "briefing", "title": "hello", "body": "world"},
        headers=GCP,
    )
    assert r.status_code == 201, r.text
    assert r.json()["deduped"] is False

    r = client.get("/api/v1/feed")
    assert r.status_code == 200
    items = r.json()["items"]
    assert len(items) == 1
    item = items[0]
    assert item["source"] == "gcp-ai-workstation"
    assert item["source_label"] == "GCP AI Workstation"
    assert item["title"] == "hello"
    assert item["body"] == "world"
    assert item["history_count"] == 1


def test_ingest_rejects_unknown_source(client):
    r = client.post(
        "/api/v1/ingest",
        json={"kind": "briefing", "body": "x"},
        headers={"X-Source-Id": "nope", "X-Source-Token": "anything"},
    )
    assert r.status_code == 401
    assert r.json()["error"] == "bad_token"


def test_ingest_rejects_wrong_token(client):
    r = client.post(
        "/api/v1/ingest",
        json={"kind": "briefing", "body": "x"},
        headers={"X-Source-Id": "gcp-ai-workstation", "X-Source-Token": "wrong"},
    )
    assert r.status_code == 401


def test_ingest_rejects_missing_headers(client):
    r = client.post("/api/v1/ingest", json={"kind": "briefing", "body": "x"})
    assert r.status_code == 401


def test_ingest_rejects_invalid_kind(client):
    r = client.post(
        "/api/v1/ingest",
        json={"kind": "garbage", "body": "x"},
        headers=GCP,
    )
    assert r.status_code == 400


def test_ingest_rejects_oversized_body(client):
    r = client.post(
        "/api/v1/ingest",
        json={"kind": "briefing", "body": "A" * 5000},
        headers=GCP,
    )
    assert r.status_code == 413
    assert r.json()["error"] == "body_too_large"


def test_dedup_upsert(client):
    r1 = client.post(
        "/api/v1/ingest",
        json={"kind": "alert", "body": "v1", "dedup_key": "k1", "severity": "warn"},
        headers=GCP,
    )
    assert r1.status_code == 201
    first_id = r1.json()["id"]

    r2 = client.post(
        "/api/v1/ingest",
        json={"kind": "alert", "body": "v2", "dedup_key": "k1", "severity": "error"},
        headers=GCP,
    )
    assert r2.status_code == 200
    assert r2.json()["deduped"] is True
    assert r2.json()["id"] == first_id

    r = client.get("/api/v1/feed?kinds=alert")
    items = r.json()["items"]
    assert len(items) == 1
    assert items[0]["body"] == "v2"
    assert items[0]["severity"] == "error"
    assert items[0]["history_count"] == 1


def test_feed_default_excludes_status_kind(client):
    client.post("/api/v1/ingest", json={"kind": "briefing", "body": "b"}, headers=GCP)
    client.post(
        "/api/v1/ingest",
        json={"kind": "status", "body": "s", "meta": {"load_1": 0.1}},
        headers=GCP,
    )
    r = client.get("/api/v1/feed")
    sources = [i["source"] for i in r.json()["items"]]
    kinds = [i["kind"] for i in r.json()["items"]]
    assert "status" not in kinds
    assert "gcp-ai-workstation" in sources


def test_feed_kinds_filter(client):
    client.post("/api/v1/ingest", json={"kind": "briefing", "body": "b"}, headers=GCP)
    client.post(
        "/api/v1/ingest",
        json={"kind": "status", "body": "s", "meta": {"load_1": 0.1}},
        headers=GCP,
    )
    r = client.get("/api/v1/feed?kinds=status")
    items = r.json()["items"]
    assert len(items) == 1
    assert items[0]["kind"] == "status"
    assert items[0]["meta"]["load_1"] == 0.1


def test_feed_one_per_source(client):
    client.post("/api/v1/ingest", json={"kind": "briefing", "body": "b1"}, headers=GCP)
    client.post("/api/v1/ingest", json={"kind": "briefing", "body": "b2"}, headers=GCP)
    client.post("/api/v1/ingest", json={"kind": "briefing", "body": "h1"}, headers=HK)

    r = client.get("/api/v1/feed")
    items = r.json()["items"]
    assert len(items) == 2
    by_source = {i["source"]: i for i in items}
    assert by_source["gcp-ai-workstation"]["body"] == "b2"
    assert by_source["gcp-ai-workstation"]["history_count"] == 2
    assert by_source["vps-hk-01"]["body"] == "h1"
    assert by_source["vps-hk-01"]["history_count"] == 1


def test_history_pagination(client):
    for i in range(5):
        client.post(
            "/api/v1/ingest",
            json={"kind": "briefing", "body": f"msg{i}"},
            headers=GCP,
        )
    r = client.get("/api/v1/feed/gcp-ai-workstation/history?limit=2")
    body = r.json()
    assert r.status_code == 200
    assert body["source"] == "gcp-ai-workstation"
    assert len(body["items"]) == 2
    assert body["items"][0]["body"] == "msg4"
    assert body["items"][1]["body"] == "msg3"
    assert body["next_before"] is not None

    r2 = client.get(
        "/api/v1/feed/gcp-ai-workstation/history?limit=2&before="
        + body["next_before"]
    )
    body2 = r2.json()
    assert [it["body"] for it in body2["items"]] == ["msg2", "msg1"]


def test_rate_limit_returns_429(client, config):
    config.rate_limit_per_minute = 2
    payload = {"kind": "briefing", "body": "x"}
    assert client.post("/api/v1/ingest", json=payload, headers=GCP).status_code == 201
    assert client.post("/api/v1/ingest", json=payload, headers=GCP).status_code == 201
    r = client.post("/api/v1/ingest", json=payload, headers=GCP)
    assert r.status_code == 429
    assert r.json()["error"] == "rate_limited"


def test_meta_depth_limit(client):
    deep = {"a": {"b": {"c": {"d": {"e": 1}}}}}
    r = client.post(
        "/api/v1/ingest",
        json={"kind": "briefing", "body": "x", "meta": deep},
        headers=GCP,
    )
    assert r.status_code == 400
