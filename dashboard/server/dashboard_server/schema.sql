CREATE TABLE IF NOT EXISTS messages (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  source      TEXT    NOT NULL,
  kind        TEXT    NOT NULL CHECK (kind IN ('briefing','status','alert','link')),
  title       TEXT,
  body        TEXT    NOT NULL,
  severity    TEXT    CHECK (severity IN ('info','warn','error')),
  client_ts   TEXT,
  server_ts   TEXT    NOT NULL,
  dedup_key   TEXT,
  meta_json   TEXT
);

CREATE INDEX IF NOT EXISTS ix_messages_source_server_ts
  ON messages (source, server_ts DESC);

CREATE INDEX IF NOT EXISTS ix_messages_server_ts
  ON messages (server_ts DESC);

CREATE UNIQUE INDEX IF NOT EXISTS uq_messages_source_dedup
  ON messages (source, dedup_key)
  WHERE dedup_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS node_status (
  node             TEXT PRIMARY KEY,
  alive            INTEGER NOT NULL,
  last_seen        TEXT,
  last_check_ts    TEXT NOT NULL,
  ping_ms          REAL,
  consecutive_fail INTEGER NOT NULL DEFAULT 0
);
