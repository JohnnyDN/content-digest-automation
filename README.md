# AI Content Digest Automation System

Fully automated 3-day content digest system that cycles through AI, Finance, Music, and Science topics, running on production VPS infrastructure.

## 🎯 What It Does

Automatically collects, enriches, and distributes professional content digests every 3 days:

- **Workflow 0**: Topic cycle manager (rotates: AI → Finance → Music → Science) + calculates 3-day period
- **Workflow 1**: RSS feed collection (8 sources, 3-day filtering)
- **Workflow 2**: AI-powered enrichment (Claude Sonnet 4.5, batched processing)
- **Workflow 3**: Digest generation (Claude-powered synthesis)
- **Workflow 4**: Multi-channel distribution (Notion + Google Docs + Gmail)
- **Workflow 5**: Error logging and email alerts
- **Workflow 6**: Automated data purging (30-day retention)

## 🛠️ Tech Stack

- **n8n**: Workflow automation engine (latest version)
- **PostgreSQL 16**: Relational database
- **Claude AI (Anthropic)**: Content enrichment & digest generation (claude-sonnet-4-5-20250929)
- **Docker Compose**: Container orchestration
- **Ubuntu 24.04 LTS**: VPS host operating system
- **Nginx**: Reverse proxy with SSL termination
- **Let's Encrypt**: SSL certificate management
- **Cronitor**: External monitoring and alerting

## 🌐 Production Infrastructure

- **Domain**: walterlabs.net
- **n8n UI**: https://n8n.walterlabs.net
- **Portainer**: https://portainer.walterlabs.net
- **Cockpit**: https://cockpit.walterlabs.net
- **VPS Provider**: OVH
- **Region**: Europe
- **Timezone**: Europe/Rome (Server and n8n aligned)

## 📊 Database Schema

### Core Tables:
- `sources` - RSS feed sources (8 feeds across 4 topics)
- `items` - Collected articles (3-day retention window)
- `item_enriched` - AI-enriched content metadata
- `digests` - Generated digest documents
- `infographic_styles` - Topic-specific visual styling
- `logs` - System activity and error tracking
- `system_state` - Current cycle state (topic, period, timestamps)

### System State Pattern:
The system uses a **centralized state store** to ensure consistency:
- Workflow 0 calculates topic + period **once** and stores in `system_state`
- Workflows 1-3 read from `system_state` (guaranteed consistency)
- Single source of truth eliminates timezone bugs and calculation drift

### Data Flow:
```
RSS Sources → items → item_enriched → digests → Distribution
                                         ↓
                                      Notion
                                   Google Docs
                                      Gmail
```

## 🚀 Quick Start

### Access n8n:
```
https://n8n.walterlabs.net
```

Login with credentials from `.env` file.

### Manual Execution:
Open **Workflow 0 - Cycle Manager** and click "Execute" to trigger the entire chain.

### Check Status:
```bash
cd ~/content-digest-automation/infra
docker compose ps
docker compose logs -f n8n
```

### Check System State:
```sql
-- View current cycle information
SELECT * FROM system_state WHERE key = 'current_cycle';
```

## 📁 Project Structure
```
content-digest-automation/
├── infra/                  # Docker configuration
│   ├── docker-compose.yml
│   ├── .env
│   └── .env.example
├── workflows/              # n8n workflow exports (JSON)
│   ├── 00-cycle-manager.json
│   ├── 01-feed-collection.json
│   ├── 02-enrichment.json
│   ├── 03-digest-generation.json
│   ├── 04-distribution.json
│   ├── 05-error-logger.json
│   └── 06-purger.json
├── sql/                    # Database schemas & queries
│   ├── 01_schema.sql
│   ├── 02_initial_data.sql
│   ├── health_check_daily.sql
│   ├── error_check.sql
│   └── cycle_status.sql
├── scripts/                # Utility scripts
│   └── backup.sh
├── backups/                # Database backups (daily automated)
├── docs/                   # Documentation
│   ├── workflows.md
│   ├── setup.md
│   └── troubleshooting.md
└── README.md
```

