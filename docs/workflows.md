# Workflow Documentation

Detailed documentation for all 7 workflows in the Content Digest automation system.

## System Architecture
```
Workflow 0 (Schedule Trigger - Every 3 days pattern)
    ↓ (Execute Sub-Workflow)
Workflow 1 (When Executed by Another Workflow)
    ↓ (Execute Sub-Workflow)
Workflow 2 (When Executed by Another Workflow)
    ↓ (Execute Sub-Workflow)
Workflow 3 (When Executed by Another Workflow)
    ↓ (Execute Sub-Workflow)
Workflow 4 (When Executed by Another Workflow)
    ↓ (Execute Sub-Workflow)
Workflow 6 (When Executed by Another Workflow)

Workflow 5 (Error Logger - Triggered by errors in any workflow)
```

## Centralized State Management

The system uses a **single source of truth** pattern via the `system_state` table:
```
Workflow 0: Calculates topic + period ONCE
    ↓
    Stores in system_state table
    ↓
Workflows 1-3: Read from system_state
    ↓
    Guaranteed consistency, no duplicate calculations
```

### Benefits:
- ✅ Calculate period once, use everywhere
- ✅ Fix timezone bugs in one place
- ✅ Guaranteed consistency across all workflows
- ✅ Queryable current state at any time

## Topic Rotation Cycle

Topics rotate every ~3 days based on day-of-month pattern:
```
Days 1, 4, 7, 10, 13, 16, 19, 22, 25, 28, 31: Cycle runs
Topic assignment based on Unix epoch modulo 4:
  Cycle 0: AI
  Cycle 1: Finance
  Cycle 2: Music
  Cycle 3: Science
```

**Calculation:**
```javascript
const cycleDay = Math.floor(Date.now() / (3 * 24 * 60 * 60 * 1000)) % 4;
```

**Schedule Pattern:**
- Cron: `0 2 */3 * *`
- Runs on: 1st, 4th, 7th, 10th, 13th, 16th, 19th, 22nd, 25th, 28th, 31st of each month
- Time: 02:00 Europe/Rome
- Server timezone: Europe/Rome (critical for correct timing)

## Workflow Export & Git Sync

After modifying any workflow in n8n:
1. Open the workflow in n8n
2. Export as JSON: **⋮ menu → Download**
3. Save to `~/content-digest-automation/workflows/`
4. Commit:
```bash
git add -A
git commit -m "Update WF XX: description of change"
```
   The pre-commit hook will automatically sanitize sensitive values.

**Important:** Always re-export immediately after changes — don't let
workflow files drift out of sync with what's running in n8n.

## Workflow 0: Cycle Manager

### Purpose
Determines current topic, calculates 3-day period, stores in `system_state`, and initiates the workflow chain.

### Trigger
- **Type**: Schedule Trigger
- **Cron**: `0 2 */3 * *` (Days 1, 4, 7, 10, 13, 16, 19, 22, 25, 28, 31 at 02:00)
- **Timezone**: Europe/Rome

### Process Flow

1. **Set 3 days Cycle Topic** (Code Node)
   - Calculates current cycle index (0-3)
   - Maps to topic: AI, Finance, Music, Science
   - **Calculates period dates** (3-day window ending yesterday)
   - Uses `formatLocalDate()` helper to avoid timezone bugs
   - Returns: `{ current_topic, cycle_index, period_start, period_end, calculated_at }`

2. **Store System State** (PostgreSQL)
```sql
   INSERT INTO system_state (key, value)
   VALUES ('current_cycle', $1::jsonb)
   ON CONFLICT (key) 
   DO UPDATE SET value = $1::jsonb, updated_at = NOW()
   RETURNING *;
```
   - Stores complete cycle state in database
   - Single source of truth for all workflows

3. **Update sources Table** (PostgreSQL)
```sql
   UPDATE sources SET is_active = (topic = $1)
   RETURNING $1 as activated_topic, 
             (SELECT COUNT(*) FROM sources WHERE is_active = true) as active_count;
```
   - Parameter: `{{ [$('Set 3 days Cycle Topic').first().json.current_topic] }}`
   - Sets `is_active = true` only for current topic's sources
   - Returns 8 rows (one per source)

4. **Create Log** (Code Node)
   - Builds log entry with topic, cycle_index, active_count
   - Reads from "Set 3 days Cycle Topic" node
   - Uses `.first()` to get single row from 8-row output
   - Workflow ID: 0
   - Event: 'cycle_start'

5. **Store Log** (PostgreSQL)
   - Inserts log entry into logs table

6. **Ping Cronitor** (HTTP Request)
   - Method: GET
   - URL: Cronitor telemetry URL + `?state=complete`
   - Response Format: String
   - Notifies Cronitor that Workflow 0 started successfully

