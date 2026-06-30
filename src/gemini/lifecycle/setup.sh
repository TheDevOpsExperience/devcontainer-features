#!/bin/bash
set -e

# ── Devcontainer rules → GEMINI.md ────────────────────────────────────────────
# Runs on every container start (postStartCommand). Seeds the global Gemini
# memory (~/.gemini/GEMINI.md, on the volume) with the devcontainer rules WITHOUT
# clobbering a user-provided GEMINI.md. Feature rules live in their own file
# (~/.gemini/devcontainer-rules.md, overwritten each start so image rebuilds
# propagate); GEMINI.md just imports it via Gemini's `@file.md` syntax. The
# user's own GEMINI.md content is preserved.
#
# Base rules (package install) always apply. Firewall rules are appended only
# when the firewall feature is present, detected by its CLI on PATH.
DEFAULTS="/usr/local/share/devcontainer/gemini"
GEMINI_DIR="$HOME/.gemini"
IMPORT_LINE="@./devcontainer-rules.md"
RULES="$GEMINI_DIR/devcontainer-rules.md"

mkdir -p "$GEMINI_DIR"
if [ -f "$DEFAULTS/rules-base.md" ]; then
  cp -f "$DEFAULTS/rules-base.md" "$RULES"
  if [ -x /usr/local/bin/list-domains.sh ] && [ -f "$DEFAULTS/rules-firewall.md" ]; then
    printf '\n' >> "$RULES"
    cat "$DEFAULTS/rules-firewall.md" >> "$RULES"
  fi
fi

# Ensure GEMINI.md imports the feature rules (create if missing, append once).
# Idempotent — never duplicates the import line across restarts.
if [ ! -f "$GEMINI_DIR/GEMINI.md" ]; then
  printf '%s\n' "$IMPORT_LINE" > "$GEMINI_DIR/GEMINI.md"
elif ! grep -qxF "$IMPORT_LINE" "$GEMINI_DIR/GEMINI.md"; then
  printf '\n%s\n' "$IMPORT_LINE" >> "$GEMINI_DIR/GEMINI.md"
fi
