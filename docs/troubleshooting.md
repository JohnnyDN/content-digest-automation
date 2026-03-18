# Troubleshooting Guide

Common issues and solutions for the AI Content Digest automation system.

## Table of Contents

1. [General Issues](#general-issues)
2. [Workflow Failures](#workflow-failures)
3. [Database Issues](#database-issues)
4. [API Issues](#api-issues)
5. [Network & Access](#network--access)
6. [Performance Issues](#performance-issues)
7. [System State Issues](#system-state-issues)
8. [Monitoring Issues](#monitoring-issues)
9. [n8n Specific Issues](#n8n-specific-issues)

---

## General Issues

### Cannot Access n8n UI

**Symptoms:**
- Browser shows "Connection refused" or timeout
- HTTPS error

**Diagnosis:**
```bash
# Check if n8n is running
docker ps | grep n8n

# Check n8n logs
docker compose logs n8n --tail 50

# Check Nginx
sudo systemctl status nginx

# Test localhost access
curl -I http://localhost:5678
```

**Solutions:**

1. **n8n not running:**
```bash
   cd ~/content-digest-automation/infra
   docker compose up -d
```

2. **Nginx not running:**
```bash
   sudo systemctl start nginx
```

3. **SSL certificate expired:**
```bash
   sudo certbot renew
   sudo systemctl reload nginx
```

4. **Firewall blocking:**
```bash
   sudo ufw status
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
```

---

### Workflows Not Executing on Schedule

**Symptoms:**
- Scheduled time passes but workflow doesn't run
- Manual execution works, scheduled doesn't
- Cronitor shows missed runs

**Diagnosis:**
```bash
# Check n8n logs for scheduler errors
docker compose logs n8n | grep -i schedule

# Check server timezone
timedatectl
date

# Verify cron expression
# Workflow 0 should be: 0 2 */3 * *
```

**Solutions:**

1. **Workflow not active:**
   - Open workflow in n8n
   - Click "Activate" or "Publish" toggle

2. **Schedule trigger misconfigured:**
   - Open Workflow 0
   - Check Schedule Trigger node
   - Verify cron expression: `0 2 */3 * *`
   - Verify timezone: Europe/Rome

3. **Server timezone incorrect:**
```bash
   # Check current timezone
   timedatectl
   
   # Should show Europe/Rome
   # If not, set it:
   sudo timedatectl set-timezone Europe/Rome
   
   # Restart n8n
   cd ~/content-digest-automation/infra
   docker compose restart n8n
```

4. **Understanding the schedule:**
   - `0 2 */3 * *` means: Days 1, 4, 7, 10, 13, 16, 19, 22, 25, 28, 31 at 02:00
   - Not true "every 3 days" but day-of-month pattern
   - Check if today matches the pattern

---

### Timezone Issues Causing Wrong Execution Times

**Symptoms:**
- Backup runs at 02:00 instead of 01:00
- Workflows run at 03:00 instead of 02:00
- Cronitor shows "missed" then "complete" 1 hour later
- Period dates offset by 1 day

**Diagnosis:**
```bash
# Check server timezone
timedatectl
# Should show: Time zone: Europe/Rome (CET, +0100)

# Check file timestamps
stat ~/content-digest-automation/backups/auto_backup_*.sql.gz
# Should show +0100, not +0000 (UTC)

# Check system_state dates
docker exec -it infra-postgres-1 psql -U ai_digest -d ai_digest_db \
  -c "SELECT value->>'period_start', value->>'period_end' FROM system_state WHERE key = 'current_cycle';"
```

**Solution:**
```bash
# Set server timezone to Europe/Rome
sudo timedatectl set-timezone Europe/Rome

# Verify
timedatectl
date

# Restart services
cd ~/content-digest-automation/infra
docker compose restart
```

**Why this matters:**
- Cron jobs use server timezone
- n8n Schedule Trigger uses specified timezone (Europe/Rome)
- If server is UTC and n8n uses Europe/Rome, confusion results
- Both should be Europe/Rome for consistency

---

### Email Alerts Not Received

**Symptoms:**
- Workflow errors occur but no email
- Gmail node shows success but email not in inbox
- Cronitor alerts not received

**Diagnosis:**
```bash
# Check logs table for errors
docker exec -it infra-postgres-1 psql -U ai_digest -d ai_digest_db \
  -c "SELECT * FROM logs WHERE status = 'error' ORDER BY timestamp DESC LIMIT 5;"

# Check if Workflow 5 is active
# Check Cronitor dashboard for alert settings
```

**Solutions:**

1. **Workflow 5 not active:**
   - Activate Workflow 5 in n8n UI

2. **Gmail credential expired:**
   - n8n → Credentials → Gmail
   - Click "Reconnect"
   - Re-authorize account

3. **Email in spam:**
   - Check spam/junk folder
   - Add sender to contacts

4. **Error in email node:**
   - Check Workflow 5 execution logs
   - Verify email address is correct

5. **Cronitor notifications not configured:**
   - Go to Cronitor dashboard
   - Click monitor → Settings
   - Verify notification channels are set up
   - Check "Notify" dropdown has valid recipients

---

## Workflow Failures

### "Referenced Node Doesn't Exist" Error

**Symptoms:**
- Error: "Cannot assign to read only property 'name' of object 'Error: Referenced node doesn't exist'"
- Happens after workflow refactoring
- Execute Sub-Workflow nodes fail

**Cause:**
- n8n caches node references
- After moving/renaming/deleting nodes, references become stale
- Execute Sub-Workflow nodes hold outdated workflow IDs

**Solutions:**

1. **Recreate Execute Sub-Workflow nodes:**
   - Delete ALL "Execute Sub-Workflow" nodes in affected workflows
   - Add new "Execute Sub-Workflow" nodes
   - Use **"From List"** option (NOT "By ID")
   - Select target workflow from dropdown
   - Test chain manually

2. **After any major refactoring:**
   - Save workflow (Ctrl+S)
   - Close workflow tab
   - Reopen workflow
   - Test with manual execution

3. **Check node references in code:**
   - Search for `$('Old Node Name')`
   - Replace with `$('New Node Name')`

---

### Workflow 0: Cycle Manager Fails

**Common Errors:**

**Error: "Could not connect to database"**

**Solution:**
```bash
# Check PostgreSQL is running
docker ps | grep postgres

# Restart PostgreSQL
cd ~/content-digest-automation/infra
docker compose restart postgres

# Check PostgreSQL logs
docker compose logs postgres --tail 50
```

---

**Error: "Could not execute sub-workflow"**

**Solution:**
- Verify Workflow 1 exists and is active
- Delete and recreate "Execute Sub-Workflow" node using "From List"
- Save, close, reopen Workflow 0
- Test manually

---

**Error: "system_state table does not exist"**

**Cause:** Database schema missing the system_state table.

**Solution:**
```bash
docker exec -it infra-postgres-1 psql -U ai_digest -d ai_digest_db
```
```sql
CREATE TABLE system_state (
  id SERIAL PRIMARY KEY,
  key TEXT UNIQUE NOT NULL,
  value JSONB NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_system_state_key ON system_state(key);
```

---

**Error: "Query Parameters must be a string or array"**

**Cause:** Parameter format issue in "Update sources Table" node.

**Solution:**
In "Update sources Table" node, change parameter to:
```javascript
{{ [$('Set 3 days Cycle Topic').first().json.current_topic] }}
```

Note the square brackets `[ ]` - it must be an array.

---

**Error: "null value in column is_active violates not-null constraint"**

**Cause:** Wrong data flow causing NULL to be passed to UPDATE query.

**Solution:**
In "Update sources Table" node, explicitly reference the correct node:
```javascript
{{ [$('Set 3 days Cycle Topic').first().json.current_topic] }}
```

---

### Workflow 1: Feed Collection Fails

**Common Errors:**

**Error: "RSS feed timeout"**

**Cause:** RSS source is down or slow

**Solution:**
```sql
-- Temporarily disable problematic source
UPDATE sources SET is_active = false WHERE url = 'problematic_url';
```

---

**Error: "No items collected" or "Items collected = 0"**

**Diagnosis:**
```sql
-- Check active sources
SELECT name, url, topic, is_active FROM sources WHERE is_active = true;

-- Check system_state
SELECT * FROM system_state WHERE key = 'current_cycle';

-- Check items collected recently
SELECT COUNT(*), MAX(created_at) FROM items WHERE created_at > NOW() - INTERVAL '1 hour';
```

**Solution:**
- Verify RSS feeds are publishing content
- Check date filtering logic in "3-Day Filter" node
- Verify system_state has correct period dates
- Check if IF node condition is working (should allow 0 items gracefully)

---

**Error: "Count shows wrong number of items"**

**Symptoms:**
- Workflow collects 27 items but logs show 1 or 2
- Or: Second run shows same count as first run (duplicate count)

**Cause 1:** Counting from wrong node

**Solution:**
Create Log should reference database count, not loop nodes:
```sql
SELECT COUNT(*) as count
FROM items
WHERE created_at > NOW() - INTERVAL '1 minute';
```

**Cause 2:** Interval too long (counting old items)

**Solution:**
Reduce interval to 1-2 minutes:
```sql
WHERE created_at > NOW() - INTERVAL '1 minute';
```

---

**Error: "Populate Items node stuck with cached parameters"**

**Symptoms:**
- Node shows same 2 values repeatedly
- Even though 3-Day Filter passes 27 items
- Seems like cached data

**Cause:** n8n caching after workflow refactoring

**Solution:**
1. **Save workflow** (Ctrl+S)
2. **Close workflow tab**
3. **Reopen workflow**
4. **Test again**

If still stuck:
- Delete and recreate "Populate Items Table" node
- Ensure connections are correct

**This is normal n8n behavior after structural changes!**

---

### Workflow 2: Enrichment Fails

**Common Errors:**

**Error: "Anthropic API error: rate_limit_error"**

**Cause:** Too many requests to Claude API

**Solution:**
1. Check batch wait time (should be 70 seconds)
2. Verify only 5 items per batch
3. Contact Anthropic support to increase rate limits
4. Reduce batch size to 3 items

---

**Error: "JSON parsing failed"**

**Cause:** Claude returned malformed JSON

**Solution:**
1. Check "Parse Output" node logs
2. Review Claude's response in execution data
3. May need to improve system message in Anthropic node
```javascript
// Add to system message:
"CRITICAL: Test your JSON with JSON.parse() before returning.
Do not use any special characters. Replace contractions."
```

---

**Error: "Create Log shows 0 items enriched"**

**Symptoms:**
- Items were enriched successfully
- But log shows 0 items_enriched and 0 batches_processed

**Cause:** Create Log referencing wrong nodes or using wrong counting method

**Solution:**
```javascript
const topic = $('Read System State').first().json.topic;
const periodData = $('Read System State').first().json;

let itemsEnriched = 0;
let batchesProcessed = 0;

try {
  // Reference nodes BEFORE the loop
  const selectItemsNode = $('Select Items to Enrich').all();
  itemsEnriched = selectItemsNode.length;
  
  const createBatchesNode = $('Create Batches').all();
  batchesProcessed = createBatchesNode.length;
} catch (error) {
  // Nodes didn't execute (FALSE branch), counts remain 0
  itemsEnriched = 0;
  batchesProcessed = 0;
}

return [{ json: { ...details... } }];
```

**Key:** Reference nodes BEFORE loop, use try-catch for FALSE branch

---

**Error: "Node 'Populate items_enriched Table' hasn't been executed"**

**Cause:** Create Log trying to reference node that only executes in TRUE branch

**Solution:** Use try-catch (see above code example)

---

**Error: "Enriching same items twice"**

**Symptoms:**
- 27 items in database
- Enrichment processes 54 items
- Database query returns duplicates

**Diagnosis:**
```sql
-- Check for duplicate items
SELECT url, COUNT(*) as count, STRING_AGG(source_id::text, ', ') as source_ids
FROM items
WHERE published_at::date BETWEEN '2026-03-01' AND '2026-03-03'
GROUP BY url
HAVING COUNT(*) > 1;

-- Check what enrichment query returns
SELECT COUNT(*)
FROM items i
LEFT JOIN item_enriched ie ON ie.item_id = i.id
WHERE ie.item_id IS NULL
  AND i.published_at::date >= '2026-03-01'
  AND i.published_at::date <= '2026-03-03';
```

**Possible causes:**
- Feed Collection ran multiple times
- System state has duplicates (check: `SELECT COUNT(*) FROM system_state WHERE key = 'current_cycle'`)
- "Read System State" returns 2 items instead of 1

**Solution:**
1. Clean up system_state duplicates
2. Ensure Feed Collection executes only once
3. Check "When Executed by Another Workflow" trigger receives only 1 item

---

### Workflow 3: Digest Generation Fails

**Common Errors:**

**Error: "No items to draft digest"**

**Cause:** No enriched items in 3-day period

**Diagnosis:**
```sql
-- Check enriched items availability
SELECT COUNT(*)
FROM item_enriched e
JOIN items i ON i.id = e.item_id
WHERE i.published_at::date >= CURRENT_DATE - 3
  AND i.published_at::date <= CURRENT_DATE - 1;
```

**Solution:**
- Verify Workflow 2 completed successfully
- Check if items were actually enriched
- Check system_state for correct period dates
- Verify IF node allows graceful 0-item handling

---

**Error: "Digest JSON parsing failed"**

**Solution:**
Similar to Workflow 2, improve Claude prompting or handle edge cases in parser.

---

**Error: "Create Log shows no digest created when one was created"**

**Symptoms:**
- Digest inserted successfully
- But log shows: `digest_id: null`, `event: 'no_items_to_digest'`

**Cause:** Create Log not referencing the correct nodes

**Solution:**
```javascript
const periodData = $('Read System State').first().json;

const existingDigest = $('Check Existing Digest').first().json;
const hasExisting = existingDigest && existingDigest.id !== null;

let digestId = null;
let dominantTopic = null;
let event = 'no_items_to_digest';

if (hasExisting) {
  event = 'digest_already_exists';
  digestId = existingDigest.id;
} else {
  try {
    const insertNode = $('Insert Into digests Table').all();
    if (insertNode.length > 0 && insertNode[0].json.id) {
      event = 'digest_created';
      digestId = insertNode[0].json.id;
      dominantTopic = insertNode[0].json.dominant_topic;
    }
  } catch (error) {
    // Insert didn't run (no items path)
  }
}

return [{ json: { ...details... } }];
```

---

**Error: "Creating duplicate digests for same period"**

**Symptoms:**
- Run workflow twice
- Two digests created for same period_start/period_end

**Cause:** Not checking if digest already exists before creating

**Solution:**
Add "Check Existing Digest" node and compound IF condition:
```sql
-- Check Existing Digest query:
SELECT id, run_date 
FROM digests
WHERE period_start = $1::date 
  AND period_end = $2::date
LIMIT 1;
```

IF node with AND conditions:
1. `{{ Object.keys($input.first().json).length > 1 }}` (items exist)
2. `{{ !$('Check Existing Digest').first().json.id }}` (no existing digest)

---

### Workflow 4: Distribution Fails

**Common Errors:**

**Error: "No unpublished digests found"**

**Cause:** Digest already distributed or Workflow 3 didn't create one

**Diagnosis:**
```sql
-- Check recent digests
SELECT id, run_date, published_at FROM digests ORDER BY run_date DESC LIMIT 5;
```

**Solution:**
- If `published_at IS NULL` but workflow still fails, check query logic
- If no recent digests, check Workflow 3 success

---

**Error: "Distributing same digest multiple times"**

**Symptoms:**
- Digest distributed successfully
- Run workflow again
- Same digest distributed again

**Cause:** Not marking digest as published after distribution

**Solution:**
Add "Mark Digest as Published" node after "Send Mail":
```sql
UPDATE digests
SET published_at = NOW()
WHERE id = $1
RETURNING id, published_at;
```

Parameter: `{{ [$('Select Digest').first().json.id] }}`

This prevents re-distribution!

---

**Error: "Notion API error: database not found"**

**Cause:** Notion database ID changed or integration lost access

**Solution:**
1. Verify database ID in "Create Notion digest page" node
2. Check Notion integration has access to database:
   - Open Notion database
   - Click "..." → Connections
   - Ensure integration is connected

---

**Error: "Google Docs API error: insufficient permissions"**

**Cause:** Google OAuth credential expired

**Solution:**
- n8n → Credentials → Google Docs
- Click "Reconnect"
- Re-authorize
- If reconnect fails: delete credential and create new one

---

**Error: "Gmail send failed"**

**Solution:**
- Check Gmail credential
- Verify email address is valid
- Check Gmail sending limits (500/day for regular accounts)

---

**Error: "Invalid JSON in response body" (Cronitor ping)**

**Cause:** HTTP Request node expects JSON but Cronitor returns text.

**Solution:**
In "Ping Cronitor" node:
- Set **Response Format**: String (not JSON)
- Or in Options: Enable "Always Output Data"

---

**Error: "The provided authorization grant is invalid, expired, revoked..."**

**Symptoms:**
- Appears on "Execute Sub-Workflow" calling Workflow 4
- Actually a Google OAuth error from within Workflow 4

**Cause:** Google Docs or Gmail credential expired

**Solution:**
1. Open n8n → Credentials
2. Find Google Docs OAuth2 and Gmail OAuth2
3. Click "Reconnect" on each
4. Re-authorize in popup
5. Test Workflow 4 manually

**Why it shows on Execute Sub-Workflow:**
- n8n validates credentials when workflows are saved/activated
- Even though error is in Workflow 4, it prevents Workflow 1 from calling it
- This is n8n's "fail fast" design (annoying but intentional)

---

**Error: "Create Log shows 'no digest to distribute' when digest was distributed"**

**Cause:** Create Log can't reference nodes that only execute in TRUE branch

**Solution:**
Use try-catch pattern:
```javascript
let hasDistribution = false;
let notionUrl = null;
let gdocId = null;

try {
  const sendMailNode = $('Send Mail').all();
  hasDistribution = sendMailNode.length > 0;
  
  if (hasDistribution) {
    const notionNode = $('Create Notion digest page').all();
    if (notionNode.length > 0 && notionNode[0].json.url) {
      notionUrl = notionNode[0].json.url;
    }
    
    const gdocNode = $('Create Google Doc digest').all();
    if (gdocNode.length > 0 && gdocNode[0].json.documentId) {
      gdocId = gdocNode[0].json.documentId;
    }
  }
} catch (error) {
  hasDistribution = false;
}

return [{ json: { ...details... } }];
```

---

### Workflow 5: Error Logger Fails

**Error: "invalid input syntax for type integer: '6kbkQyAjU8kTapVf'"**

**Cause:** Using n8n's internal workflow ID (string) instead of numeric workflow ID (0-6)

**Solution:**
Update "Code in JavaScript" node to extract workflow ID from name:
```javascript
const data = $input.first().json;

function getWorkflowId(workflowName) {
  if (!workflowName) return null;
  if (workflowName.includes('00') || workflowName.includes('Cycle Manager')) return 0;
  if (workflowName.includes('01') || workflowName.includes('Feed Collection')) return 1;
  if (workflowName.includes('02') || workflowName.includes('Enrichment')) return 2;
  if (workflowName.includes('03') || workflowName.includes('Digest Generation')) return 3;
  if (workflowName.includes('04') || workflowName.includes('Distribution')) return 4;
  if (workflowName.includes('06') || workflowName.includes('Purger')) return 6;
  return null;
}

return [{
  json: {
    topic: 'unknown',
    workflow_id: getWorkflowId(data.workflow?.name),
    event: 'error',
    status: 'error',
    details: { ...error details... }
  }
}];
```

---

### Workflow 6: Purger Shows Wrong Delete Counts

**Symptoms:**
- No items older than 30 days
- But purger logs "1 item deleted" per table

**Cause:** "Always Output Data" on DELETE nodes returns 1 empty item when 0 rows deleted

**Solution:**
Filter out empty items before counting:
```javascript
const logsDeleted = $('Purge Logs').all().filter(item => item.json.id).length;
const enrichedDeleted = $('Purge item_enriched').all().filter(item => item.json.id).length;
// ... etc
```

The `.filter(item => item.json.id)` removes empty items.

---

## Database Issues

### Connection Failures

**Error: "FATAL: database 'ai_digest_db' does not exist"**

**Solution:**
```bash
# Create database
docker exec -it infra-postgres-1 psql -U ai_digest -d postgres \
  -c "CREATE DATABASE ai_digest_db;"

# Run schema
docker exec -i infra-postgres-1 psql -U ai_digest -d ai_digest_db \
  < ~/content-digest-automation/sql/01_schema.sql
```

---

**Error: "FATAL: password authentication failed"**

**Cause:** Incorrect database password

**Solution:**
1. Check `.env` file for correct `POSTGRES_PASSWORD`
2. Recreate PostgreSQL credential in n8n with correct password

---

### System State Issues

**Error: "system_state table is empty"**

**Cause:** Workflow 0 hasn't run yet or failed to populate.

**Diagnosis:**
```sql
SELECT * FROM system_state WHERE key = 'current_cycle';
```

**Solution:**
- Manually execute Workflow 0
- Check Workflow 0 logs for errors
- Verify "Store System State" node exists in Workflow 0

---

**Error: "Period dates are incorrect/offset by 1 day"**

**Cause:** Timezone bug - using toISOString() instead of formatLocalDate()

**Solution:**
Verify Workflow 0's "Set 3 days Cycle Topic" node uses formatLocalDate():
```javascript
function formatLocalDate(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}
```

NOT:
```javascript
periodStart.toISOString().split('T')[0]  // ❌ Wrong!
```

**Also check server timezone:**
```bash
timedatectl
# Must show: Europe/Rome
```

---

**Error: "system_state has duplicate rows"**

**Symptoms:**
- Query returns 2 rows for key 'current_cycle'
- Workflows process data twice

**Diagnosis:**
```sql
SELECT COUNT(*) FROM system_state WHERE key = 'current_cycle';
```

**Solution:**
```sql
-- Keep only the most recent one
DELETE FROM system_state 
WHERE key = 'current_cycle' 
  AND id NOT IN (
    SELECT id FROM system_state 
    WHERE key = 'current_cycle' 
    ORDER BY updated_at DESC 
    LIMIT 1
  );
```

**Prevention:**
The `key` column has UNIQUE constraint, so duplicates shouldn't happen. If they do, investigate why the constraint isn't working.

---

### Slow Queries

**Symptoms:**
- Workflows taking longer than usual
- Timeouts

**Diagnosis:**
```sql
-- Check table sizes
SELECT 
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Check for missing indexes
SELECT * FROM pg_stat_user_tables WHERE idx_scan = 0 AND n_tup_ins > 10000;
```

**Solutions:**

1. **Run Workflow 6 manually** to purge old data
2. **Vacuum database:**
```bash
   docker exec -it infra-postgres-1 psql -U ai_digest -d ai_digest_db \
     -c "VACUUM ANALYZE;"
```
3. **Verify indexes exist:**
```sql
   \di  -- List all indexes
```

---

### Disk Space Full

**Symptoms:**
- PostgreSQL crashes
- "No space left on device" errors

**Diagnosis:**
```bash
df -h
docker system df
```

**Solutions:**

1. **Clean Docker images:**
```bash
   docker system prune -a
```

2. **Clean old backups:**
```bash
   find ~/content-digest-automation/backups/ -name "*.sql.gz" -mtime +30 -delete
```

3. **Run purger:**
   - Manually execute Workflow 6
   - Or lower `PURGE_DAYS` temporarily

4. **Increase VPS disk** (contact provider)

---

## API Issues

### Claude API Rate Limits

**Error:** `rate_limit_error`

**Cause:** Too many requests in short time

**Solutions:**

1. **Increase wait time between batches:**
   - Edit Workflow 2 "Wait" node
   - Increase from 70s to 120s

2. **Reduce batch size:**
   - Edit "Create Batches" node
   - Change from 5 to 3 items per batch

3. **Upgrade Anthropic plan** (if using free tier)

---

### Google API Quota Exceeded

**Error:** `quotaExceeded`

**Cause:** Too many API calls to Google Docs/Gmail

**Solutions:**

1. **Wait for quota reset** (usually resets at midnight Pacific Time)
2. **Request quota increase** via Google Cloud Console
3. **Reduce frequency** of workflow runs

---

### Notion API Errors

**Error:** `unauthorized`

**Cause:** Integration lost access or token expired

**Solution:**
1. Generate new Notion integration secret
2. Update credential in n8n
3. Re-grant database access in Notion

**Error:** `object_not_found`

**Cause:** Database was deleted or ID changed

**Solution:**
1. Verify database exists in Notion
2. Get new database ID from Notion URL
3. Update "Create Notion digest page" node

---

## Network & Access

### Cannot SSH to VPS

**Error:** `Connection refused` or `Permission denied`

**Solutions:**

1. **Check if banned by fail2ban:**
```bash
   # From OVH console/KVM:
   sudo fail2ban-client status sshd
   # If banned:
   sudo fail2ban-client set sshd unbanip YOUR_IP
```

2. **Use OVH console/KVM** to access and debug

3. **Check SSH service:**
```bash
   sudo systemctl status ssh
   sudo systemctl restart ssh
```

---

### SSL Certificate Issues

**Error:** "Your connection is not private" in browser

**Diagnosis:**
```bash
# Check certificate expiry
sudo certbot certificates
```

**Solutions:**

1. **Certificate expired:**
```bash
   sudo certbot renew
   sudo systemctl reload nginx
```

2. **Wrong certificate loaded:**
```bash
   sudo nginx -t
   # Check if correct cert paths in Nginx config
```

3. **Force renewal:**
```bash
   sudo certbot renew --force-renewal
```

---

### Firewall Blocking Services

**Symptoms:**
- Can't access services from browser
- Internal services can communicate

**Diagnosis:**
```bash
sudo ufw status verbose
sudo netstat -tlnp | grep -E '5678|9000|9090'
```

**Solutions:**

1. **Open required ports:**
```bash
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
```

2. **Verify services listen on localhost:**
```bash
   # Should show 127.0.0.1:5678, not 0.0.0.0:5678
   sudo netstat -tlnp | grep 5678
```

---

## Performance Issues

### n8n UI Slow

**Causes:**
- Too many execution records
- Docker resource constraints

**Solutions:**

1. **Verify execution pruning is enabled:**
```bash
   docker exec infra-n8n-1 env | grep EXECUTIONS
   # Should show EXECUTIONS_DATA_PRUNE=true
```

2. **Manually prune executions:**
```bash
   docker exec -it infra-postgres-1 psql -U ai_digest -d ai_digest_db \
     -c "DELETE FROM execution_entity WHERE finished_at < NOW() - INTERVAL '7 days';"
```

3. **Increase Docker resources:**
   - Edit docker-compose.yml
   - Add resource limits:
```yaml
   deploy:
     resources:
       limits:
         cpus: '2'
         memory: 2G
```

---

### Workflow Takes Too Long

**Symptoms:**
- Workflow exceeds expected duration
- Timeouts

**Diagnosis:**
1. Check execution time in n8n UI
2. Identify slow nodes
3. Review logs

**Solutions:**

1. **RSS feeds slow to respond:**
   - Increase RSS Read timeout
   - Consider removing slow sources

2. **Claude API slow:**
   - Reduce batch size
   - This is usually API processing time, can't optimize much

3. **Database queries slow:**
   - Add indexes
   - Run VACUUM ANALYZE
   - Check table sizes

---

### High CPU/Memory Usage

**Diagnosis:**
```bash
# Check container stats
docker stats

# Check system resources
htop

# Or in Cockpit UI
# https://cockpit.walterlabs.net
```

**Solutions:**

1. **Restart services:**
```bash
   cd ~/content-digest-automation/infra
   docker compose restart
```

2. **Reduce parallel executions:**
   - Ensure workflows run sequentially (default with chaining)

3. **Upgrade VPS** if consistently hitting limits

---

## System State Issues

### System State Out of Sync

**Symptoms:**
- Workflows use different periods
- Logs show inconsistent dates

**Diagnosis:**
```sql
-- Check current system state
SELECT * FROM system_state WHERE key = 'current_cycle';

-- Check logs for period consistency
SELECT 
  workflow_id,
  details->>'period_start' as period_start,
  details->>'period_end' as period_end,
  timestamp
FROM logs
WHERE timestamp > NOW() - INTERVAL '6 hours'
ORDER BY workflow_id;
```

**Solution:**
1. Manually execute Workflow 0 to refresh system_state
2. Verify all workflows read from system_state (not calculating locally)
3. Check that Workflow 0's "Store System State" node is working

---

### Period Dates Wrong by 1 Day

**Cause:** Timezone conversion bug or wrong server timezone

**Diagnosis:**
```sql
-- Check if dates are offset
SELECT 
  value->>'period_start' as period_start,
  value->>'period_end' as period_end,
  CURRENT_DATE - 3 as expected_start,
  CURRENT_DATE - 1 as expected_end
FROM system_state 
WHERE key = 'current_cycle';
```

**Solution:**
1. Verify server timezone is Europe/Rome: `timedatectl`
2. Verify Workflow 0 uses formatLocalDate() function, not toISOString()

---

## Monitoring Issues

### Cronitor Not Receiving Pings

**Symptoms:**
- Workflows run successfully
- Cronitor shows "missed" or no data

**Diagnosis:**
```bash
# Test ping manually
curl "YOUR_CRONITOR_URL?state=complete"
# Should return: {"ok": true}

# Check n8n execution logs
# Verify HTTP Request nodes executed
```

**Solutions:**

1. **Check HTTP Request node configuration:**
   - Method: GET
   - URL includes `?state=complete`
   - Response Format: String (not JSON)

2. **Test from VPS:**
```bash
   curl -v "YOUR_CRONITOR_URL?state=complete"
```

3. **Check network connectivity:**
```bash
   ping cronitor.io
```

4. **Verify Cronitor URL is correct:**
   - Go to Cronitor dashboard
   - Click monitor → View telemetry URL
   - Compare with URL in n8n

---

### Crontab Backup Not Pinging

**Symptoms:**
- Backup runs (files created)
- Cronitor shows missed backup

**Diagnosis:**
```bash
# Check crontab
crontab -l

# Test curl manually
curl "YOUR_BACKUP_CRONITOR_URL?state=complete"
```

**Solutions:**

1. **Verify crontab includes curl:**
```bash
   crontab -l | grep cronitor
   # Should show: && curl -fsS ... "URL?state=complete"
```

2. **Check cron logs:**
```bash
   grep CRON /var/log/syslog | tail -20
```

3. **Add to crontab if missing:**
```bash
   crontab -e
   # Add curl command at end of backup line
```

---

### Cronitor Shows Missed Execution But Backup File Exists

**Symptoms:**
- Backup file created at correct time
- But Cronitor shows "missed" at expected time
- Then shows "complete" 1 hour later

**Cause:** Server timezone mismatch (UTC vs Europe/Rome)

**Solution:**
Set server timezone to Europe/Rome:
```bash
sudo timedatectl set-timezone Europe/Rome
```

Then both cron and Cronitor use Rome time consistently.

---

### Cronitor Grace Period Too Short

**Symptoms:**
- Job starts on time
- But takes longer than expected
- Cronitor marks as "missed" before job completes
- Then shows "complete" after grace period

**Solution:**
Increase grace period in Cronitor dashboard:
- Click monitor → Settings
- Increase "Grace Period"
- Backup: 15 min → 75 min (4500 seconds)
- Workflows: 30 min → 2 hours (7200 seconds)

---

## n8n Specific Issues

### Nodes Show Stale/Cached Data

**Symptoms:**
- Making changes but node still uses old values
- Parameters seem cached
- Wrong data displayed even after save

**Cause:** n8n caching behavior after structural changes

**Solution:**

**Always after major refactoring:**
1. ✅ Save workflow (Ctrl+S or Cmd+S)
2. ✅ Close workflow tab
3. ✅ Reopen workflow
4. ✅ Test with manual execution

**Or:**
1. ✅ Save workflow
2. ✅ Refresh browser page (F5)
3. ✅ Test

**This forces n8n to:**
- Rebuild execution context
- Clear cached parameter evaluations
- Refresh node references
- Reload execution graph

**When this happens:**
- After moving nodes
- After changing connections
- After deleting nodes
- After reconnecting Execute Sub-Workflow nodes
- After changing loop structures

---

### IF Node Always Returns TRUE or FALSE

**Symptoms:**
- IF node returns TRUE when it should return FALSE
- Even with "Always Output Data", condition seems wrong

**Cause:** Condition checking wrong thing

**Common Issues:**

**Issue 1:** Checking `.length > 0` when "Always Output Data" returns 1 empty item
```javascript
// ❌ Wrong - returns TRUE for empty item
{{ $input.all().length > 0 }}

// ✅ Better - check for real data
{{ $input.first().json.id }}
```

**Issue 2:** Not accounting for NULL vs undefined
```javascript
// ❌ Might miss NULL
{{ $input.first().json.id !== undefined }}

// ✅ Better - just check truthiness
{{ $input.first().json.id }}
```

**Issue 3:** Combining conditions in code instead of using n8n AND/OR
```javascript
// ❌ Hard to debug
{{ $input.first().json.id && !$('Other Node').first().json.id }}

// ✅ Better - use n8n's UI
Condition 1: {{ $input.first().json.id }}
Operator: AND
Condition 2: {{ !$('Other Node').first().json.id }}
```

---

### Can't Count Loop Iterations from Outside Loop

**Symptoms:**
- Create Log outside loop shows wrong count
- Only sees 1 item instead of total

**Cause:** Can't reference nodes inside loop from outside loop

**Solutions:**

**1. Reference nodes BEFORE loop:**
```javascript
// ✅ This works - node before loop
const count = $('3-Day Filter').all().length;

// ❌ This fails - node inside loop
const count = $('Populate Items Table').all().length;
```

**2. Use database count:**
```sql
SELECT COUNT(*) as count
FROM items
WHERE created_at > NOW() - INTERVAL '1 minute';
```

**3. Connect Create Log to loop's "Done" output:**
- Not inside loop
- Connected to "Done" branch that fires once after all iterations

---

### Try-Catch Pattern for Branch Handling

**When to use:**

When Create Log needs to reference nodes that might not have executed (TRUE/FALSE branch scenarios).

**Pattern:**
```javascript
let data = null;

try {
  // Try to reference node that may not have executed
  data = $('Node In TRUE Branch').all();
} catch (error) {
  // Node didn't execute (FALSE branch), use default
  data = null;
}

// Now safely use data
```

**Use in:**
- Workflow 2: Create Log (enrichment path)
- Workflow 3: Create Log (digest creation path)
- Workflow 4: Create Log (distribution path)

---

### Execute Sub-Workflow Calls Workflow Multiple Times

**Symptoms:**
- Workflow 1 completes
- Workflow 2 executes twice (or more)
- Duplicate processing

**Cause:** Execute Sub-Workflow receiving multiple items

**Diagnosis:**
Check the node BEFORE Execute Sub-Workflow:
- Is it outputting multiple items?
- Is it connected to loop output instead of "Done"?

**Solution:**
- Connect Execute Sub-Workflow to "Done" output of loop (not loop items)
- Ensure Create Log outputs only 1 item: `return [{ json: {...} }]`
- Not: `return $input.all()` or similar

---

## Backup & Recovery

### Backup Failed

**Symptoms:**
- No backup file created
- Cron job error emails
- Cronitor shows missed backup

**Diagnosis:**
```bash
# Check cron logs
grep CRON /var/log/syslog | tail -20

# Test backup manually
docker exec infra-postgres-1 pg_dump -U ai_digest ai_digest_db | gzip > test_backup.sql.gz
```

**Solutions:**

1. **PostgreSQL not running:**
```bash
   docker compose restart postgres
```

2. **Permissions issue:**
```bash
   # Ensure directory exists and is writable
   mkdir -p ~/content-digest-automation/backups
   chmod 755 ~/content-digest-automation/backups
```

3. **Disk full:**
```bash
   df -h
   # Clean up old backups if needed
```

---

### Restore From Backup

**Full restore procedure:**
```bash
# 1. Stop n8n (prevents new writes)
cd ~/content-digest-automation/infra
docker compose stop n8n

# 2. Restore database
gunzip -c ~/content-digest-automation/backups/backup_YYYYMMDD.sql.gz | \
  docker exec -i infra-postgres-1 psql -U ai_digest -d ai_digest_db

# 3. Restart n8n
docker compose start n8n

# 4. Verify
docker compose logs n8n --tail 50

# 5. Refresh system state
# Manually execute Workflow 0 to recalculate current state
```

---

## Getting Help

### Check Logs First

**Always start with logs:**
```bash
# n8n logs
cd ~/content-digest-automation/infra
docker compose logs n8n --tail 100

# PostgreSQL logs
docker compose logs postgres --tail 100

# System logs
sudo journalctl -u docker -n 50

# Nginx logs
sudo tail -50 /var/log/nginx/error.log

# Cron logs
grep CRON /var/log/syslog | tail -20
```

### Collect Debug Information

**Before asking for help, collect:**

1. **Error message** (exact text)
2. **Workflow execution ID** (from n8n UI)
3. **Logs** (relevant portions)
4. **System state:**
```sql
   SELECT * FROM system_state WHERE key = 'current_cycle';
```
5. **What changed** (recent updates, config changes)
6. **Steps to reproduce**
7. **Server timezone:** `timedatectl`

### Community Resources

- [n8n Community Forum](https://community.n8n.io)
- [n8n GitHub Issues](https://github.com/n8n-io/n8n/issues)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Docker Documentation](https://docs.docker.com/)
- [Cronitor Documentation](https://cronitor.io/docs/)

### Emergency Recovery

**Complete system failure:**

1. **Access via OVH console/KVM**
2. **Check Docker status:**
```bash
   sudo systemctl status docker
   docker ps -a
```
3. **Restart everything:**
```bash
   cd ~/content-digest-automation/infra
   docker compose down
   docker compose up -d
```
4. **Check backups** if database corrupted
5. **Contact VPS provider** if hardware issue

---

## Prevention

### Regular Maintenance

**Daily:**
- Check Cronitor dashboard
- Review error emails (if any)

**Weekly:**
- Review error logs
- Check disk space: `df -h`
- Verify system state consistency
- Monitor execution times
- Test credential health (especially Google OAuth)

**Monthly:**
- Test backup restoration
- Review and optimize slow queries
- Update n8n: `docker compose pull && docker compose up -d`
- Review SSL certificate expiry
- Check Cronitor monitor configurations
- Reconnect Google OAuth credentials preemptively

**Quarterly:**
- Review and optimize Claude prompts
- Audit security settings
- Check for n8n breaking changes in updates
- Verify all credentials still valid
- Review workflow performance

### Monitoring Best Practices

1. **Set up external uptime monitoring** (Cronitor provides this)
2. **Review health check daily:** Run `health_check_daily.sql`
3. **Subscribe to error emails** (configured in Workflow 5 and Cronitor)
4. **Check execution history** in n8n UI weekly
5. **Monitor system_state age:**
```sql
   SELECT AGE(NOW(), updated_at) FROM system_state WHERE key = 'current_cycle';
```
   Should be less than 4 days!

### System Health Checks

**Run these regularly:**
```sql
-- 1. System state check
SELECT 
  value->>'current_topic' as topic,
  value->>'period_start' as start,
  value->>'period_end' as end,
  AGE(NOW(), updated_at) as age
FROM system_state WHERE key = 'current_cycle';

-- 2. Recent execution check
SELECT 
  workflow_id,
  event,
  status,
  timestamp
FROM logs
WHERE timestamp > NOW() - INTERVAL '7 days'
ORDER BY timestamp DESC
LIMIT 20;

-- 3. Error check
SELECT COUNT(*) as error_count
FROM logs
WHERE status = 'error'
  AND timestamp > NOW() - INTERVAL '7 days';

-- 4. Data volume check
SELECT 
  (SELECT COUNT(*) FROM items) as items,
  (SELECT COUNT(*) FROM item_enriched) as enriched,
  (SELECT COUNT(*) FROM digests) as digests,
  (SELECT COUNT(*) FROM logs) as logs;

-- 5. Duplicate digest check
SELECT 
  period_start,
  period_end,
  COUNT(*) as count
FROM digests
GROUP BY period_start, period_end
HAVING COUNT(*) > 1;
```

### Best Practices After Workflow Changes

**Checklist after modifying workflows:**
1. ✅ Save workflow
2. ✅ Close and reopen workflow tab (clears caches)
3. ✅ Test manually (don't rely on scheduled run)
4. ✅ Check both TRUE and FALSE branch outcomes
5. ✅ Verify logging is accurate
6. ✅ Download updated JSON
7. ✅ Commit to version control
8. ✅ Document what you changed

---

**Last Updated**: March 4, 2026  
**Version**: 1.2.0 (n8n Caching, Timezone, Loop Counting, Duplicate Prevention)