7. **Execute Sub-Workflow** (Triggers Workflow 1)
   - Source: From List (select Workflow 1)
   - Wait for completion: Enabled

### Period Calculation Logic
```javascript
// Calculate period - last 3 complete days excluding today
const now = new Date();

// Period Start: 3 days ago at midnight
const periodStart = new Date();
periodStart.setDate(now.getDate() - 3);
periodStart.setHours(0, 0, 0, 0);

// Period End: Yesterday at midnight
const periodEnd = new Date();
periodEnd.setDate(now.getDate() - 1);
periodEnd.setHours(0, 0, 0, 0);

// Helper function - avoids timezone bugs from toISOString()
function formatLocalDate(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}
```

**Example:**
```
Today: March 4, 2026
Period Start: March 1, 2026 (3 days ago)
Period End: March 3, 2026 (yesterday)
→ Collects articles from March 1, 2, 3
```

### Configuration

**No user configuration needed.** Topic rotation and period calculation are automatic.

### Monitoring
```sql
-- Check last cycle change
SELECT * FROM logs 
WHERE workflow_id = 0 
ORDER BY timestamp DESC 
LIMIT 1;

-- Check current system state
SELECT 
  value->>'current_topic' as topic,
  value->>'period_start' as period_start,
  value->>'period_end' as period_end,
  updated_at
FROM system_state 
WHERE key = 'current_cycle';

-- Check currently active topic
SELECT topic, COUNT(*) 
FROM sources 
WHERE is_active = true 
GROUP BY topic;
```

---

## Workflow 1: Feed Collection

### Purpose
Collects articles from active RSS sources for the current topic within the 3-day period.

### Trigger
- **Type**: When Executed by Another Workflow (triggered by Workflow 0)

### Process Flow

1. **Read System State** (PostgreSQL)
```sql
   SELECT 
     value->>'current_topic' as topic,
     value->>'period_start' as period_start,
     value->>'period_end' as period_end
   FROM system_state
   WHERE key = 'current_cycle';
```
   - Reads period and topic calculated by Workflow 0
   - No duplicate calculation!

2. **Select Active Sources** (PostgreSQL)
```sql
   SELECT id, name, url, topic
   FROM sources
   WHERE is_active = TRUE;
```
   - Gets all active sources for current topic (typically 2 sources)

3. **Loop Over Items** (Split in Batches)
   - Processes each source sequentially
   - Batch size: 1 (process one source at a time)

4. **RSS Read**
   - URL: `{{ $json.url }}`
   - Fetches RSS feed from source URL
   - Parses feed items

5. **3-Day Filter** (Code Node)
   - Gets period from: `$('Read System State').first().json`
   - Filters items published in the period window
   - Limits to 20 most recent items per source
   - Adds source_id to each item
   - Returns formatted items for database

6. **Check if Items Exist** (IF Node)
   - **Condition:** `{{ $input.first().json.id }}`
   - **TRUE branch:** Items passed filter → Continue to Populate
   - **FALSE branch:** No items → Skip to loop completion
   - Handles cases where RSS feed has no articles in period

7. **Populate Items Table** (PostgreSQL) - TRUE branch only
```sql
   INSERT INTO items (source_id, title, url, published_at, raw_content)
   VALUES ($1, $2, $3, $4, $5)
   ON CONFLICT (url) DO NOTHING;
```
   - Inserts new items (skips duplicates)
   - Returns empty if conflict (duplicate URL)

8. **Count Inserted Items** (PostgreSQL) - Connected to Loop "Done" output
```sql
   SELECT COUNT(*) as count
   FROM items
   WHERE created_at > NOW() - INTERVAL '1 minute';
```
   - Counts items inserted in last minute
   - Executes ONCE after loop completes (not per iteration)

9. **Create Log** (Code Node)
   - References: `$('Count Inserted Items').first().json.count`
   - Uses period from: `$('Read System State').first().json`
   - Logs ingestion results
   - Event: 'ingest_complete'

10. **Store Log** (PostgreSQL)

11. **Execute Sub-Workflow** (Triggers Workflow 2)
    - Source: From List (select Workflow 2)

### Key Design Patterns

**Loop Structure:**
- Loop processes sources inside
- Create Log connects to "Done" output (executes once after all iterations)
- Counting happens via database query, not loop accumulation

**0-Item Handling:**
- IF node allows workflow to continue even if no items match filter
- Prevents chain breaking when feeds have no new content

### Configuration

**RSS Sources** managed in database:
```sql
SELECT * FROM sources;
```

To add/remove sources, update the sources table.

