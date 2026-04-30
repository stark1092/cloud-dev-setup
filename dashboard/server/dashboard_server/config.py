import hashlib
import tomllib
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class SourceEntry:
    source_id: str
    display_name: str
    token_hash: str


@dataclass
class Config:
    bind: str = "127.0.0.1"
    port: int = 8787
    tls_certfile: str | None = None
    tls_keyfile: str | None = None
    db_path: str = "/var/lib/dashboard/dashboard.db"
    retain_days: int = 90
    body_max_bytes: int = 65536
    rate_limit_per_minute: int = 60
    require_read_token: bool = False
    read_token_hash: str = ""
    sources: dict[str, SourceEntry] = field(default_factory=dict)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def load_server_toml(path: Path) -> dict:
    if not path.exists():
        return {}
    return tomllib.loads(path.read_text())


def load_sources_toml(path: Path) -> dict[str, SourceEntry]:
    if not path.exists():
        return {}
    raw = tomllib.loads(path.read_text())
    out: dict[str, SourceEntry] = {}
    for source_id, entry in raw.get("sources", {}).items():
        out[source_id] = SourceEntry(
            source_id=source_id,
            display_name=entry.get("display_name", source_id),
            token_hash=entry["token_hash"],
        )
    return out


def load_config(server_toml: Path, sources_toml: Path) -> Config:
    cfg = Config()
    raw = load_server_toml(server_toml)
    server = raw.get("server", {})
    storage = raw.get("storage", {})
    ingest = raw.get("ingest", {})
    read = raw.get("read", {})
    if "bind" in server:
        cfg.bind = server["bind"]
    if "port" in server:
        cfg.port = int(server["port"])
    cfg.tls_certfile = server.get("tls_certfile") or None
    cfg.tls_keyfile = server.get("tls_keyfile") or None
    if "db_path" in storage:
        cfg.db_path = storage["db_path"]
    if "retain_days" in storage:
        cfg.retain_days = int(storage["retain_days"])
    if "body_max_bytes" in ingest:
        cfg.body_max_bytes = int(ingest["body_max_bytes"])
    if "rate_limit_per_minute" in ingest:
        cfg.rate_limit_per_minute = int(ingest["rate_limit_per_minute"])
    cfg.require_read_token = bool(read.get("require_token", False))
    cfg.read_token_hash = read.get("read_token_hash", "") or ""
    cfg.sources = load_sources_toml(sources_toml)
    return cfg
