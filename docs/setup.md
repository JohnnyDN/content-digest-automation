# Setup Guide
*Last updated: March 18, 2026*
Complete guide for deploying the Content Digest automation system from scratch.

## Prerequisites

- Ubuntu 24.04 LTS VPS (OVH or similar)
- Domain name with DNS control
- Claude API key (Anthropic)
- Google OAuth credentials
- Notion integration token
- Basic terminal/SSH knowledge

## Part 1: VPS Initial Setup

### 1.1 SSH Access

**Connect to VPS:**
```bash
ssh ubuntu@YOUR_VPS_IP
```

**If password authentication fails:**
- Boot to OVH rescue mode
- Mount partition: `mount /dev/sda1 /mnt`
- Edit sshd config: `nano /mnt/etc/ssh/sshd_config`
- Uncomment: `PasswordAuthentication yes`
- Set password: `chroot /mnt && passwd ubuntu`
- Reboot to normal mode

### 1.2 System Updates
```bash
sudo apt update && sudo apt upgrade -y
```

### 1.3 Security Hardening

**Configure UFW Firewall:**
```bash
sudo apt install ufw -y
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status
```

**Install fail2ban:**
```bash
sudo apt install fail2ban -y
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

**Whitelist your IP in fail2ban:**
```bash
sudo nano /etc/fail2ban/jail.local
```

Add:
```ini
[DEFAULT]
ignoreip = 127.0.0.1/8 YOUR_IP_ADDRESS

[sshd]
maxretry = 5
```

Restart:
```bash
sudo systemctl restart fail2ban
```

### 1.4 Install Docker

**Add Docker repository:**
```bash
sudo apt install ca-certificates curl gnupg lsb-release -y
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

**Install Docker:**
```bash
sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
```

**Add user to docker group:**
```bash
sudo usermod -aG docker $USER
newgrp docker
```

**Verify:**
```bash
docker --version
docker compose version
```

## Part 2: Project Setup

### 2.1 Create Project Structure
```bash
cd ~
mkdir -p content-digest-automation/{infra,workflows,sql,scripts,backups,docs}
cd content-digest-automation
```

### 2.2 Create .env File
```bash
nano infra/.env
```

**Paste:**
```env
# Database
POSTGRES_USER=ai_digest
POSTGRES_PASSWORD=CHANGE_ME_strong_password
POSTGRES_DB=ai_digest_db

# n8n
N8N_PORT=5678
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=CHANGE_ME_admin_password

# URLs (update after domain setup)
WEBHOOK_URL=https://YOUR_DOMAIN/
N8N_EDITOR_BASE_URL=https://YOUR_DOMAIN

# Config
GENERIC_TIMEZONE=Europe/Rome

# API Keys
CLAUDE_API_KEY=sk-ant-api03-YOUR_KEY_HERE
```

**Replace all CHANGE_ME and YOUR_* placeholders!**

### 2.3 Create docker-compose.yml
```bash
nano infra/docker-compose.yml
```

**Paste:**
```yaml
services:
  postgres:
    image: postgres:16
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U ${POSTGRES_USER}']
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - ai_digest_net

  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    ports:
      - "127.0.0.1:5678:5678"
    environment:
      # Auth
      N8N_BASIC_AUTH_ACTIVE: ${N8N_BASIC_AUTH_ACTIVE}
      N8N_BASIC_AUTH_USER: ${N8N_BASIC_AUTH_USER}
      N8N_BASIC_AUTH_PASSWORD: ${N8N_BASIC_AUTH_PASSWORD}

      # URLs
      WEBHOOK_URL: ${WEBHOOK_URL}
      N8N_EDITOR_BASE_URL: ${N8N_EDITOR_BASE_URL}

      # Timezone
      GENERIC_TIMEZONE: ${GENERIC_TIMEZONE}

      # Database
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: ${POSTGRES_DB}
      DB_POSTGRESDB_USER: ${POSTGRES_USER}
      DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}

      # API Keys
      ANTHROPIC_API_KEY: ${CLAUDE_API_KEY}

      # Execution Pruning
      EXECUTIONS_DATA_PRUNE: "true"
      EXECUTIONS_DATA_MAX_AGE: 720
      EXECUTIONS_DATA_PRUNE_MAX_COUNT: 10000

    volumes:
      - n8n_data:/home/node/.n8n
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - ai_digest_net

volumes:
  postgres_data:
  n8n_data:

networks:
  ai_digest_net:
    driver: bridge
```

### 2.4 Start Services
```bash
cd ~/content-digest-automation/infra
docker compose up -d
docker compose ps
```

**Should see both containers running!**

## Part 3: Domain & SSL Setup

### 3.1 Register Domain

Register domain at Cloudflare (or your preferred registrar).

### 3.2 Configure DNS

**In Cloudflare DNS:**

