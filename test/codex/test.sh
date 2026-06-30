#!/bin/bash
set -e

source dev-container-features-test-lib

# The bootstrapper installs `codex` into the remote user's ~/.local/bin.
check "codex CLI installed" bash -c 'for h in "$HOME" /home/* /root; do [ -x "$h/.local/bin/codex" ] && exit 0; done; command -v codex'
check "codex domains registered" test -f /usr/local/share/devcontainer/domains.d/codex.conf
# The symlink is created for the remote user, whose home may differ from the
# test step's $HOME — scan the common home locations.
check "~/.codex symlinked to volume" bash -c '
  for h in "$HOME" /home/* /root; do
    [ -L "$h/.codex" ] && [ "$(readlink "$h/.codex")" = /dc-volumes/codex ] && exit 0
  done
  exit 1'
check "~/.agents symlinked to volume" bash -c '
  for h in "$HOME" /home/* /root; do
    [ -L "$h/.agents" ] && [ "$(readlink "$h/.agents")" = /dc-volumes/codex/agents ] && exit 0
  done
  exit 1'

# ── Install-time artifacts ────────────────────────────────────────────────────
check "codex rules-base copied"     test -f /usr/local/share/devcontainer/codex/rules-base.md
check "codex rules-firewall copied" test -f /usr/local/share/devcontainer/codex/rules-firewall.md
check "codex lifecycle setup installed"  test -x /usr/local/share/devcontainer/codex/setup.sh
check "codex lifecycle create installed" test -x /usr/local/share/devcontainer/codex/create.sh

# ── Functional: setup.sh manages a marker block in AGENTS.md, preserving the
# user's own content. No firewall feature here, so only the base rules apply.
check "codex rules merge preserves user AGENTS.md" bash -c '
  set -e
  mkdir -p "$HOME/.codex"
  printf "# user\nSENTINEL_KEEP\n" > "$HOME/.codex/AGENTS.md"
  /usr/local/share/devcontainer/codex/setup.sh
  # Second run must stay idempotent (exactly one managed block).
  /usr/local/share/devcontainer/codex/setup.sh
  grep -q SENTINEL_KEEP "$HOME/.codex/AGENTS.md" &&
  test "$(grep -cF "BEGIN devcontainer-rules" "$HOME/.codex/AGENTS.md")" = 1 &&
  grep -q "Installing packages" "$HOME/.codex/AGENTS.md"
'

reportResults
