-- plain: execute only after owner UI permanent deletion of the exact Issue
-- and independent authenticated 404 plus complete empty state=all list evidence.
-- Keep the tombstone and every other column unchanged.
UPDATE feedback
SET state = 'deleted'
WHERE id = '9650fede-d514-4672-81f7-c92d2fa1afd2'
  AND issue_number = 1
  AND issue_node_id = 'I_kwDOVaxKc88AAAABa8HXFg'
  AND delete_requested = 1
  AND payload IS NULL
  AND state = 'deletion_pending';