Add A records:
```
Type: A
Name: n8n
IPv4: YOUR_VPS_IP
Proxy: DNS only (gray cloud)

Type: A
Name: portainer
IPv4: YOUR_VPS_IP

Type: A
Name: cockpit
IPv4: YOUR_VPS_IP
```

**Wait for DNS propagation (2-5 minutes).**

Test:
```bash
ping n8n.yourdomain.net
```

### 3.3 Install Nginx & Certbot
```bash
sudo apt install nginx certbot python3-certbot-nginx -y
```

### 3.4 Configure Nginx for n8n
```bash
sudo nano /etc/nginx/sites-available/n8n
```

**Paste:**
```nginx
server {
    listen 80;
    server_name n8n.yourdomain.net;

    location / {
        proxy_pass http://localhost:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
```

**Enable:**
```bash
sudo ln -s /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

### 3.5 Get SSL Certificate
```bash
sudo certbot --nginx -d n8n.yourdomain.net
```

Select option **2** (redirect HTTP to HTTPS).

**Update .env with domain:**
```bash
nano ~/content-digest-automation/infra/.env
```

Change:
```env
WEBHOOK_URL=https://n8n.yourdomain.net/
N8N_EDITOR_BASE_URL=https://n8n.yourdomain.net
```

**Restart n8n:**
```bash
cd ~/content-digest-automation/infra
docker compose restart n8n
```

### 3.6 Access n8n

Open: `https://n8n.yourdomain.net`

Create owner account when prompted.

## Part 4: Database Initialization

### 4.1 Create Schema

**Copy schema file to VPS** (or create manually):
```bash
nano ~/content-digest-automation/sql/01_schema.sql
```

Paste schema from exported local database.

**Important:** Schema must include `system_state` table:
```sql
CREATE TABLE system_state (
  id SERIAL PRIMARY KEY,
  key TEXT UNIQUE NOT NULL,
  value JSONB NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_system_state_key ON system_state(key);
```

**Run schema:**
```bash
docker exec -i infra-postgres-1 psql -U ai_digest -d ai_digest_db < ~/content-digest-automation/sql/01_schema.sql
```

### 4.2 Load Initial Data
```bash
nano ~/content-digest-automation/sql/02_initial_data.sql
```

Paste initial data (sources, infographic_styles).

**Run:**
```bash
docker exec -i infra-postgres-1 psql -U ai_digest -d ai_digest_db < ~/content-digest-automation/sql/02_initial_data.sql
```

### 4.3 Verify
```bash
docker exec -it infra-postgres-1 psql -U ai_digest -d ai_digest_db -c "\dt"
```

Should list all tables including `system_state`!

## Part 5: n8n Workflows

### 5.1 Import Workflows

In n8n UI:
1. Click **"+"** → **"Import from File"**
2. Select workflow JSON from `~/content-digest-automation/workflows/`
3. Repeat for all 7 workflows

### 5.2 Configure Credentials

**PostgreSQL:**
- Host: `postgres`
- Database: `ai_digest_db`
- User: `ai_digest`
- Password: (from .env)
- Port: 5432
- SSL: Disable

**Anthropic API:**
- API Key: (from .env)

**Google OAuth:**
- Create OAuth client in Google Cloud Console
- Add redirect URI: `https://n8n.yourdomain.net/rest/oauth2-credential/callback`
- Copy Client ID and Secret to n8n

**Notion:**
- Integration secret from Notion
- Grant access to Content Calendar database

**Gmail:**
- Use same Google OAuth as Docs

### 5.3 Activate Workflow 5 First

**Error Logger must be active before linking others!**

### 5.4 Link Error Logger

For Workflows 0, 1, 2, 3, 4, 6:
- Settings → Error Workflow → Select "05 - Error Logger"

### 5.5 Test Each Workflow

Manually execute in order:
1. Workflow 0
2. Workflow 1
3. Workflow 2
4. Workflow 3
5. Workflow 4
6. Workflow 6

## Part 6: Automation & Monitoring

### 6.1 Set Up Workflow Chaining

Workflow 0 triggers the chain. See [workflows.md](workflows.md) for details.

### 6.2 Automated Backups
```bash
crontab -e
```

**Choose editor:** 1 (nano)

Add:
```bash
# Daily PostgreSQL backup at 01:00 (keeps last 30 days)
0 1 * * * docker exec infra-postgres-1 pg_dump -U ai_digest ai_digest_db | gzip > ~/content-digest-automation/backups/auto_backup_$(date +\%Y\%m\%d).sql.gz && find ~/content-digest-automation/backups/auto_backup_*.sql.gz -mtime +30 -delete
```

### 6.3 Set Up Cronitor Monitoring

**Sign up:** https://cronitor.io/

**Create 3 monitors:**

#### Monitor 1: Daily Backup
```
Name: PostgreSQL Backup
Type: Cron Job
Schedule: 0 1 * * *
Timezone: Europe/Rome
Grace Period: 900 seconds (15 min)
```

