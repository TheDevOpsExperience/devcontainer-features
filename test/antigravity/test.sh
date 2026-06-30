#!/bin/bash
set -e

source dev-container-features-test-lib

# The bootstrapper installs `agy` into the remote user's ~/.local/bin.
check "agy CLI installed" bash -c 'for h in "$HOME" /home/* /root; do [ -x "$h/.local/bin/agy" ] && exit 0; done; command -v agy'
check "antigravity domains registered" test -f /usr/local/share/devcontainer/domains.d/antigravity.conf
# The symlink is created for the remote user, whose home may differ from the
# test step's $HOME — scan the common home locations.
check "~/.gemini symlinked to volume" bash -c '
  for h in "$HOME" /home/* /root; do
    [ -L "$h/.gemini" ] && [ "$(readlink "$h/.gemini")" = /dc-volumes/gemini ] && exit 0
  done
  exit 1'

# ── Install-time artifacts ────────────────────────────────────────────────────
check "antigravity rules-base copied"     test -f /usr/local/share/devcontainer/antigravity/rules-base.md
check "antigravity rules-firewall copied" test -f /usr/local/share/devcontainer/antigravity/rules-firewall.md
check "antigravity lifecycle setup installed"  test -x /usr/local/share/devcontainer/antigravity/setup.sh
check "antigravity lifecycle create installed" test -x /usr/local/share/devcontainer/antigravity/create.sh

# ── Functional: setup.sh merges rules into ~/.gemini/antigravity/AGENTS.md
# WITHOUT clobbering the user's content. No firewall feature here → base only.
check "antigravity rules merge preserves user AGENTS.md" bash -c '
  set -e
  mkdir -p "$HOME/.gemini/antigravity"
  printf "# user\nSENTINEL_KEEP\n" > "$HOME/.gemini/antigravity/AGENTS.md"
  /usr/local/share/devcontainer/antigravity/setup.sh
  grep -q SENTINEL_KEEP "$HOME/.gemini/antigravity/AGENTS.md" &&
  test "$(grep -cxF "@./devcontainer-rules.md" "$HOME/.gemini/antigravity/AGENTS.md")" = 1 &&
  test -f "$HOME/.gemini/antigravity/devcontainer-rules.md" &&
  grep -q "Installing packages" "$HOME/.gemini/antigravity/devcontainer-rules.md"
'

reportResults
