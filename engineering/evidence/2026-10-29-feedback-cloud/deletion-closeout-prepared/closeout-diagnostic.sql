-- diagnostic: execute only after owner UI permanent deletion of the exact Issue
-- and independent authenticated 404 plus complete empty state=all list evidence.
-- Keep the tombstone and every other column unchanged.
UPDATE feedback
SET state = 'deleted'
WHERE id = '5b11fd1c-80a9-4a41-8790-0b1296bd6401'
  AND issue_number = 2
  AND issue_node_id = 'I_kwDOVaxKc88AAAABa8HZEQ'
  AND delete_requested = 1
  AND payload IS NULL
  AND state = 'deletion_pending';
