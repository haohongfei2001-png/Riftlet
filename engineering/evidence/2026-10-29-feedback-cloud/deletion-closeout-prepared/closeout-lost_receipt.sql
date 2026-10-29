-- lost_receipt: execute only after owner UI permanent deletion of the exact Issue
-- and independent authenticated 404 plus complete empty state=all list evidence.
-- Keep the tombstone and every other column unchanged.
UPDATE feedback
SET state = 'deleted'
WHERE id = '2b2dd0e6-c966-4910-93a0-e96b5510a056'
  AND issue_number = 3
  AND issue_node_id = 'I_kwDOVaxKc88AAAABa8HbSw'
  AND delete_requested = 1
  AND payload IS NULL
  AND state = 'deletion_pending';