## 🔧 Common Tasks

### Start/Stop Services
```bash
cd ~/content-digest-automation/infra

# Start
docker compose up -d

# Stop
docker compose down

# Restart
docker compose restart

# View logs
docker compose logs -f n8n
```

### Database Access

**Via SQLTools (VS Code):**
- Connect via SSH tunnel
- Run queries from `sql/` folder

**Via Command Line:**
```bash
docker exec -it infra-postgres-1 psql -U ai_digest -d ai_digest_db
```

### Backup & Restore

**Manual Backup:**
```bash
bash ~/content-digest-automation/scripts/backup.sh
```

**Automated Backup:**
- Runs daily at 01:00 AM Europe/Rome time via cron
- Keeps 30 days of backups
- Location: `~/content-digest-automation/backups/`
- Monitored by Cronitor

**Restore:**
```bash
gunzip -c backup_file.sql.gz | docker exec -i infra-postgres-1 psql -U ai_digest -d ai_digest_db
```

### Update n8n
```bash
cd ~/content-digest-automation/infra
docker compose pull n8n
docker compose up -d

# After major updates, always:
# 1. Test workflows manually
# 2. Check for breaking changes in release notes
```

### Export Workflows
1. Open workflow in n8n UI
2. Click ⋮ → Download
3. Save to `~/content-digest-automation/workflows/`
4. Commit to version control

## ⏰ Execution Schedule
```
Daily:
01:00 → Database Backup (captures previous day's data)

Every 3-Day Pattern (Days 1, 4, 7, 10, 13, 16, 19, 22, 25, 28, 31):
02:00 → Workflow 0: Cycle Manager (calculates topic + period, stores in system_state)
  ↓ (triggers immediately)
02:01 → Workflow 1: Feed Collection (reads from system_state)
  ↓ (triggers immediately)
02:15 → Workflow 2: Enrichment (reads from system_state, Claude API batching)
  ↓ (triggers immediately)
03:30 → Workflow 3: Digest Generation (reads from system_state, Claude API)
  ↓ (triggers immediately)
03:45 → Workflow 4: Distribution (Notion + Docs + Email)
  ↓ (triggers immediately)
04:00 → Workflow 6: Purger (cleanup old data)
```

**Schedule Pattern:**
- Cron expression: `0 2 */3 * *`
- Runs on: 1st, 4th, 7th, 10th, 13th, 16th, 19th, 22nd, 25th, 28th, 31st of each month
- Approximately every 3 days (day-of-month pattern)
- Time: 02:00 Europe/Rome (both server and n8n use same timezone)

**Why 02:00?**
- Backup runs first at 01:00 on stable data
- Workflows start after midnight cron job rush
- Clean system state for reliable execution
- Digest ready by morning (06:00)
- Proper timezone alignment prevents missed executions

## 📧 Monitoring & Alerts

### Cronitor External Monitoring:
**Three monitors track system health:**

1. **PostgreSQL Backup** (Daily at 01:00)
   - Grace period: 15 minutes
   - Alerts if backup fails or doesn't run
   - Pings via crontab curl command

2. **Workflow 0 Start** (Every 3-day pattern at 02:00)
   - Grace period: 30 minutes
   - Alerts if Workflow 0 doesn't start
   - Pings via n8n HTTP Request node

3. **Complete Workflow Chain** (Heartbeat)
   - Grace period: 4 hours
   - Alerts if entire chain doesn't complete
   - Pings via n8n HTTP Request node in Workflow 4

**Dashboard:** https://cronitor.io/

### Error Notifications:
- Email sent automatically on workflow failures (Workflow 5)
- Cronitor alerts via email for missed runs
- Check Gmail for alerts with prefix: `⚠️ n8n Error`

### Health Checks:
Run daily health check query:
```sql
-- In VS Code SQLTools or DBeaver
\i ~/content-digest-automation/sql/health_check_daily.sql
```

