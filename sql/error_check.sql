-- Check for errors in last 7 days
SELECT 
  workflow_id,
  details->>'workflow_name' as workflow_name,
  details->>'error_message' as error,
  timestamp
FROM logs
WHERE status = 'error'
  AND timestamp > NOW() - INTERVAL '7 days'
ORDER BY timestamp DESC;