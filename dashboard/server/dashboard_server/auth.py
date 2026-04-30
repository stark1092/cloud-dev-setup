import hmac

from fastapi import Header, HTTPException, Request

from .config import Config, SourceEntry, hash_token


def _err(detail: str) -> HTTPException:
    return HTTPException(status_code=401, detail={"error": "bad_token", "detail": detail})


def verify_source(
    request: Request,
    x_source_id: str | None = Header(default=None),
    x_source_token: str | None = Header(default=None),
) -> SourceEntry:
    cfg: Config = request.app.state.config
    if not x_source_id or not x_source_token:
        raise _err("missing source headers")
    entry = cfg.sources.get(x_source_id)
    if entry is None:
        raise _err("unknown source")
    if not hmac.compare_digest(hash_token(x_source_token), entry.token_hash):
        raise _err("token mismatch")
    return entry


def verify_read(
    request: Request,
    x_read_token: str | None = Header(default=None),
) -> None:
    cfg: Config = request.app.state.config
    if not cfg.require_read_token:
        return
    if not x_read_token or not hmac.compare_digest(hash_token(x_read_token), cfg.read_token_hash):
        raise _err("read token required")
