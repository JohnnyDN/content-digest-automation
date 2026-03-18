#!/bin/bash

# ============================================
# SANITIZE WORKFLOWS + UPDATE DOC METADATA
# Replaces real values with placeholders
# Updates Last Updated date and version
# on modified markdown files only
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
SECRETS_FILE="$SCRIPT_DIR/secrets.conf"
WORKFLOWS_DIR="$REPO_ROOT/workflows"
VERSION_FILE="$REPO_ROOT/VERSION"

# ============================================
# STEP 1: SANITIZE WORKFLOWS
# ============================================

if [ ! -f "$SECRETS_FILE" ]; then
  echo "❌ secrets.conf not found at $SECRETS_FILE"
  echo "   Create it from scripts/secrets.conf.example"
  exit 1
fi

echo "🔍 Sanitizing workflow files..."

while IFS='|' read -r placeholder real_value || [ -n "$placeholder" ]; do
  [[ -z "$placeholder" || "$placeholder" =~ ^# ]] && continue

  find "$WORKFLOWS_DIR" -name "*.json" | while read -r file; do
    if grep -qF "$real_value" "$file"; then
      sed -i "s|$real_value|$placeholder|g" "$file"
      echo "   ✅ Replaced $placeholder in $(basename "$file")"
      git add "$file" 2>/dev/null
    fi
  done

done < "$SECRETS_FILE"

# ============================================
# STEP 2: UPDATE DATE + VERSION IN CHANGED DOCS
# ============================================

if [ ! -f "$VERSION_FILE" ]; then
  echo "⚠️  VERSION file not found, skipping doc metadata update"
else
  VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')
  TODAY=$(date '+%B %-d, %Y')  # e.g. March 18, 2026

  echo ""
  echo "📝 Updating doc metadata (version: $VERSION, date: $TODAY)..."

  # Get list of staged .md files only
  STAGED_MD_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.md$')

  if [ -z "$STAGED_MD_FILES" ]; then
    echo "   No modified markdown files found, skipping."
  else
    while IFS= read -r file; do
      FULL_PATH="$REPO_ROOT/$file"

      if [ -f "$FULL_PATH" ]; then
        # Update Last Updated date
        if grep -q "\*\*Last Updated\*\*:" "$FULL_PATH"; then
          sed -i "s|\*\*Last Updated\*\*:.*|\*\*Last Updated\*\*: $TODAY|g" "$FULL_PATH"
          echo "   ✅ Updated date in $file"
        fi

        # Update version string
        if grep -q "\*\*Version\*\*:" "$FULL_PATH"; then
          sed -i "s|\*\*Version\*\*:.*|\*\*Version\*\*: $VERSION|g" "$FULL_PATH"
          echo "   ✅ Updated version in $file"
        fi

        git add "$FULL_PATH" 2>/dev/null
      fi
    done <<< "$STAGED_MD_FILES"
  fi
fi

echo ""
echo "✅ Pre-commit checks complete."