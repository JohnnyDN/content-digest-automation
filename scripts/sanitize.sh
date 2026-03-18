#!/bin/bash

# ============================================
# SANITIZE WORKFLOWS BEFORE GIT COMMIT
# Replaces real values with placeholders
# using secrets.conf as the mapping source
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="$SCRIPT_DIR/secrets.conf"
WORKFLOWS_DIR="$SCRIPT_DIR/../workflows"

# Check secrets.conf exists
if [ ! -f "$SECRETS_FILE" ]; then
  echo "❌ secrets.conf not found at $SECRETS_FILE"
  echo "   Create it from scripts/secrets.conf.example"
  exit 1
fi

echo "🔍 Sanitizing workflow files..."

CHANGES_MADE=0

# Loop through each line in secrets.conf
while IFS='|' read -r placeholder real_value || [ -n "$placeholder" ]; do
  # Skip empty lines and comments
  [[ -z "$placeholder" || "$placeholder" =~ ^# ]] && continue

  # Replace in all workflow JSON files
  find "$WORKFLOWS_DIR" -name "*.json" | while read -r file; do
    if grep -qF "$real_value" "$file"; then
      sed -i "s|$real_value|$placeholder|g" "$file"
      echo "   ✅ Replaced $placeholder in $(basename "$file")"
      CHANGES_MADE=1
    fi
  done

done < "$SECRETS_FILE"

if [ $CHANGES_MADE -eq 1 ]; then
  echo ""
  echo "⚠️  Sensitive values were replaced with placeholders."
  echo "   Workflow files have been modified and re-staged."
  # Re-stage the sanitized files
  git add "$WORKFLOWS_DIR"/*.json 2>/dev/null
  git add "$WORKFLOWS_DIR"/*\ *.json 2>/dev/null
fi

echo ""
echo "✅ Sanitization complete."