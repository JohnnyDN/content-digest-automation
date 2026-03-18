-- Daily Health Dashboard
WITH daily_stats AS (
  SELECT 
    topic,
    workflow_id,
    event,
    COUNT(*) as count,
    MAX(timestamp) as last_run
  FROM logs
  WHERE timestamp > NOW() - INTERVAL '24 hours'
  GROUP BY topic, workflow_id, event
)
SELECT 
  CASE workflow_id
    WHEN 0 THEN 'Cycle Manager'
    WHEN 1 THEN 'Feed Collection'
    WHEN 2 THEN 'Enrichment'
    WHEN 3 THEN 'Digest Generation'
    WHEN 4 THEN 'Distribution'
    WHEN 6 THEN 'Purger'
  END as workflow_name,
  topic,
  event,
  count,
  last_run
FROM daily_stats
ORDER BY workflow_id, last_run DESC;