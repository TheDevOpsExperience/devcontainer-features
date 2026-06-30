#!/bin/bash
set -e

source dev-container-features-test-lib

check "gemini CLI installed" bash -c "command -v gemini"

# ── Install-time artifacts ────────────────────────────────────────────────────
check "gemini rules-base copied"     test -f /usr/local/share/devcontainer/gemini/rules-base.md
check "gemini rules-firewall copied" test -f /usr/local/share/devcontainer/gemini/rules-firewall.md
check "gemini lifecycle setup installed"  test -x /usr/local/share/devcontainer/gemini/setup.sh
check "gemini lifecycle create installed" test -x /usr/local/share/devcontainer/gemini/create.sh

# ── Functional: setup.sh merges rules WITHOUT clobbering the user's GEMINI.md ──
# No firewall feature in this scenario, so only the base rules apply.
check "gemini rules merge preserves user GEMINI.md" bash -c '
  set -e
  mkdir -p "$HOME/.gemini"
  printf "# user\nSENTINEL_KEEP\n" > "$HOME/.gemini/GEMINI.md"
  /usr/local/share/devcontainer/gemini/setup.sh
  grep -q SENTINEL_KEEP "$HOME/.gemini/GEMINI.md" &&
  test "$(grep -cxF "@./devcontainer-rules.md" "$HOME/.gemini/GEMINI.md")" = 1 &&
  test -f "$HOME/.gemini/devcontainer-rules.md" &&
  grep -q "Installing packages" "$HOME/.gemini/devcontainer-rules.md"
'

reportResults
