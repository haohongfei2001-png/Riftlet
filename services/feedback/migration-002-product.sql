-- Apply once to the existing dedicated feedback D1 before deploying the new Workers.
-- Do not rewrite payload or payload_hash: frozen legacy retries must remain valid.
-- Keep routing metadata after payload scrubbing so uncertain/deleted deliveries
-- reconcile their original Issue title without recreating an Issue.
ALTER TABLE feedback ADD COLUMN product TEXT NOT NULL DEFAULT 'riftlet'
  CHECK(product IN ('riftlet','saytile','nearpane'));