### Monitoring
```sql
-- Items collected in last run
SELECT 
  s.name,
  s.topic,
  COUNT(i.id) as items_collected
FROM sources s
LEFT JOIN items i ON i.source_id = s.id 
  AND i.created_at > NOW() - INTERVAL '6 hours'
WHERE s.is_active = true
GROUP BY s.name, s.topic;
```

---

## Workflow 2: Enrichment

### Purpose
Enriches collected articles with AI-powered metadata using Claude API.

### Trigger
- **Type**: When Executed by Another Workflow (triggered by Workflow 1)

### Process Flow

1. **Read System State** (PostgreSQL)
```sql
   SELECT 
     value->>'current_topic' as topic,
     value->>'period_start' as period_start,
     value->>'period_end' as period_end
   FROM system_state
   WHERE key = 'current_cycle';
```
   - Gets topic and period from centralized state

2. **Select Items to Enrich** (PostgreSQL)
```sql
   SELECT i.id, i.title, i.url, i.raw_content
   FROM items i
   LEFT JOIN item_enriched ie ON ie.item_id = i.id
   WHERE ie.item_id IS NULL
     AND i.published_at::date >= $1
     AND i.published_at::date <= $2
   ORDER BY i.id;
```
   - Parameters: `{{ [$('Read System State').first().json.period_start, $('Read System State').first().json.period_end] }}`
   - Only selects items not yet enriched
   - **Options:** "Always Output Data" enabled

3. **Check if Items Exist** (IF Node)
   - **Condition:** `{{ $input.first().json.id }}`
   - **TRUE branch:** Items need enrichment → Continue to batching
   - **FALSE branch:** All items already enriched → Skip to logging
   - Allows workflow to complete gracefully with 0 items

4. **Create Batches** (Code Node) - TRUE branch only
   - Splits items into batches of 5
   - Gets topic from: `$('Read System State').first().json.topic`
   - Includes batch number, total batches

5. **Loop Over Batches** (Split in Batches)
   - Processes batches sequentially
   - Batch size: 1 (one batch at a time)

6. **Prepare Batch for LLM** (Code Node)
   - Formats batch for Claude API
   - Includes batch progress info

7. **Message a model** (Anthropic)
   - Model: claude-sonnet-4-5-20250929
   - Max tokens: 8000
   - Processes 5 items at once
   - Returns JSON array of enrichments

8. **Parse Output** (Code Node)
   - Robust JSON parser
   - Handles markdown code blocks
   - Adds item_id to each enrichment

9. **Populate items_enriched Table** (PostgreSQL)
```sql
   INSERT INTO item_enriched (
     item_id, language, category, tags,
     short_summary, detailed_summary,
     importance_score, virality_score
   ) VALUES (...)
   ON CONFLICT (item_id) DO NOTHING;
```

10. **Check if Last Batch** (IF Node)
    - If NOT last batch → Wait 70 seconds → Loop back
    - If last batch → Continue to logging

11. **Wait** (Wait Node)
    - 70 seconds between batches
    - Prevents API rate limits

12. **Create Log** (Code Node) - Connected to Loop "Done" output
    - Uses try-catch to handle both branches
    - References: `$('Select Items to Enrich').all().length` for item count
    - References: `$('Create Batches').all().length` for batch count
    - Event: 'enrichment_complete'
```javascript
const topic = $('Read System State').first().json.topic;
const periodData = $('Read System State').first().json;

let itemsEnriched = 0;
let batchesProcessed = 0;

try {
  const selectItemsNode = $('Select Items to Enrich').all();
  itemsEnriched = selectItemsNode.length;
  
  const createBatchesNode = $('Create Batches').all();
  batchesProcessed = createBatchesNode.length;
} catch (error) {
  // Nodes didn't execute (FALSE branch), counts remain 0
  itemsEnriched = 0;
  batchesProcessed = 0;
}

return [{
  json: {
    topic: topic,
    workflow_id: 2,
    event: 'enrichment_complete',
    status: 'success',
    details: {
      period_start: periodData.period_start,
      period_end: periodData.period_end,
      items_enriched: itemsEnriched,
      batches_processed: batchesProcessed
    }
  }
}];
```

13. **Store Log** (PostgreSQL)

14. **Execute Sub-Workflow** (Triggers Workflow 3)
    - Source: From List (select Workflow 3)

### Batch Processing Strategy

- **Batch size**: 5 items
- **Wait time**: 70 seconds
- **Why batching**: Claude API token limits, rate limits
- **Error handling**: Each batch independent

### Enrichment Schema

Each item gets:
- `language`: Detected language (e.g., "en", "it")
- `category`: Content category
- `tags`: Array of relevant tags (JSONB)
- `short_summary`: 2-3 sentence summary
- `detailed_summary`: 1-3 paragraph analysis
- `importance_score`: 0.0 - 1.0
- `virality_score`: 0.0 - 1.0

