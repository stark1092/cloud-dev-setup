import argparse
import sys
from pathlib import Path

import uvicorn

from .app import create_app
from .config import load_config


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="dashboard-server")
    parser.add_argument("--server-toml", default="/etc/dashboard/server.toml")
    parser.add_argument("--sources-toml", default="/etc/dashboard/sources.toml")
    parser.add_argument("--bind", default=None, help="override server.bind")
    parser.add_argument("--port", type=int, default=None, help="override server.port")
    args = parser.parse_args(argv)

    cfg = load_config(Path(args.server_toml), Path(args.sources_toml))
    if args.bind:
        cfg.bind = args.bind
    if args.port:
        cfg.port = args.port

    app = create_app(cfg)
    uvicorn.run(
        app,
        host=cfg.bind,
        port=cfg.port,
        ssl_certfile=cfg.tls_certfile,
        ssl_keyfile=cfg.tls_keyfile,
        log_level="info",
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
