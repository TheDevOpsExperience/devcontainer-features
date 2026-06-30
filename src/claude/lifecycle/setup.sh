#!/bin/bash
set -e

DEFAULTS="/usr/local/share/devcontainer"
CLAUDE_DIR="$HOME/.claude"
IMPORT_LINE="@devcontainer-rules.md"

# Feature rules live in their own file — always overwrite so image rebuilds
# propagate updates. The user's CLAUDE.md is never clobbered.
#
# Base rules (package install) always apply — install-package.sh comes from core.
# Firewall rules are appended only when the firewall feature is present, detected
# by its CLI on PATH. All install.sh run before any lifecycle hook, so this is
# reliable regardless of feature order.
RULES="$CLAUDE_DIR/devcontainer-rules.md"
if [ -f "$DEFAULTS/rules-base.md" ]; then
  cp -f "$DEFAULTS/rules-base.md" "$RULES"
  if [ -x /usr/local/bin/list-domains.sh ] && [ -f "$DEFAULTS/rules-firewall.md" ]; then
    printf '\n' >> "$RULES"
    cat "$DEFAULTS/rules-firewall.md" >> "$RULES"
  fi
fi
cp -f "$DEFAULTS/statusline.sh" "$CLAUDE_DIR/statusline.sh" 2>/dev/null || true

# Ensure CLAUDE.md imports the feature rules (create if missing, append once).
# Idempotent: runs on every container start, never duplicates the import line.
if [ ! -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  printf '%s\n' "$IMPORT_LINE" > "$CLAUDE_DIR/CLAUDE.md"
elif ! grep -qxF "$IMPORT_LINE" "$CLAUDE_DIR/CLAUDE.md"; then
  printf '\n%s\n' "$IMPORT_LINE" >> "$CLAUDE_DIR/CLAUDE.md"
fi

# Seed settings only if missing; otherwise merge to preserve user customizations
if [ ! -f "$CLAUDE_DIR/settings.json" ]; then
  cp "$DEFAULTS/settings.json" "$CLAUDE_DIR/settings.json" 2>/dev/null || true
else
  jq -s ".[0] * .[1]" "$DEFAULTS/settings.json" "$CLAUDE_DIR/settings.json" > /tmp/claude-settings.json
  cp -f /tmp/claude-settings.json "$CLAUDE_DIR/settings.json"
fi
