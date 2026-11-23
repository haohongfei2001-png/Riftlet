-- Recovery indexes and triggers from the frozen build 61 SQLite schema.
CREATE INDEX unresolved_per_asset ON operations(asset_id) WHERE phase NOT IN ('failed','succeeded');

CREATE INDEX recovery_predecessor ON attachment_reselections(predecessor_id);

CREATE TRIGGER single_unresolved_insert BEFORE INSERT ON operations
WHEN NEW.phase NOT IN ('failed','succeeded') AND EXISTS(
    SELECT 1 FROM operations o WHERE o.asset_id=NEW.asset_id AND o.id != NEW.id
      AND o.phase NOT IN ('failed','succeeded')
      AND NOT EXISTS(SELECT 1 FROM attachment_reselections r WHERE r.predecessor_id=o.id
        AND (r.successor_id=NEW.id OR o.id IS NOT
             (SELECT active_operation_id FROM assets WHERE id=NEW.asset_id))))
BEGIN SELECT RAISE(ABORT,'asset already has an unresolved input'); END;

CREATE TRIGGER single_unresolved_update BEFORE UPDATE OF phase,asset_id ON operations
WHEN NEW.phase NOT IN ('failed','succeeded') AND EXISTS(
    SELECT 1 FROM operations o WHERE o.asset_id=NEW.asset_id AND o.id != NEW.id
      AND o.phase NOT IN ('failed','succeeded')
      AND NOT EXISTS(SELECT 1 FROM attachment_reselections r WHERE r.predecessor_id=o.id
        AND (r.successor_id=NEW.id OR o.id IS NOT
             (SELECT active_operation_id FROM assets WHERE id=NEW.asset_id))))
BEGIN SELECT RAISE(ABORT,'asset already has an unresolved input'); END;

CREATE TRIGGER preserve_recovery_call BEFORE UPDATE ON checkpoints
WHEN OLD.key LIKE 'transfer-dispatch-call-v1:%' AND EXISTS(
    SELECT 1 FROM attachment_reselections WHERE predecessor_id=substr(OLD.key,length('transfer-dispatch-call-v1:')+1))
BEGIN SELECT RAISE(ABORT,'original invocation is read-only'); END;