### Key Design Patterns

**Try-Catch for Branch Handling:**
- Create Log uses try-catch to reference nodes that may not have executed
- Handles both TRUE branch (items enriched) and FALSE branch (no items) gracefully

**Loop Counting:**
- Can't count loop iterations from outside
- References nodes BEFORE loop (Select Items to Enrich, Create Batches)

### Monitoring
```sql
-- Enrichment completion rate
SELECT 
  COUNT(DISTINCT i.id) as total_items,
  COUNT(DISTINCT ie.item_id) as enriched_items,
  ROUND(100.0 * COUNT(DISTINCT ie.item_id) / NULLIF(COUNT(DISTINCT i.id), 0), 2) as completion_rate
FROM items i
LEFT JOIN item_enriched ie ON ie.item_id = i.id
WHERE i.published_at > NOW() - INTERVAL '3 days';
```

---

## Workflow 3: Digest Generation

### Purpose
Generates a comprehensive digest article from enriched items using Claude API.

### Trigger
- **Type**: When Executed by Another Workflow (triggered by Workflow 2)

### Process Flow

1. **Read System State** (PostgreSQL)
```sql
   SELECT 
     value->>'current_topic' as topic,
     value->>'period_start' as period_start,
     value->>'period_end' as period_end
   FROM system_state
   WHERE key = 'current_cycle';
```
   - Gets period from centralized state

2. **Check Existing Digest** (PostgreSQL)
```sql
   SELECT id, run_date 
   FROM digests
   WHERE period_start = $1::date 
     AND period_end = $2::date
   LIMIT 1;
```
   - Parameters: `{{ [$('Read System State').first().json.period_start, $('Read System State').first().json.period_end] }}`
   - Checks if digest already exists for this period
   - **Options:** "Always Output Data" enabled
   - **Purpose:** Prevents duplicate digests

3. **Select Items to draft** (PostgreSQL)
```sql
   SELECT e.*, i.*, s.topic
   FROM item_enriched e
   JOIN items i ON i.id = e.item_id
   JOIN sources s ON s.id = i.source_id
   WHERE i.published_at::date >= $1
     AND i.published_at::date <= $2
   ORDER BY 
     e.importance_score DESC,
     e.virality_score DESC,
     i.published_at DESC;
```
   - Parameters: `{{ [$('Read System State').first().json.period_start, $('Read System State').first().json.period_end] }}`
   - Gets enriched items sorted by importance
   - **Options:** "Always Output Data" enabled

4. **Check if Items Exist** (IF Node)
   - **Condition 1:** `{{ Object.keys($input.first().json).length > 1 }}`
   - **Operator:** AND
   - **Condition 2:** `{{ !$('Check Existing Digest').first().json.id }}`
   - **TRUE branch:** Items exist AND no existing digest → Create digest
   - **FALSE branch:** No items OR digest already exists → Skip to logging
   - **Prevents:** Creating duplicate digests or digests with no content

5. **Parse Results** (Code Node) - TRUE branch only
   - Builds payload with topic, period, items array
   - Includes audience profile

6. **Message a model** (Anthropic)
   - Model: claude-sonnet-4-5-20250929
   - Max tokens: 10000
   - System message: Strict JSON output rules
   - Returns: dominant_topic, theme_sentence, fullmarkdown, linkedinposttext

7. **Parse Output** (Code Node)
   - Parses Claude's JSON response
   - Robust error handling

8. **Insert Into digests Table** (PostgreSQL)
```sql
   INSERT INTO digests (
     run_date, period_start, period_end,
     full_markdown, linkedin_post_text,
     dominant_topic, topic_category
   ) VALUES (...)
   RETURNING id, dominant_topic;
```
   - Uses period from: `$('Read System State').first().json`
   - Returns digest ID and dominant topic

9. **Create Log** (Code Node)
   - Uses try-catch to handle both branches
   - Checks if digest was created or already existed
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

return [{
  json: {
    topic: 'unknown',
    workflow_id: 3,
    event: event,
    status: 'success',
    details: {
      period_start: periodData.period_start,
      period_end: periodData.period_end,
      digest_id: digestId,
      dominant_topic: dominantTopic
    }
  }
}];
```

10. **Store Log** (PostgreSQL)

11. **Execute Sub-Workflow** (Triggers Workflow 4)
    - Source: From List (select Workflow 4)

### Digest Format

**Full Markdown includes:**
- Header with period dates
- Theme sentence (bold intro)
- Grouped narrative (not just bullet list)
- Business/career implications
- "What to watch next" section
- All URLs as inline links
- 400-600 words

**LinkedIn Post:**
- 150-200 characters
- Emoji + topic + theme
- Call to action

### Duplicate Prevention

**Two-part check prevents duplicates:**
1. Check existing digest for this period
2. IF condition uses AND to verify both items exist AND no digest exists

**This prevents:**
- Creating multiple digests for same period
- Creating empty digests when no items available

### Monitoring
```sql
-- Recent digests
SELECT 
  id,
  topic_category,
  dominant_topic,
  period_start,
  period_end,
  run_date,
  published_at
