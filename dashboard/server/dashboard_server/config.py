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
class NodeEntry:
    node_id: str
    label: str
    tailscale_name: str
    method: str = "icmp"        # "icmp" | "tcp"
    tcp_port: int = 0


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
    nodes: dict[str, NodeEntry] = field(default_factory=dict)
    sources_toml_path: Path | None = None
    nodes_toml_path: Path | None = None
    liveness_interval_s: float = 30.0
    liveness_probe_timeout_s: float = 2.0
    retention_interval_s: float = 86400.0
    enable_background_tasks: bool = True


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


def load_nodes_toml(path: Path) -> dict[str, NodeEntry]:
    if not path.exists():
        return {}
    raw = tomllib.loads(path.read_text())
    out: dict[str, NodeEntry] = {}
    for node_id, entry in raw.get("nodes", {}).items():
        method = entry.get("method", "icmp")
        if method not in ("icmp", "tcp"):
            raise ValueError(f"node {node_id}: invalid method {method!r}")
        out[node_id] = NodeEntry(
            node_id=node_id,
            label=entry.get("label", node_id),
            tailscale_name=entry.get("tailscale_name", node_id),
            method=method,
            tcp_port=int(entry.get("tcp_port", 0)),
        )
    return out


def load_config(server_toml: Path, sources_toml: Path, nodes_toml: Path | None = None) -> Config:
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
    cfg.sources_toml_path = sources_toml
    cfg.nodes_toml_path = nodes_toml
    cfg.sources = load_sources_toml(sources_toml)
    if nodes_toml is not None:
        cfg.nodes = load_nodes_toml(nodes_toml)
    return cfg
