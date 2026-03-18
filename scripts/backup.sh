#!/bin/bash

# Database Backup Script
# Run with: bash scripts/backup.sh

BACKUP_DIR=~/content-digest-automation/backups
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="ai_digest_backup_${TIMESTAMP}.sql"

echo "Creating backup: ${BACKUP_FILE}"

docker exec n8n-postgres pg_dump \
  -U ai_digest \
  -d ai_digest_db \
  --clean \
  --if-exists \
  > "${BACKUP_DIR}/${BACKUP_FILE}"

# Compress
gzip "${BACKUP_DIR}/${BACKUP_FILE}"

echo "Backup complete: ${BACKUP_DIR}/${BACKUP_FILE}.gz"

# Keep only last 10 backups
cd "${BACKUP_DIR}"
ls -t *.gz | tail -n +11 | xargs -r rm

echo "Old backups cleaned up"