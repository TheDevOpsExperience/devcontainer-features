#!/bin/bash
set -e

source dev-container-features-test-lib

# ── Install-time artifacts ────────────────────────────────────────────────────
check "claude rules-base copied"      test -f /usr/local/share/devcontainer/rules-base.md
check "claude rules-firewall copied"  test -f /usr/local/share/devcontainer/rules-firewall.md
check "claude statusline default copied" test -f /usr/local/share/devcontainer/statusline.sh
check "claude lifecycle setup installed"  test -x /usr/local/share/devcontainer/claude/setup.sh
check "claude lifecycle create installed" test -x /usr/local/share/devcontainer/claude/create.sh

# ── Functional: setup.sh merges rules WITHOUT clobbering the user's CLAUDE.md ──
# No firewall feature in this scenario, so only the base rules apply.
check "claude rules merge preserves user CLAUDE.md" bash -c '
  set -e
  mkdir -p "$HOME/.claude"
  printf "# user\nSENTINEL_KEEP\n" > "$HOME/.claude/CLAUDE.md"
  /usr/local/share/devcontainer/claude/setup.sh
  grep -q SENTINEL_KEEP "$HOME/.claude/CLAUDE.md" &&
  test "$(grep -cxF "@devcontainer-rules.md" "$HOME/.claude/CLAUDE.md")" = 1 &&
  test -f "$HOME/.claude/devcontainer-rules.md" &&
  grep -q "Installing packages" "$HOME/.claude/devcontainer-rules.md"
'

reportResults
