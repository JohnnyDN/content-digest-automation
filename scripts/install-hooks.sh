#!/bin/bash

# ============================================
# INSTALL GIT HOOKS
# Run once after cloning the repo
# ============================================

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"

cp "$REPO_ROOT/scripts/pre-commit.sh" "$HOOKS_DIR/pre-commit"
chmod +x "$HOOKS_DIR/pre-commit"

echo "✅ Git hooks installed successfully."
echo "   Pre-commit sanitization will run automatically on every commit."
