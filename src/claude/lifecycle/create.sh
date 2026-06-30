#!/bin/bash
set -e

# Add Claude Code alias, opting into --dangerously-skip-permissions if the flag
# was set at image-build time via the feature's skip_permissions option.
if [ -f /usr/local/share/devcontainer/.claude-skip-permissions ]; then
  echo 'alias claude="$HOME/.local/bin/claude --dangerously-skip-permissions"' >> ~/.zshrc
else
  echo 'alias claude="$HOME/.local/bin/claude"' >> ~/.zshrc
fi