**Get telemetry URL and add to crontab:**
```bash
0 1 * * * docker exec infra-postgres-1 pg_dump -U ai_digest ai_digest_db | gzip > ~/content-digest-automation/backups/auto_backup_$(date +\%Y\%m\%d).sql.gz && find ~/content-digest-automation/backups/auto_backup_*.sql.gz -mtime +30 -delete && curl -fsS -m 10 --retry 5 "YOUR_CRONITOR_URL?state=complete"
```

#### Monitor 2: Workflow 0
```
Name: n8n Workflow 0 - Cycle Manager
Type: Cron Job
Schedule: 0 2 */3 * *
Timezone: Europe/Rome
Grace Period: 1800 seconds (30 min)
```

**In n8n Workflow 0, add HTTP Request node after "Store Log":**
```
Method: GET
URL: YOUR_CRONITOR_URL?state=complete
Response Format: String
```

#### Monitor 3: Complete Chain
```
Name: n8n Complete Workflow Chain
Type: Heartbeat
Expected Frequency: Every 3 days
Grace Period: 14400 seconds (4 hours)
```

**In n8n Workflow 4, add HTTP Request node after "Store Log":**
```
Method: GET
URL: YOUR_CRONITOR_URL?state=complete
Response Format: String
```

### 6.4 Install GUI Tools (Optional)

**Portainer:**
```bash
docker run -d -p 127.0.0.1:9000:9000 --name portainer --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest
```

Configure Nginx + SSL for portainer.yourdomain.net

**Cockpit:**
```bash
sudo apt install cockpit -y
sudo systemctl enable --now cockpit.socket
```

Configure localhost-only listening and Nginx proxy.

## Part 7: Final Checks

### 7.1 Security Audit
```bash
# Check firewall
sudo ufw status

# Check fail2ban
sudo fail2ban-client status sshd

# Check Docker ports
sudo netstat -tlnp | grep -E '5678|9000|9090'
```

All should show `127.0.0.1` only!

### 7.2 Test Full Chain

Manually execute Workflow 0 and verify:
- All workflows complete successfully
- System state populated
- All logs have consistent periods
- Cronitor monitors ping successfully

### 7.3 Verify System State
```sql
SELECT * FROM system_state WHERE key = 'current_cycle';
```

Should show current topic and period!

### 7.4 Verify Schedule

**Workflow 0 runs on:**
- Days 1, 4, 7, 10, 13, 16, 19, 22, 25, 28, 31 of each month
- At 02:00 Europe/Rome time
- Approximately every 3 days

## Troubleshooting

See [troubleshooting.md](troubleshooting.md) for common issues.

## Post-Setup

- Export all workflows regularly
- Monitor execution logs
- Test backup restoration monthly
- Update n8n quarterly
- Check Cronitor dashboard weekly

---

**Setup Complete!** 🎉

System is now production-ready with:
- Centralized state management
- Automated monitoring
- Timezone handling fixed
- Full error tracking

**Next scheduled run:** Check Cronitor dashboard or calculate next day matching pattern (1, 4, 7, 10, etc.)

## Git Repository Setup

### Initial Setup
The repository is hosted at:
`https://github.com/JohnnyDN/content-digest-automation`

Clone and set up:
```bash
git clone https://github.com/JohnnyDN/content-digest-automation.git
cd content-digest-automation

# Install pre-commit hook
bash scripts/install-hooks.sh

# Create secrets file
cp scripts/secrets.conf.example scripts/secrets.conf
nano scripts/secrets.conf  # Fill in real values
```

### secrets.conf Format
```
# Format: PLACEHOLDER|REAL_VALUE
CRONITOR_CYCLE_MANAGER_URL|https://cronitor.link/p/YOUR_KEY/YOUR_MONITOR?state=complete
CRONITOR_DISTRIBUTION_URL|https://cronitor.link/p/YOUR_KEY/YOUR_MONITOR?state=complete
YOUR_EMAIL|your@email.com
```

### Committing Workflow Changes
After modifying workflows in n8n:
1. Re-export the workflow JSON from n8n
2. Save to `workflows/` folder
3. `git add -A && git commit` — sanitization runs automatically
4. Verify with `git diff workflows/` before pushing

### Version & Date Management
- Version is stored in the `VERSION` file at the root of the project
- To bump the version, edit `VERSION` before committing:
```
  nano ~/content-digest-automation/VERSION
```
- `**Last Updated**` and `**Version**` in all staged `.md` files are updated
  automatically by the pre-commit hook — no manual editing needed

### Security Notes
- `.env` is gitignored — never committed
- `secrets.conf` is gitignored — never committed
- `backups/` is gitignored — never committed
- Workflow JSONs are sanitized automatically on commit
- n8n credential IDs in workflows are safe — useless without access to the instance