FROM digests
ORDER BY run_date DESC
LIMIT 5;

-- Check for duplicates
SELECT 
  period_start,
  period_end,
  COUNT(*) as digest_count
FROM digests
GROUP BY period_start, period_end
HAVING COUNT(*) > 1;
```

---

## Workflow 4: Distribution

### Purpose
Distributes the digest to Notion, Google Docs, and Gmail. Marks digest as published after successful distribution.

### Trigger
- **Type**: When Executed by Another Workflow (triggered by Workflow 3)

### Process Flow

1. **Select Digest** (PostgreSQL)
```sql
   SELECT *
   FROM digests
   WHERE published_at IS NULL
   ORDER BY run_date DESC
   LIMIT 1;
```
   - Gets most recent **unpublished** digest
   - **Options:** "Always Output Data" enabled

2. **Check if Digest Exists** (IF Node)
   - **Condition:** `{{ $input.first().json.id }}`
   - **TRUE branch:** Unpublished digest found → Distribute
   - **FALSE branch:** No unpublished digest → Skip to logging
   - **Prevents:** Running distribution when no new digest available

3. **Style Lookup** (PostgreSQL) - TRUE branch only
```sql
   SELECT s.*, d.dominant_topic, string_agg(src.name, ', ') as source_names
   FROM infographic_styles s
   JOIN digests d ON s.topic_category = d.topic_category
   JOIN items i ON i.published_at::date BETWEEN d.period_start AND d.period_end
   JOIN sources src ON src.id = i.source_id
   WHERE d.id = $1
   GROUP BY s.id, d.dominant_topic, d.id
   LIMIT 1;
```
   - Parameter: `{{ [$('Select Digest').item.json.id] }}`
   - Gets styling for topic
   - Aggregates source names

4. **Edit Fields** (Code Node)
   - Builds infographic prompt (6 blocks)
   - Creates notion_title, email_subject, gdoc_title
   - Adds topic emoji

5. **Split Markdown** (Code Node)
   - Splits fullmarkdown into 5 blocks (max 1900 chars each)
   - Notion has block size limits

6. **Create Notion digest page** (Notion)
   - Creates page in Content Calendar database
   - Sets properties: Digest ID, Period, Run Date, Status, Channel
   - Adds 5 markdown blocks
   - Returns: Notion page URL

7. **Create Google Doc digest** (Google Docs)
   - Creates blank doc in specified folder
   - Returns: documentId

8. **Update with Markdown** (Google Docs)
   - Inserts full markdown into doc

9. **Send Mail** (Gmail)
   - To: your_email@gmail.com
   - Subject: Topic emoji + draft notification
   - Body: HTML with Notion link, GDoc link, LinkedIn draft

10. **Mark Digest as Published** (PostgreSQL)
```sql
    UPDATE digests
    SET published_at = NOW()
    WHERE id = $1
    RETURNING id, published_at;
```
    - Parameter: `{{ [$('Select Digest').first().json.id] }}`
    - **Critical:** Marks digest as published to prevent re-distribution
    - Executes after successful email send

11. **Create Log** (Code Node)
    - Uses try-catch to handle both branches
    - Event: 'distribution_complete' or 'no_digest_to_distribute'
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

return [{
  json: {
    topic: 'unknown',
    workflow_id: 4,
    event: hasDistribution ? 'distribution_complete' : 'no_digest_to_distribute',
    status: 'success',
    details: hasDistribution ? {
      notion_url: notionUrl,
      gdoc_id: gdocId,
      email_sent: true
    } : {
      message: 'No unpublished digest found'
    }
  }
}];
```

12. **Store Log** (PostgreSQL)

13. **Ping Cronitor** (HTTP Request)
    - Method: GET
    - URL: Cronitor telemetry URL + `?state=complete`
    - Response Format: String
    - Notifies Cronitor that complete chain finished successfully

14. **Execute Sub-Workflow** (Triggers Workflow 6)
    - Source: From List (select Workflow 6)

### Distribution Channels

1. **Notion**: Full digest + metadata + LinkedIn draft
2. **Google Docs**: Full markdown for editing
3. **Gmail**: Summary email with links

### Duplicate Distribution Prevention

**The "Mark Digest as Published" step is critical:**

**Without it:**
- Digest created with `published_at = NULL`
- Workflow 4 runs → Distributes
- Next run: Digest still `published_at = NULL` → Distributes again ❌

