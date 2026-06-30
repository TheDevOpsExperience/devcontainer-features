#!/bin/bash
set -e

# ── Devcontainer rules → AGENTS.md ────────────────────────────────────────────
# Runs on every container start (postStartCommand). Antigravity reads global
# instructions from ~/.gemini/antigravity/AGENTS.md (on the shared ~/.gemini
# volume) and supports import directives. So, like the gemini feature, we keep
# feature rules in their own file (~/.gemini/antigravity/devcontainer-rules.md,
# overwritten each start so image rebuilds propagate) and just ensure AGENTS.md
# imports it. The user's own AGENTS.md content is never clobbered.
#
# Base rules (package install) always apply. Firewall rules are appended only
# when the firewall feature is present, detected by its CLI on PATH.
DEFAULTS="/usr/local/share/devcontainer/antigravity"
AGY_DIR="$HOME/.gemini/antigravity"
IMPORT_LINE="@./devcontainer-rules.md"
RULES="$AGY_DIR/devcontainer-rules.md"

mkdir -p "$AGY_DIR"
if [ -f "$DEFAULTS/rules-base.md" ]; then
  cp -f "$DEFAULTS/rules-base.md" "$RULES"
  if [ -x /usr/local/bin/list-domains.sh ] && [ -f "$DEFAULTS/rules-firewall.md" ]; then
    printf '\n' >> "$RULES"
    cat "$DEFAULTS/rules-firewall.md" >> "$RULES"
  fi
fi

# Ensure AGENTS.md imports the feature rules (create if missing, append once).
# Idempotent — never duplicates the import line across restarts.
if [ ! -f "$AGY_DIR/AGENTS.md" ]; then
  printf '%s\n' "$IMPORT_LINE" > "$AGY_DIR/AGENTS.md"
elif ! grep -qxF "$IMPORT_LINE" "$AGY_DIR/AGENTS.md"; then
  printf '\n%s\n' "$IMPORT_LINE" >> "$AGY_DIR/AGENTS.md"
fi
