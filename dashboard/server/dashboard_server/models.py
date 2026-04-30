from typing import Annotated, Any, Literal

from pydantic import BaseModel, Field, field_validator

Kind = Literal["briefing", "status", "alert", "link"]
Severity = Literal["info", "warn", "error"]


class IngestRequest(BaseModel):
    kind: Kind
    title: str | None = Field(default=None, max_length=200)
    body: Annotated[str, Field(min_length=1)]
    severity: Severity | None = None
    client_ts: str | None = None
    dedup_key: Annotated[str | None, Field(default=None, max_length=200)] = None
    meta: dict[str, Any] | None = None

    @field_validator("meta")
    @classmethod
    def _meta_depth(cls, v: dict[str, Any] | None) -> dict[str, Any] | None:
        if v is None:
            return v
        if _depth(v) > 4:
            raise ValueError("meta JSON depth > 4")
        return v


def _depth(obj: Any, level: int = 1) -> int:
    if isinstance(obj, dict):
        return max((_depth(x, level + 1) for x in obj.values()), default=level)
    if isinstance(obj, list):
        return max((_depth(x, level + 1) for x in obj), default=level)
    return level


class IngestResponse(BaseModel):
    id: int
    server_ts: str
    deduped: bool


class FeedItem(BaseModel):
    id: int
    source: str
    source_label: str
    kind: Kind
    title: str | None
    body: str
    severity: Severity | None
    client_ts: str | None
    server_ts: str
    history_count: int | None = None
    meta: dict[str, Any] | None = None


class FeedResponse(BaseModel):
    items: list[FeedItem]
    generated_at: str


class HistoryResponse(BaseModel):
    source: str
    items: list[FeedItem]
    next_before: str | None


class HealthResponse(BaseModel):
    status: str
    version: str
    db_ok: bool
    uptime_s: int
    now: str
