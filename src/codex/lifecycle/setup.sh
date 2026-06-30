#!/bin/bash
set -e

# ── Devcontainer rules → AGENTS.md ────────────────────────────────────────────
# Runs on every container start (postStartCommand). Codex reads global
# instructions from ~/.codex/AGENTS.md (on the volume) and has NO file-import
# syntax — files are concatenated, not included. So instead of an import line we
# manage a marker-delimited block inside AGENTS.md: the block is (re)written each
# start so image rebuilds propagate, while everything outside the markers (the
# user's own instructions) is preserved untouched.
#
# Base rules (package install) always apply. Firewall rules are appended only
# when the firewall feature is present, detected by its CLI on PATH.
#
# NOTE: a user-provided ~/.codex/AGENTS.override.md takes precedence over
# AGENTS.md at the global scope (Codex reads the override INSTEAD of AGENTS.md),
# so these rules would not apply if such an override exists. Documented in README.
DEFAULTS="/usr/local/share/devcontainer/codex"
CODEX_DIR="$HOME/.codex"
AGENTS="$CODEX_DIR/AGENTS.md"
BEGIN_MARKER="<!-- BEGIN devcontainer-rules (managed — do not edit) -->"
END_MARKER="<!-- END devcontainer-rules (managed) -->"

if [ -f "$DEFAULTS/rules-base.md" ]; then
  mkdir -p "$CODEX_DIR"

  # Build the managed block (base [+ firewall]).
  BLOCK="$(mktemp)"
  {
    printf '%s\n' "$BEGIN_MARKER"
    cat "$DEFAULTS/rules-base.md"
    if [ -x /usr/local/bin/list-domains.sh ] && [ -f "$DEFAULTS/rules-firewall.md" ]; then
      printf '\n'
      cat "$DEFAULTS/rules-firewall.md"
    fi
    printf '%s\n' "$END_MARKER"
  } > "$BLOCK"

  # Assemble into a temp file then move into place. Writing via a temp avoids the
  # self-redirect clobber (`{ cat "$AGENTS"; } > "$AGENTS"` truncates before read).
  NEW="$(mktemp)"
  if [ -f "$AGENTS" ]; then
    # User content = AGENTS with any prior managed block removed, trailing blank
    # lines trimmed (so the separator below doesn't accumulate across restarts).
    awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" '
      $0==b {skip=1; next}
      skip && $0==e {skip=0; next}
      skip {next}
      {buf[++n]=$0}
      END {last=0; for(i=1;i<=n;i++) if(buf[i] !~ /^[[:space:]]*$/) last=i;
           for(i=1;i<=last;i++) print buf[i]}
    ' "$AGENTS" > "$NEW"
    [ -s "$NEW" ] && printf '\n' >> "$NEW"   # one blank line before the block
  fi
  cat "$BLOCK" >> "$NEW"
  mv "$NEW" "$AGENTS"
  rm -f "$BLOCK"
fi