### System State Check:
```sql
-- View current cycle information
SELECT 
  value->>'current_topic' as topic,
  value->>'period_start' as period_start,
  value->>'period_end' as period_end,
  value->>'cycle_index' as cycle_index,
  updated_at,
  AGE(NOW(), updated_at) as age
FROM system_state 
WHERE key = 'current_cycle';
```

**Note:** If age > 4 days, Workflow 0 may not be running!

### Execution History:
- n8n UI → "Executions" tab
- Auto-purged after 30 days

### System Logs:
```bash
# Check recent logs
docker compose logs n8n --tail 100

# Follow live logs
docker compose logs -f

# System metrics
https://cockpit.walterlabs.net
```

## 🔐 Security

- ✅ HTTPS with Let's Encrypt SSL certificates
- ✅ UFW firewall configured
- ✅ fail2ban brute-force protection on SSH
- ✅ Services bound to localhost only (Nginx reverse proxy)
- ✅ PostgreSQL isolated in Docker network
- ✅ n8n Basic Auth enabled
- ✅ All credentials stored in .env (not committed to git)
- ✅ External monitoring via Cronitor
- ✅ Server timezone properly configured (Europe/Rome)

## 📦 Data Retention

- **Execution History**: 30 days (auto-pruned)
- **Database Items**: 30 days (Workflow 6 purger)
- **Database Backups**: 30 days rolling window
- **n8n Logs**: Pruned automatically via `EXECUTIONS_DATA_PRUNE`

## 🎯 RSS Sources

### AI (Topic Code: 0)
- VentureBeat AI
- AI4Business (Italian)

### Finance (Topic Code: 1)
- CNBC
- Il Sole 24 Ore Economia (Italian)

### Music (Topic Code: 2)
- Avant Music News
- Billboard IT (Italian)

### Science (Topic Code: 3)
- ScienceDaily
- Le Scienze (Italian)

## 🏗️ Architecture Highlights

### Centralized State Management
**Problem:** Original design had 4 separate period calculations leading to potential inconsistency and timezone bugs.

**Solution:** Single `system_state` table acts as source of truth:
```
Workflow 0: Calculate ONCE → Store in system_state
Workflows 1-3: Read from system_state → Guaranteed consistency
```

**Benefits:**
- ✅ Fix bugs in one place
- ✅ Guaranteed period consistency across all workflows
- ✅ Timezone handling centralized
- ✅ Queryable current state at any time

**Schema:**
```sql
CREATE TABLE system_state (
  id SERIAL PRIMARY KEY,
  key TEXT UNIQUE NOT NULL,
  value JSONB NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

**Example data:**
```json
{
  "current_topic": "AI",
  "cycle_index": 0,
  "period_start": "2026-03-01",
  "period_end": "2026-03-03",
  "calculated_at": "2026-03-04T02:00:00.000Z"
}
```

### Timezone Handling
**Problem:** Using `toISOString()` caused 1-day offset in UTC+1 timezone. Server timezone UTC vs n8n Europe/Rome caused execution time mismatches.

**Solution:** 
1. **Server timezone set to Europe/Rome:**
```bash
   sudo timedatectl set-timezone Europe/Rome
```

2. **Custom `formatLocalDate()` function in Workflow 0:**
```javascript
   function formatLocalDate(date) {
     const year = date.getFullYear();
     const month = String(date.getMonth() + 1).padStart(2, '0');
     const day = String(date.getDate()).padStart(2, '0');
     return `${year}-${month}-${day}`;
   }
```

Used **only once** in Workflow 0 - all other workflows read pre-formatted dates.

**Critical:** Both server and n8n must use Europe/Rome timezone for correct cron execution.

### Graceful 0-Item Handling

**Problem:** Original design broke chain when no items needed processing.

**Solution:** IF nodes with "Always Output Data" in Workflows 2, 3, 4:
```
SQL Query (Always Output Data enabled)
    ↓
IF Node (checks for real data)
    ├─ TRUE → Process normally
    └─ FALSE → Skip to logging
    ↓
