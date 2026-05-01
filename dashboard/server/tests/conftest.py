import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from dashboard_server.app import create_app  # noqa: E402
from dashboard_server.config import Config, SourceEntry, hash_token  # noqa: E402

PLAIN_TOKEN = "test-token-aaaa"
ALT_PLAIN_TOKEN = "test-token-bbbb"


@pytest.fixture()
def config(tmp_path) -> Config:
    cfg = Config(
        bind="127.0.0.1",
        port=0,
        db_path=str(tmp_path / "dashboard.db"),
        retain_days=90,
        body_max_bytes=1024,
        rate_limit_per_minute=1000,
        enable_background_tasks=False,
    )
    cfg.sources["gcp-ai-workstation"] = SourceEntry(
        source_id="gcp-ai-workstation",
        display_name="GCP AI Workstation",
        token_hash=hash_token(PLAIN_TOKEN),
    )
    cfg.sources["vps-hk-01"] = SourceEntry(
        source_id="vps-hk-01",
        display_name="HK VPS",
        token_hash=hash_token(ALT_PLAIN_TOKEN),
    )
    return cfg


@pytest.fixture()
def client(config) -> TestClient:
    app = create_app(config)
    with TestClient(app) as c:
        yield c
