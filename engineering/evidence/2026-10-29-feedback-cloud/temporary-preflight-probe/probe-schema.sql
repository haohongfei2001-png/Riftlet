-- Temporary, dedicated diagnostic table; contains no feedback body/ID/token/IP.
CREATE TABLE IF NOT EXISTS feedback_delivery_probe (
  slot INTEGER PRIMARY KEY CHECK(slot=1),
  started_ms INTEGER NOT NULL,
  finished_ms INTEGER,
  phase TEXT NOT NULL CHECK(phase IN ('scheduled_entered','retention_batch','delivery_flag','repository_configuration','repository_request','repository_http','repository_json','repository_match','eligible_query','preflight_complete')),
  http_status INTEGER CHECK(http_status IS NULL OR http_status BETWEEN 100 AND 599),
  flags_json TEXT NOT NULL CHECK(json_valid(flags_json))
);
-- Read only. A row proves scheduled entry reached D1; no row alone proves neither absence nor success.
-- SELECT started_ms,finished_ms,phase,http_status,flags_json FROM feedback_delivery_probe WHERE slot=1;