Both paths merge → Create Log → Continue chain
```

**Benefits:**
- ✅ Chain always completes (never stops mid-flow)
- ✅ Proper logging of "0 items processed"
- ✅ Cronitor Monitor 3 always pings (complete chain)
- ✅ Clear visibility when no work needed

**Events logged:**
- `no_items_to_digest` - No items available for digest
- `digest_already_exists` - Digest already created for this period
- `no_digest_to_distribute` - No unpublished digest available

### Duplicate Prevention

**Workflow 3 (Digest Generation):**
- Checks if digest exists for period **before** creating
- IF condition uses AND: items exist AND no existing digest
- Prevents creating multiple digests for same period

**Workflow 4 (Distribution):**
- Queries only unpublished digests (`WHERE published_at IS NULL`)
- Marks digest as published after successful distribution
- Next run finds no unpublished digests

**Database constraints:**
- `items.url` UNIQUE - prevents duplicate articles from same source
- `system_state.key` UNIQUE - prevents duplicate state entries

### Loop and Counting Patterns

**Problem:** Can't accurately count loop iterations from outside the loop.

**Solutions:**

1. **Reference nodes before loop:**
   - "3-Day Filter" (before loop) has all items
   - "Create Batches" (before loop) has batch count

2. **Database count queries:**
   - Count items inserted in last 1-2 minutes
   - Executes after loop completes
   - Connected to loop's "Done" output

3. **Connect Create Log to "Done" branch:**
   - Not inside loop
   - Executes once after all iterations complete

**Pattern:**
```
Loop Over Items (processes sources)
    ↓ (Done output)
Count Inserted Items (SQL query, runs once)
    ↓
Create Log (references count, runs once)
    ↓
Store Log
    ↓
