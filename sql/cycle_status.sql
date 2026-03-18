-- Check current topic and last cycle change
SELECT 
  topic,
  is_active,
  name
FROM sources
ORDER BY topic, name;