**With it:**
- First run: Distributes → Sets `published_at = NOW()`
- Next run: `WHERE published_at IS NULL` returns 0 rows → Skips ✅

### Monitoring
```sql
-- Distribution status
SELECT 
  d.id,
  d.topic_category,
  d.run_date,
  d.published_at,
  l.details->>'notion_url' as notion_url,
  l.details->>'email_sent' as email_sent
FROM digests d
LEFT JOIN logs l ON l.details->>'digest_id' = d.id::text
  AND l.event = 'distribution_complete'
ORDER BY d.run_date DESC
LIMIT 10;

-- Check unpublished digests
SELECT COUNT(*) as unpublished_count
FROM digests
WHERE published_at IS NULL;
```

---

## Workflow 5: Error Logger

### Purpose
Captures and logs all workflow errors across the system. Sends email alerts.

### Trigger
- **Type**: Error Trigger
- **Configured as**: Error Workflow for Workflows 0, 1, 2, 3, 4, 6

### Process Flow

1. **Error Trigger**
   - Automatically triggered when any linked workflow errors
   - Receives error data structure

2. **Code in JavaScript** (Code Node)
   - Extracts workflow ID from workflow name (not internal ID)
   - Parses error details
```javascript
const data = $input.first().json;

// Extract workflow ID from name
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
    details: {
      error_message: data.execution?.error?.message || 'Unknown error',
      error_node: data.execution?.lastNodeExecuted || 'unknown',
      workflow_name: data.workflow?.name || 'unknown',
      execution_id: data.execution?.id || 'unknown',
      execution_url: data.execution?.url || '',
      timestamp: new Date().toISOString()
    }
  }
}];
```

3. **Execute a SQL query** (PostgreSQL)
   - Inserts error into logs table
   - `workflow_id` is now INTEGER (0-6), not internal string ID

4. **Send Mail** (Gmail)
   - To: your_email@gmail.com
   - Subject: `⚠️ n8n Error - Workflow {name}`
   - Body: HTML formatted error details
   - Includes execution URL

### Error Data Captured

- Workflow name and ID (numeric 0-6)
- Error message
- Node where error occurred
- Execution ID and URL
- Timestamp

### Email Format

HTML formatted with:
- Workflow name
- Error node
- Error message
- Execution ID
- Timestamp
- Link to view execution in n8n

### Important Notes

- **Must be active** for error logging to work
- **No error workflow** should be set on this workflow (would cause infinite loop)
- Errors are logged even if email fails
- **Workflow ID extraction** from name prevents database type mismatch errors

### Monitoring
```sql
-- Recent errors
SELECT 
  details->>'workflow_name' as workflow,
  details->>'error_node' as node,
  details->>'error_message' as error,
  timestamp
FROM logs
WHERE status = 'error'
ORDER BY timestamp DESC
LIMIT 20;
```

---

## Workflow 6: Purger

### Purpose
Automatically deletes old data to maintain database size and performance.

### Trigger
- **Type**: When Executed by Another Workflow (triggered by Workflow 4)

### Process Flow

1. **Purge Config** (Code Node)
```javascript
   const PURGE_DAYS = 30;  // Change this to adjust retention
   return [{
     json: {
       purge_days: PURGE_DAYS,
       purge_interval: `${PURGE_DAYS} days`,
       purge_before: new Date(...).toISOString().split('T')[0]
     }
   }];
```

2. **Purge Logs** (PostgreSQL)
```sql
   DELETE FROM logs
   WHERE timestamp < NOW() - ($1 || ' days')::INTERVAL
   RETURNING id;
```

3. **Purge item_enriched** (PostgreSQL)
```sql
   DELETE FROM item_enriched
   WHERE item_id IN (
     SELECT id FROM items
     WHERE published_at < NOW() - ($1 || ' days')::INTERVAL
   )
   RETURNING id;
```

4. **Purge items** (PostgreSQL)
```sql
   DELETE FROM items
   WHERE published_at < NOW() - ($1 || ' days')::INTERVAL
   RETURNING id;
```

5. **Purge digests** (PostgreSQL)
```sql
   DELETE FROM digests
   WHERE run_date < NOW() - ($1 || ' days')::INTERVAL
   RETURNING id;
```

6. **Create Log** (Code Node)
   - Counts actual deleted items (filters out empty items from "Always Output Data")
   - Event: 'purge_complete'
   - Logs: purge_days, counts deleted per table, total_deleted