Execute Sub-Workflow
```

### Try-Catch for Branch Handling

**Problem:** When IF nodes create branches, some nodes only execute in TRUE branch. Create Log (outside branches) can't always reference them.

**Solution:** Use try-catch in Create Log nodes:
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

**Used in:**
- Workflow 2: Create Log (enrichment path)
- Workflow 3: Create Log (digest creation path)
- Workflow 4: Create Log (distribution path)
- Workflow 6: Create Log (purge path)

### Workflow Chaining

Using "Execute Sub-Workflow" with "Wait for Completion":
- Ensures sequential execution
- Each workflow completes before next starts
- Prevents race conditions
- Easier debugging (linear execution path)
- **Use "From List" not "By ID"** to avoid reference errors after refactoring

### External Monitoring

Cronitor monitors:
- **Backup**: Daily at 01:00 (via crontab curl)
- **Workflow 0**: Every 3-day pattern at 02:00 (via HTTP Request)
- **Complete Chain**: Heartbeat after Workflow 4 (via HTTP Request)

**Independent of VPS:**
- Alerts even if VPS is down
- Tracks execution history and trends
- Multiple notification channels
- Single dashboard for all jobs

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

**Symptoms of stale cache:**
- Nodes show old parameter values
- "Referenced node doesn't exist" errors
- Changes don't seem to take effect
- Execute Sub-Workflow fails after refactoring

## 🤝 Maintenance

### Daily
- Review Cronitor dashboard
- Check error emails (if any)

### Weekly
- Review digest quality
- Monitor VPS disk space: `df -h`
- Verify system state consistency
- Check execution times in n8n
- Test Google OAuth credential health

### Monthly
- Test backup restoration
- Review and optimize Claude prompts
- Check for n8n updates
- Verify SSL certificate renewal (auto-renewed by certbot)
- Review Cronitor monitor configurations
- **Reconnect Google OAuth credentials preemptively** (prevent expiration)

### Quarterly
- Audit security settings
- Review workflow performance and optimize
- Check for n8n breaking changes
- Verify all API credentials still valid

### After Workflow Changes

**Checklist:**
1. ✅ Save workflow (Ctrl+S)
2. ✅ Close and reopen workflow tab (clear n8n cache)
3. ✅ Test manually (don't rely on scheduled run)
4. ✅ Test both TRUE and FALSE branch outcomes (if using IF nodes)
5. ✅ Verify logging is accurate
6. ✅ Download updated JSON
7. ✅ Commit to version control
8. ✅ Document changes

## 📝 Documentation

- **Setup Guide**: [docs/setup.md](docs/setup.md)
- **Workflow Details**: [docs/workflows.md](docs/workflows.md)
- **Troubleshooting**: [docs/troubleshooting.md](docs/troubleshooting.md)

## 🔗 Useful Links

- [n8n Documentation](https://docs.n8n.io)
- [Anthropic Claude API](https://docs.anthropic.com)
- [PostgreSQL Docs](https://www.postgresql.org/docs/)
- [Docker Compose Reference](https://docs.docker.com/compose/)
- [Cron Expression Helper](https://crontab.guru/)
- [Cronitor Documentation](https://cronitor.io/docs/)

## 📊 System Requirements

- **VPS**: 2 vCPU, 4GB RAM, 70GB SSD minimum
- **Network**: Stable connection, ports 80/443/22 open
- **Domain**: Registered domain with DNS control
- **Timezone**: Server must be set to Europe/Rome

## 🎉 Production Status

✅ **Live and Operational**

- Workflows run on days 1, 4, 7, 10, 13, 16, 19, 22, 25, 28, 31 at 02:00 Europe/Rome
- Backups run daily at 01:00 AM Europe/Rome
- System state centralized for consistency
- All timezone bugs resolved
- External monitoring via Cronitor
- Error notifications enabled
- Graceful 0-item handling implemented
- Duplicate prevention active

**Architecture Version:** 1.2.0
- Centralized state management via system_state table
- Timezone properly configured (server + n8n = Europe/Rome)
- IF nodes for graceful 0-item scenarios
- Try-catch patterns for branch handling
- Loop counting via database queries
- Duplicate digest and distribution prevention
- n8n caching behavior documented and managed

**Next scheduled run:** Check Cronitor dashboard or calculate next day matching pattern (1, 4, 7, 10, etc.)

**Current cycle info:**
```sql
SELECT 
  value->>'current_topic' as topic,
  value->>'period_start' as period_start,
  value->>'period_end' as period_end,
  updated_at,
  AGE(NOW(), updated_at) as age
FROM system_state WHERE key = 'current_cycle';
```

## 🐛 Known Issues & Gotchas

### n8n Specific

1. **Node caching after refactoring:** Always save, close, reopen workflow after structural changes
2. **Execute Sub-Workflow errors:** Delete and recreate using "From List" if "Referenced node doesn't exist"
3. **Loop counting:** Can't count iterations from outside loop - use database queries or reference pre-loop nodes
4. **IF nodes with Always Output Data:** Check for real data (`.id`), not just `.length > 0`
5. **Credential validation:** n8n checks credentials upfront, can block unrelated workflows if one credential expires

### Timezone Critical

1. **Server timezone MUST be Europe/Rome:** Otherwise cron jobs run at wrong times
2. **Both server and n8n must match:** Prevents execution time confusion
3. **Cronitor monitors use Europe/Rome:** Timezone mismatch causes "missed" alerts

### Google OAuth

1. **Credentials expire:** Reconnect monthly to prevent mid-workflow failures
2. **If reconnect fails:** Delete and create new credential
3. **Preemptive maintenance:** Don't wait for expiration - refresh proactively

### Database Queries

1. **Count recent items:** Use 1-2 minute intervals, not 5 minutes (prevents duplicate counts on re-runs)
2. **Always Output Data:** SQL nodes return 1 empty item when 0 rows, filter with `.filter(item => item.json.id)`

## 📄 License

Private project - Internal use only

---

**Last Updated**: March 4, 2026  
**Version**: 1.2.0 (Production - Graceful 0-Item Handling + Duplicate Prevention + Timezone Alignment)
**System Status**: Fully operational with comprehensive monitoring