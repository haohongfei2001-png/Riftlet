-- Dedicated D1 database. Never apply to Riftlet's screenshot database.
CREATE TABLE IF NOT EXISTS limits (
  id INTEGER PRIMARY KEY CHECK (id = 1), daily INTEGER NOT NULL CHECK(daily BETWEEN 1 AND 10000),
  hourly INTEGER NOT NULL CHECK(hourly BETWEEN 1 AND 1000)
);
INSERT OR IGNORE INTO limits VALUES (1,1000,20);
CREATE TABLE IF NOT EXISTS quota (bucket TEXT PRIMARY KEY, used INTEGER NOT NULL, expires INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS feedback (
  id TEXT PRIMARY KEY, payload_hash TEXT NOT NULL, secret_hash TEXT NOT NULL,
  payload TEXT, created INTEGER NOT NULL, expires INTEGER NOT NULL,
  day_bucket TEXT NOT NULL, ip_bucket TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','attempting','uncertain','delivered','deletion_pending','deleted','expired')),
  issue_number INTEGER, issue_node_id TEXT, attempt_at INTEGER,
  checked_at INTEGER NOT NULL DEFAULT 0, delete_requested INTEGER NOT NULL DEFAULT 0 CHECK(delete_requested IN (0,1))
);
CREATE INDEX IF NOT EXISTS feedback_delivery ON feedback(state,checked_at,created);
CREATE INDEX IF NOT EXISTS feedback_expiry ON feedback(expires);
-- Keep periodic retention work bounded as scrubbed tombstones accumulate.
CREATE INDEX IF NOT EXISTS feedback_live_expiry ON feedback(expires) WHERE payload IS NOT NULL;
CREATE INDEX IF NOT EXISTS feedback_state_created ON feedback(state,created,issue_number);
CREATE INDEX IF NOT EXISTS quota_expiry ON quota(expires);
-- Trigger and insertion/outbox are atomic. Zero changed rows cannot grant quota.
CREATE TRIGGER IF NOT EXISTS feedback_budget BEFORE INSERT ON feedback BEGIN
  SELECT CASE WHEN COALESCE((SELECT used FROM quota WHERE bucket=NEW.day_bucket),0) >= (SELECT daily FROM limits WHERE id=1)
    OR COALESCE((SELECT used FROM quota WHERE bucket=NEW.ip_bucket),0) >= (SELECT hourly FROM limits WHERE id=1)
    THEN RAISE(ABORT,'feedback_quota') END;
  INSERT INTO quota VALUES(NEW.day_bucket,1,NEW.created+172800)
    ON CONFLICT(bucket) DO UPDATE SET used=used+1;
  INSERT INTO quota VALUES(NEW.ip_bucket,1,NEW.created+7200)
    ON CONFLICT(bucket) DO UPDATE SET used=used+1;
END;