```javascript
const config = $('Purge Config').first().json;

// Count actual deleted items (filter out empty items)
const logsDeleted = $('Purge Logs').all().filter(item => item.json.id).length;
const enrichedDeleted = $('Purge item_enriched').all().filter(item => item.json.id).length;
const itemsDeleted = $('Purge items').all().filter(item => item.json.id).length;
const digestsDeleted = $('Purge digests').all().filter(item => item.json.id).length;

const totalDeleted = logsDeleted + enrichedDeleted + itemsDeleted + digestsDeleted;

return [{
  json: {
    topic: 'system',
    workflow_id: 6,
    event: 'purge_complete',
    status: 'success',
    details: {
      purge_days: config.purge_days,
      logs_deleted: logsDeleted,
      enriched_deleted: enrichedDeleted,
      items_deleted: itemsDeleted,
      digests_deleted: digestsDeleted,
      total_deleted: totalDeleted
    }
  }
}];
```

7. **Store Log** (PostgreSQL)

### Deletion Order

**Critical**: Must respect foreign key constraints!

1. **Logs** (no dependencies)
2. **item_enriched** (depends on items)
3. **items** (depends on sources - but sources not deleted)
4. **digests** (no dependencies)

### Configuration

**To change retention period:**

Edit Purge Config node:
```javascript
const PURGE_DAYS = 30;  // Change this number
```

### Data Retention

Default: **30 days**

- Items older than 30 days: Deleted
- Enrichments for deleted items: Deleted
- Digests older than 30 days: Deleted
- Logs older than 30 days: Deleted

Sources and infographic_styles: **Never deleted**

### Accurate Counting

**The `.filter(item => item.json.id)` pattern:**
- PostgreSQL DELETE nodes have "Always Output Data" enabled
- When 0 rows deleted, returns 1 empty item
- Filter removes empty items before counting
- Ensures accurate "0 deleted" when no old data exists

### Monitoring
```sql
-- Last purge results
SELECT 
  details->>'purge_days' as retention_days,
  details->>'total_deleted' as total_deleted,
  details->>'items_deleted' as items_deleted,
  details->>'logs_deleted' as logs_deleted,
  timestamp
FROM logs
WHERE event = 'purge_complete'
ORDER BY timestamp DESC
LIMIT 1;
```

---

## Cross-Workflow Concepts

### Centralized State Pattern

**Problem:** Original design had period calculations in 4 different workflows, leading to:
- Potential inconsistency
- Timezone bugs in 4 places
- Duplicate maintenance burden

**Solution:** `system_state` table as single source of truth:
```sql
CREATE TABLE system_state (
  id SERIAL PRIMARY KEY,
  key TEXT UNIQUE NOT NULL,
  value JSONB NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

**Usage:**
```
Workflow 0: Calculate → Store
Workflows 1-3: Read → Use
```

**Query current state:**
```sql
SELECT * FROM system_state WHERE key = 'current_cycle';
```

### Date Filtering Consistency

All workflows use the **same period** from `system_state`:
```
Period Start: 3 days ago at 00:00:00 (local time)
Period End: Yesterday at 23:59:59 (local time)
Today: Excluded
```

This ensures:
- Feed collection matches enrichment period
- Enrichment matches digest period
- Consistent reporting

### Timezone Handling

**Problem:** `toISOString()` converts to UTC, causing 1-day shift in +0100 timezone.

**Solution:** `formatLocalDate()` helper function:
```javascript
function formatLocalDate(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}
```

Used **only in Workflow 0** - all other workflows read formatted dates from `system_state`.

**Server timezone MUST be Europe/Rome:**
```bash
sudo timedatectl set-timezone Europe/Rome
```

Without correct server timezone:
- Cron jobs run at wrong times
- Backups and workflows misaligned
- Cronitor shows missed executions

### Error Handling

Every workflow (except Error Logger) is linked to Workflow 5 for error logging.

Errors are:
- Logged to database
- Emailed to admin
- Include execution URL for debugging

### Logging Pattern

All workflows log their completion:
- `workflow_id`: 0-6 (INTEGER, not internal string ID)
- `event`: Descriptive string (e.g., 'cycle_start')
- `status`: 'success' or 'error'
- `details`: JSONB with run-specific data

### Workflow Chaining

Using "Execute Sub-Workflow" with "Wait for Completion":
- Ensures sequential execution
- Each workflow completes before next starts
- Prevents race conditions
- Easier debugging (linear execution path)
- **Use "From List" not "By ID"** to avoid reference errors

### External Monitoring

Cronitor monitors:
- **Backup**: Daily at 01:00 (via crontab curl)
- **Workflow 0**: Every 3-day pattern at 02:00 (via HTTP Request)
- **Complete Chain**: Heartbeat after Workflow 4 (via HTTP Request)

### Graceful 0-Item Handling

**IF nodes in Workflows 2, 3, 4:**
- Allow workflows to complete when no items need processing
- Prevent chain breaking due to empty datasets
- Use "Always Output Data" on SQL nodes so IF nodes receive data
- Log appropriate events (e.g., 'no_items_to_digest', 'digest_already_exists')

**Pattern:**
```
SQL Query (Always Output Data enabled)
    ↓
IF Node (checks for real data)
    ├─ TRUE → Process normally
    └─ FALSE → Skip to logging
    ↓
Both paths merge → Create Log → Continue chain
```

### Loop and Counting Patterns

**Problem:** Can't accurately count loop iterations from outside the loop.

**Solutions:**

1. **Reference nodes before loop:**
   - "3-Day Filter" (before loop) has all items
   - "Create Batches" (before loop) has batch count

2. **Database count queries:**
   - Count items inserted in last 1-2 minutes
   - Executes after loop completes

3. **Connect to "Done" output:**
   - Create Log connects to loop's "Done" branch
   - Executes once after all iterations complete

**Anti-pattern:**
```javascript
// ❌ This only sees last iteration
const count = $('Node Inside Loop').all().length;
```

**Correct patterns:**
```javascript
// ✅ Reference node before loop
const count = $('Node Before Loop').all().length;

// ✅ Or use database query
SELECT COUNT(*) FROM items WHERE created_at > NOW() - INTERVAL '1 minute';
```

### Try-Catch for Branch Handling

**Problem:** When IF nodes create branches, some nodes only execute in TRUE branch. Create Log (outside branches) can't always reference them.

**Solution:** Use try-catch:
```javascript
let data = null;

try {
  // Try to reference node that may not have executed
  data = $('Node In TRUE Branch').all();
} catch (error) {
  // Node didn't execute (FALSE branch), use default
  data = null;
}
```

This allows Create Log to work for both TRUE and FALSE branch outcomes.

### n8n Caching Behavior

**After major structural changes (moving nodes, changing connections):**

n8n sometimes caches stale execution contexts:
- Cached parameter evaluations
- Stale node references
- Old execution graph

**Always do after refactoring:**
1. ✅ Save workflow (Ctrl+S)
2. ✅ Close workflow tab
3. ✅ Reopen workflow
4. ✅ Test with manual execution

**Or:**
1. ✅ Save workflow
2. ✅ Refresh browser page
3. ✅ Test

This forces n8n to rebuild execution context with fresh data.

### Duplicate Prevention Strategies

**Workflow 3 (Digest):**
- Check if digest exists for period before creating
- IF condition uses AND: items exist AND no existing digest

**Workflow 4 (Distribution):**
- Query only unpublished digests (`WHERE published_at IS NULL`)
- Mark as published after successful distribution
- Next run finds no unpublished digests

**Database constraints:**
- `items.url` UNIQUE - prevents duplicate articles
- Period check in queries - prevents duplicate processing

---

## Maintenance

### Workflow Updates

**To update a workflow:**
1. Make changes in n8n UI
2. Save workflow (Ctrl+S)
3. Test with manual execution
4. Download JSON (⋮ → Download)
5. Save to `~/content-digest-automation/workflows/`
6. Commit to version control

**After structural changes:**
- Save, close, reopen workflow
- Test thoroughly
- Check both TRUE and FALSE branch outcomes

### Credential Rotation

**To rotate API keys:**
1. Generate new key in provider console
2. Update in n8n: Credentials → Edit credential
3. Test workflows
4. Update .env file as backup reference

**Google OAuth credentials:**
- Can expire after 7 days of inactivity
- Reconnect via Credentials UI
- If reconnect fails, delete and recreate credential
- Test Distribution workflow after reconnecting

### Schedule Changes

**To change execution frequency:**

Only edit Workflow 0's Schedule Trigger. All others will follow automatically via chaining.

Example - run on specific days:
```
Cron: 0 2 1,15 * *  # 1st and 15th of each month at 02:00
```

### System State Verification

**Regular health check:**
```sql
-- Verify state is current
SELECT 
  value->>'current_topic' as topic,
  value->>'period_start' as period_start,
  value->>'period_end' as period_end,
  updated_at,
  AGE(NOW(), updated_at) as age
FROM system_state 
WHERE key = 'current_cycle';
```

If `age` is more than 4 days, Workflow 0 might not be running!

### Execute Sub-Workflow Maintenance

**If you see "Referenced node doesn't exist" errors:**

1. Delete all "Execute Sub-Workflow" nodes
2. Recreate them using **"From List"** option (not "By ID")
3. Select target workflow from dropdown
4. Test chain manually

**This happens after:**
- Major workflow refactoring
- Renaming workflows
- Moving nodes around
- n8n updates

---

## Troubleshooting

See [troubleshooting.md](troubleshooting.md) for common workflow issues.

**Last Updated**: March 18, 2026  
**Version**: 1.2.0 (Production - Graceful 0-Item Handling + Duplicate Prevention)